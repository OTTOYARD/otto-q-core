-- 0397  **G255: nothing on the scorecard measured whether the depot met the work side's demand. On the day's two full busy
--       days it met 37.4% and 35.4%. The learner's experiments run in a world that meets 98.8%, so no dial verdict to date
--       was measured where the operator's day is decided (G256).**
--
--       Written on 2026-09-27 (15:25-16:10 UTC, 10:25-11:10 AM CT), from 6ddd827e, validation run 6e0352a0 (while it ran
--       and after the governor stopped it at 15:46 UTC), G240's pair 76 and G161's pair 81. Read-only.

-- ══ §1 THE DAY'S SUPPLY GAP, HOUR BY HOUR ═════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_kpi_supply_gap` (0530): each car's time in `deployed`, rebuilt from its signed state transitions, sampled each
--   sim-minute against the dispatcher's own target (`ottoq_deploy_target_now`). The hour columns are the hour's mean.

\echo '=== 0397 §1 — the two full busy days after 0526: target and cars out, by hour (CT) ==='
SELECT left(r.id::text, 8) AS run, h.key AS hour_ct, (h.value->>'target')::int AS target, (h.value->>'deployed')::int AS deployed
  FROM (VALUES ('6ddd827e-b549-43cf-8154-4d1bfb20cabf'::uuid), ('6e0352a0-243d-4429-9c4d-70debc73f902'::uuid)) r(id),
       jsonb_each(public.ottoq_kpi_supply_gap(r.id)->'by_hour_ct') h
 ORDER BY 1, 2;
-- READ (2026-09-27 15:48 UTC, both runs ended by the governor at 540 sim-minutes):
--   hour   6ddd827e   6e0352a0        6ddd827e: demand 451.3 car-hours, out 168.8, unmet 282.5 (62.6%), peak shortfall 46
--    08     37 / 45    38 / 45        6e0352a0: demand 449.5 car-hours, out 159.1, unmet 290.5 (64.6%), peak shortfall 49
--    09     44 / 49    43 / 49
--    10     21 / 50    18 / 50        Two seeds, the same shape: the depot keeps up for two hours on the cars the start
--    11     13 / 49    11 / 49        deals it, then falls to a sixth to a quarter of its target by 11 and stays there.
--    12     14 / 48    13 / 48        KPI 1 read 184.6 and 173.0 hours on these runs and nothing on the scorecard read
--    13     13 / 48    10 / 48        the gap: KPI 1 has no denominator.
--    14     10 / 49     9 / 49
--    15      7 / 50     9 / 50
--    16      7 / 52     8 / 52
--    17      9 / 52     4 / 52

-- ══ §2 WHY 0530 MATERIALIZES FOUR CTES ════════════════════════════════════════════════════════════════════════════════
--
--   The per-minute count (`SELECT count(*) FROM dep WHERE dep.t0 <= m AND dep.t1 > m`) is a correlated subquery. With
--   `dep` referenced once, Postgres 12+ inlines it: each of the run's ~550 minutes re-ran the transition scan and the
--   `lead()` window over the run's ~29k `vehicle.state_changed` events. The first V3 read of 6ddd827e took 31.4 s, and
--   moving the run filter from the joined run row to `p_run` changed nothing (32 s). `AS MATERIALIZED` on `r`, `dep`,
--   `tgt` and `per_min` computes each once: 84-91 ms, the same answer. Any per-minute occupancy read over the event
--   stream has this shape; it is the second planning hazard of the day after 0396 §6's lateral read of a KPI view.

\echo '=== 0397 §2 — the applied function, timed on the full day ==='
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT public.ottoq_kpi_supply_gap('6ddd827e-b549-43cf-8154-4d1bfb20cabf');
-- READ (2026-09-27 15:40 UTC): 84-91 ms over five reads; 6e0352a0's 551 minutes in under 2 s while it ran.

-- ══ §3 THE LEARNER'S WORLD IS NOT THE OPERATOR'S ══════════════════════════════════════════════════════════════════════
--
--   The dial experiments measure their arms' supply gap too (0530 added it to the arm metrics), so the question is what
--   the learner's world looks like. G240's pair 76 runs the same hours (8 AM - 5 PM CT) of the same scenario:

