-- 0413  **Night 1, read the morning after: OTTO-Q served more visits for less power than first come, first served, and
--        put fewer cars back to work; in every depot most of the fleet ended the day waiting in staging.** Before
--        calibration. (G300 measured; G301, G302 new)
--
--       Written 2026-09-30, 6:40 AM CT. Read-only. Sweep frontier_2026_09_29 (0568): busy_day, 12-hour test days from
--       6 AM CT (sim Tue 2026-09-01), 5-minute ticks, deploy_peak_fraction 0.90, at 10 and 20 robotic fast chargers,
--       seats otto_q / fifo / greedy. The window ran 11 PM-6 AM CT.
--
--       **BEFORE CALIBRATION. Never customer-facing.** Night 1 ran on the old charge curves (G298: I-PACE and Zoox, two
--       thirds of the fleet, charged far too slowly to 100%) and the unsourced prices (G299). 0573 and 0574 replace both
--       today. These are the before record.
--
-- ══ §1 WHAT RAN ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   20 arms (ids 3-22), every one complete, shield paid and restored, none with an error:
--     seeds 1-3 in all six cells (18 arms); the replicate of dcfc10.otto_q seed 1 (arm 9); seed 4's first arm (arm 22,
--     finished 6:12 AM CT). Seeds 4-5 wait for a later night.
--   Wall time per 12-hour arm: 831-1,543 s, mean 1,189 s (19.8 min). dcfc20.otto_q is the slowest cell (1,339 / 1,393
--   / 1,543 s), greedy the fastest.
--   About 20 minutes were lost: at 11:35:30 PM CT a manual Start in the twin (operator demo 1ccad49b) cancelled the arm
--   in flight, by design (0564). It left no row and was retried at 11:44 PM CT. Nothing was purged.
--
--   Runs (arm: cell, seed k, run):
--     3 dcfc10.otto_q k1 85a5d396  4 dcfc10.fifo k1 d038fb17  5 dcfc10.greedy k1 1edc847e
--     6 dcfc20.otto_q k1 9cbe9eae  7 dcfc20.fifo k1 55f57dfe  8 dcfc20.greedy k1 b6c8cc5b  9 dcfc10.otto_q k1 rep 8fb88df0
--     10 dcfc10.otto_q k2 13de7d61 11 dcfc10.fifo k2 6639f2cc 12 dcfc10.greedy k2 f25337e2
--     13 dcfc20.otto_q k2 14f0fe7c 14 dcfc20.fifo k2 d5280ace 15 dcfc20.greedy k2 305ac53e
--     16 dcfc10.otto_q k3 412c1595 17 dcfc10.fifo k3 a6b2f192 18 dcfc10.greedy k3 6c77c32a
--     19 dcfc20.otto_q k3 73d1cb94 20 dcfc20.fifo k3 54c25658 21 dcfc20.greedy k3 1170d0ec 22 dcfc10.otto_q k4 2c1fdb9b
--
-- ══ §2 THE FRONTIER (ottoq_throughput_frontier, means over seeds) ═════════════════════════════════════════════════════
--
--   cell            visits  cars   door p50  on time  deployed  unmet    peak    site cost  rule 9
--                   served served  (min)     (%)      car-h     demand   kW      $/day      breaches
--   dcfc10.otto_q   129.0   73.0   217       2.5      81.5      92.7%    858     1,205      0
--   dcfc10.fifo     104.0   68.7   258       0.0      130.3     88.3%    912     1,397      0
--   dcfc10.greedy   134.7   64.7   191       2.4      69.2      93.8%    908     1,333      0
--   dcfc20.otto_q   172.7   89.7   173       5.0      100.8     91.0%    1,435   1,926      0
--   dcfc20.fifo     139.0   91.0   250       1.3      169.0     84.8%    1,605   2,171      0
--   dcfc20.greedy   174.0   72.7   135       4.1      102.6     90.8%    1,726   2,153      0
--   (dcfc10.otto_q's mean includes the replicate, which repeats seed 1.)
--
-- ══ §3 OTTO-Q AGAINST EACH BASELINE, SEED BY SEED (ottoq_throughput_sweep_pairs, ottoq_margin_summary) ════════════════
--
--   Against first come, first served, the same world (world_identical on every pair):
--     10 chargers: served +16 / +38 / +34 visits; site cost -$50 / -$100 / -$207 a day; door-to-door +3 / -73 / -50 min;
--                  deployed car-hours -12.6 / -48.7 / -76.6.
--     20 chargers: served +11 / +39 / +51; site cost -$261 / -$243 / -$230; door -33 / -118 / -82;
--                  deployed car-hours -36.4 / -87 / -81.3.
--     Margin summary: cars at work -3.8 (10) and -5.7 (20); demand met -46 and -68 car-hours a 12-hour day;
--     uptime -$919 and -$1,365 a day at $20 a car-hour.
--   Against greedy: served -1.3 on both; site cost -$55 (10) and -$227 (20) a day; demand met +15 car-hours at 10,
--     -1.8 at 20.
--
--   **Read plainly:** OTTO-Q turned more visits, faster, for less power, and on every seed. It also put fewer cars back on
--   the road than first come, first served, on every seed. So on Chase's third priority (vehicle revenue and uptime),
--   before calibration, OTTO-Q lost to the plain rule. §6 says where the cars were.
--
-- ══ §4 WHERE EACH DAY'S PEAK FELL (G300) ═════════════════════════════════════════════════════════════════════════════
--
--   0577's profile, run read-only on all 20 arms: at 0 minutes it equals the scorer's peak_30min_kw and
--   demand_charge_usd_month on 20 of 20. **The opening set the whole day's peak on 20 of 20**; the peak half hour began
--   10-30 minutes in. The load it leaves then keeps falling for about three hours (19 primary arms):
--     read from   later peak still at that mark   mean peak
--     60 min      13 of 19                        1,017 kW
--     90 min       9 of 19                          977 kW
--     120 min      7 of 19                          934 kW
--     180 min      4 of 19                          849 kW
--     240 min      3 of 19                          802 kW
--   From 180 minutes most days peak in the late afternoon (arms 3, 4, 6, 7, 13, 17: 580-690 minutes in, 3:40-5:30 PM).
--   **Decision:** 0576 bills peak demand from 180 minutes (9 AM on a 6 AM test day), not 60. 0577 reads offsets to 240.
--   This is the conservative side for OTTO-Q: the longer cut removes more of the plain depot's opening tail, which its
--   battery does not shave.
--
-- ══ §5 THE REPLICATE WAS IDENTICAL, AND THE VIEW SAYS IT WAS NOT (G301) ══════════════════════════════════════════════
--
--   Arm 9 repeats arm 3 (dcfc10.otto_q, seed 1). Every hash in their atoms is equal: h_evt, h_dec, h_bkg, h_nrg,
--   h_prop, h_rule, h_cmd, h_arr, h_rcl, h_sdr, fp, clock, end state, decisions and blocked counts. Their metrics are
--   equal too: peak 822.7 kW, 118 visits, 1,036.8 unmet car-hours. ottoq_throughput_sweep_replicates still reports
--   identical = false, moved = ["run"]. The live ottoq_ab_arm_atoms includes `run`, the arm's own sim_run_id, so
--   two arms can never be identical. 0572's ottoq_throughput_cross_sweep_twins compares atoms the same way. The stub's
--   atoms carry no `run` key, which is why the tests passed.
--   Fix: 0578, the replicate and twin comparisons ignore `run`.
--
-- ══ §6 MOST OF THE FLEET ENDED THE DAY WAITING IN STAGING (G302) ═════════════════════════════════════════════════════
--
--   Ride demand is 1,114 car-hours in every arm, about 93 cars' worth on average over 12 hours, for a 116-car fleet.
--   Every arm met 6-15% of it. At 6 PM, cars staged awaiting service (atoms.end.by_state), against cars deployed:
--     otto_q  dcfc10: 74, 68, 72 (seed 4: 67) staged / 5, 4, 1 deployed;  dcfc20: 68, 67, 68 / 6, 7, 4
--     fifo    dcfc10: 66, 35, 37 / 6, 15, 22;                              dcfc20: 60, 54, 65 / 6, 13, 6
--     greedy  dcfc10: 74, 66, 70 / 3, 5, 3;                                dcfc20: 72, 72, 63 / 3, 1, 7
--   With 10 or 20 fast chargers alike, well over half the fleet ends the day waiting for service. Unmet demand hardly
--   moves when chargers double (92.7% to 91.0% for OTTO-Q, 88.3% to 84.8% for first come, first served). The fast
--   chargers were busy only 68-75% of the time (frontier dcfc_busy_pct) while those cars waited. So the queue is not
--   waiting on chargers alone. The likeliest constraint is the service bays (3 wash, 2 service) and the technicians,
--   under rule 9, which releases no car with a needed service open. That is a reading, not a measurement.
--   OTTO-Q ends the day with the most cars staged.
--   Not yet established: which services the staged cars are waiting on (a charger, a bay or a technician), and
--   whether it is a capacity finding (rule 9: more capacity, never fewer services) or an ordering one. 0573 makes
--   sensor calibration 60 minutes instead of 30, which would make a bay queue heavier. Handed to the engine review
--   (session_011hD7J36g7XruCNnuS6taWW), whose scope it is.
--
-- ══ §7 WHAT THIS MEANS FOR NIGHT 2 ═══════════════════════════════════════════════════════════════════════════════════
--
--   A 12-hour arm takes a mean 19.8 min, and tick cost grows through the day: the smoke arm's first 24 ticks ran about
--   2.9 s a tick, a whole 12-hour arm 8.3 s. A 24-hour arm is estimated at 50-80 min, so a 7-hour night fits about 6-8,
--   against value_2026_09_30's 24. 0575's cells are reordered so each seed runs its four headline cells first: OTTO-Q
--   against the plain depot at 10 and at 20 chargers, then the four split cells.
--
-- ══ QUERIES (read-only) ═══════════════════════════════════════════════════════════════════════════════════════════════

-- §1-§3
SELECT a.arm_id, c.cell_code, array_position(s.seeds, a.seed) AS k, a.replicate, a.complete, a.paid_shield, a.ticks,
       a.wall_s, a.arm_error, a.restore -> 'restored' AS restored, a.sim_run_id
  FROM public.ottoq_throughput_sweep_arms a
  JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
  JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
 WHERE s.sweep_code = 'frontier_2026_09_29' ORDER BY a.arm_id;
SELECT * FROM public.ottoq_throughput_frontier WHERE sweep_code = 'frontier_2026_09_29';
SELECT * FROM public.ottoq_throughput_sweep_pairs WHERE sweep_code = 'frontier_2026_09_29';
SELECT * FROM public.ottoq_margin_summary WHERE sweep_code = 'frontier_2026_09_29';

-- §5
SELECT arm_id, atoms - 'run' AS atoms_without_run, atoms ->> 'run' AS run
  FROM public.ottoq_throughput_sweep_arms WHERE arm_id IN (3, 9);
SELECT * FROM public.ottoq_throughput_sweep_replicates WHERE sweep_code = 'frontier_2026_09_29';

-- §6
SELECT a.arm_id, c.cell_code, a.atoms #> '{end,by_state}' AS end_states,
       a.arm_metrics -> 'unmet_demand_car_hours' AS unmet_h, a.arm_metrics -> 'demand_car_hours' AS demand_h
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
 WHERE a.arm_id BETWEEN 3 AND 22 ORDER BY a.arm_id;

-- §4: where the peak falls, by offset (the 30-minute window and samples of ottoq_dial_arm_metrics)
WITH arms AS (
  SELECT a.arm_id, a.sim_run_id FROM public.ottoq_throughput_sweep_arms a
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE s.sweep_code = 'frontier_2026_09_29' AND NOT a.replicate
), w AS (
  SELECT arms.arm_id, e.t - r.sim_clock_start AS dt,
         avg(e.g) OVER (PARTITION BY arms.arm_id ORDER BY e.t
                        RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30
    FROM arms JOIN public.ottoq_sim_runs r ON r.sim_run_id = arms.sim_run_id
    JOIN LATERAL (SELECT x.timestamp AS t, GREATEST(COALESCE(x.grid_import_kw, 0), 0) AS g
                    FROM public.site_energy_snapshots x
                   WHERE x.sim_run_id = arms.sim_run_id AND x.depot_id = '11111111-1111-1111-1111-111111111111') e ON true
), per AS (
  SELECT d.arm_id, m.k, (SELECT max(w2.g30) FROM w w2 WHERE w2.arm_id = d.arm_id AND w2.dt >= make_interval(mins => m.k)) AS pk
    FROM (SELECT DISTINCT arm_id FROM w) d CROSS JOIN unnest(ARRAY[60, 90, 120, 180, 240]) AS m(k)
), st AS (
  SELECT per.*, (SELECT round(EXTRACT(EPOCH FROM min(w3.dt)) / 60)::int FROM w w3
                  WHERE w3.arm_id = per.arm_id AND w3.dt >= make_interval(mins => per.k) AND w3.g30 = per.pk) AS start_min
    FROM per
)
SELECT k AS from_min, count(*) AS arms, count(*) FILTER (WHERE start_min <= k + 5) AS peak_at_boundary, round(avg(pk)) AS mean_peak
  FROM st GROUP BY k ORDER BY k;