\echo '=== 0397 §3(a) — supply gap on a G240 arm and the energy arm against the operator day ==='
SELECT r.label, (g->>'demand_car_hours')::numeric AS demand, (g->>'deployed_car_hours')::numeric AS deployed,
       (g->>'unmet_demand_pct')::numeric AS unmet_pct, g->'by_hour_ct'->'08' AS h08, g->'by_hour_ct'->'12' AS h12,
       g->'by_hour_ct'->'16' AS h16
  FROM (VALUES ('6ddd827e operator'::text, '6ddd827e-b549-43cf-8154-4d1bfb20cabf'::uuid),
               ('pair 76 control (e58909eb)', 'e58909eb-7e31-4858-9375-ec7ba93e1e5a'),
               ('pair 81 control (141c955f)', '141c955f-5697-4aeb-b826-c529baf6e475')) r(label, id),
       LATERAL (SELECT public.ottoq_kpi_supply_gap(r.id) AS g) x;
-- READ (2026-09-27 15:41 UTC):
--     6ddd827e operator        451.3 demand, 168.8 out, 62.6% unmet
--     pair 76 control          440.0 demand, 579.3 out,  1.2% unmet -- 80 cars out at 8 AM against a target of 45,
--                              79 until noon, then exactly on target (47-52) to 5 PM
--     pair 81 control          770.0 demand, 486.5 out, 44.0% unmet over 24 hours from 4 AM (30-minute ticks)
--   The learner's 9-hour busy day meets its demand; the operator's does not meet two thirds of it.

\echo '=== 0397 §3(b) — what the two worlds are made of: the start, the trips, the returns ==='
SELECT left(d.sim_run_id::text, 8) AS run, r.run_by,
       (SELECT count(*) FROM public.ottoq_variability_profiles vp WHERE vp.sim_run_id = d.sim_run_id) AS profile_rows,
       count(*) AS dispatches, count(d.actual_return_at) AS returned,
       round(avg(d.planned_duration_min)::numeric, 1) AS planned_avg_min,
       round(avg(d.actual_duration_min) FILTER (WHERE d.actual_return_at IS NOT NULL)::numeric, 1) AS out_avg_min,
       round(avg(d.soc_at_dispatch_pct - d.soc_at_return_pct) FILTER (WHERE d.actual_return_at IS NOT NULL)::numeric, 1) AS soc_used
  FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
 WHERE d.sim_run_id IN ('6ddd827e-b549-43cf-8154-4d1bfb20cabf', '6e0352a0-243d-4429-9c4d-70debc73f902',
                        'e58909eb-7e31-4858-9375-ec7ba93e1e5a')
 GROUP BY 1, 2, 3 ORDER BY 1;
-- READ (2026-09-27 15:50 UTC):
--     run        by             profile  dispatches  returned  planned  out     SoC used per trip
--     6ddd827e   operator_demo  1        218         208       25.1     55.2    37.1
--     6e0352a0   operator_demo  1        204         199       26.5     55.1    36.9
--     e58909eb   ab_harness     0        168         116       88.3     280.8   31.1
--   The operator's cars go out for 55 minutes and come back 37 points lower; the learner's go out for 4.7 hours and
--   come back 31 points lower. In nine hours the operator's depot takes 199-208 returns, each wanting a large charge;
--   the learner's takes 116. The twin's `twin.recharge_stranded` (a car under the deploy floor held with its charge
--   undone) fired on 882 of 6ddd827e's 991 ticks and on 22 of the arm's 90.
--
--   The cause is G219's part 3, deferred on 2026-09-26 and costed here. The operator starts through
--   `ottoq_sim_run_scenario`: `twin.ottoq_sim_seed_fleet(depot, seed, start hour)` stages the start hour's share of a
--   0.90 peak for departure (0.792 at 8 AM: 91 of 116, at 86-99%) and puts 55% of the rest AT THE GATE AT 12-47% SoC
--   (6e0352a0: 17), the others held or awaiting service; `ottoq_variability_instantiate` gives the run busy_day's
--   template (the arrival drain as SoC points per hour out, trip duration x0.3, DTC x7, idle fraction x1.9, incidents
--   x0.4); the fleet overrides (maintenance intervals x0.01/x0.02); a prime at the scenario's 0.45 peak shape (0.396 at
--   8 AM: 46 out, 13 of them inbound). `ottoq_dial_pair` resets the fleet OFFLINE AT 85-99%
--   (`ottoq_tick_invariance_reset_fleet`), starts through `twin.ottoq_sim_start_run` (a 0.55 cold-start prime) and
--   primes again at 0.70 -- all 116 primed, 81 on the road at 8 AM, no car at the gate, no template:
--   `ottoq_profile_rate_mult` returns 1 for a run with no profile row, so every rate reads its default. Two worlds by
--   construction, not by chance.
--
--   What it means: every dial verdict to date (G240's charge windows, the energy pair, the recall dials) was measured
--   in a depot that meets its demand, on the question "which setting is better when nothing is short". The operator's
--   day is decided by the charger queue. A dial that helps the queue cannot show it in a world without one, and a dial
--   that is neutral with idle chargers can be costly with none. Fixed by G256 in 0531 (applied 20260927161230): the
--   arms start through the operator's door, deterministically; 0398 reads the first pair run in that world.

-- ══ §4 KPI 1 DISAGREES WITH THE DEPLOYED TIME (OPEN) ═══════════════════════════════════════════════════════════════════
--
--   KPI 1 credits each dispatch from `dispatched_at` to its actual return or, still out, its SCHEDULED return, clipped
--   to the run. The supply gap measures the same quantity from the state stream. They disagree in both directions:

\echo '=== 0397 §4 — KPI 1 against the car-hours in `deployed` ==='
SELECT left(r.id::text, 8) AS run,
       (SELECT sum(t.v::numeric) FROM jsonb_each_text(public.ottoq_kpi_five_raw(r.id)->'asset_hours_available_per_day') AS t(k, v))
         AS kpi1_hours,
       (public.ottoq_kpi_supply_gap(r.id)->>'deployed_car_hours')::numeric AS deployed_car_hours
  FROM (VALUES ('6ddd827e-b549-43cf-8154-4d1bfb20cabf'::uuid), ('6e0352a0-243d-4429-9c4d-70debc73f902'::uuid),
               ('e58909eb-7e31-4858-9375-ec7ba93e1e5a'::uuid)) r(id);
-- READ (2026-09-27 15:52 UTC): 6ddd827e 184.57 against 168.8 (+15.8, +9.3%); 6e0352a0 173.02 against 159.1 (+13.9,
--   +8.7%); pair 76's control 514.75 against 579.3 (-64.5, -11.1%; its audit: 52 dispatches open at the horizon, 115.51
--   hours clipped). The harness arm's under-read is the scheduled-return truncation -- cars kept out past their planned
--   return are credited to the plan. The operator runs' over-read is not established here: dispatches credited before
--   the car's state reads `deployed`, or after it has come in, are the candidates. KPI 1 carries weight +0.3 in the
--   active reward weights, so both matter to the learner; which of the two measures the depot is scored on is the
--   reward-weights decision G254 left open, not a fix taken here.

-- ══ §5 THE VALIDATION RUN, 6e0352a0 ═══════════════════════════════════════════════════════════════════════════════════
--
--   busy_day, seed 5986348604352095237, 14:37-15:46 UTC (9:37-10:46 AM CT), 925 ticks, sim 8:00 AM - 5:11 PM CT. The first
--   operator run after 0526-0530. G251's reads are in 0394 §4. The scorecard, from the one command and its two companions:
--     KPI 1 asset hours 173.02 · KPI 2 turns per point 3.95 (561 cars leaving 142 points; 474 bookings done) ·
--     KPI 3 peak site kW 1,288 (demand-billing 1,214.7) · KPI 4 touches per car in 0.667 (143 technician tasks and one
--     command-centre touch on 216 arrivals) · KPI 5 p95 time to service 306.3 min (p50 3.2; 9 returns unserved)
--     charge wait (0501): 193 charged of 211 visits owing a charge, p50 16 min, p95 335.7, max 436.1; 16 still waiting
--     at the horizon, a median 347.8 minutes so far
--     supply gap (0530): 64.6% unmet, §1.
--
--   READ LIVE (2026-09-27 ~15:05-15:35 UTC, sim ~1:45-2:50 PM CT, from the live world before the teardown): 28-29 cars
--   waiting on staging stalls for a DCFC, a mean 185 minutes each; the two DCFC stalls reading `available` were the two
--   whose chargers were thermally faulted; 36 cars on chargers, every one charging to 90% (the day target), 16 of them
--   already between 80% and 90% -- above the deploy floor, able to go -- while the deploy target read 49 against 8 out.
--   A charger is a car-hour machine and the day's binding resource: every minute a charger spends taking a deployable
--   car from 80 to 90 is a minute a car below the floor waits for it. That is the first question the challenger asks
--   (0532+), and the dial experiment to answer it is `dcfc_target_soc_day` 90 against 85, primary
--   `unmet_demand_car_hours` -- registered after 0531 (experiment 08262943, 2026-09-27 16:13 UTC), so that it runs in
--   this world and not the learner's old one.
