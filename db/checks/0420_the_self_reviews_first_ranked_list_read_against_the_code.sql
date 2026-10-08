-- 0420  **The self-review's first ranked list, read against the code behind it (0626, G360-G364).** 0626's first
--        review (assessment 3, 2026-10-08 22:50:37 UTC) ranks eleven areas, eight open, and its top three hold up
--        against the source. The air temperature it names has a mechanism in both kinds of charger: the twin derates a
--        charge 2% for each degree its battery runs past 35 °C, the battery warms 5 °C for each 10 minutes it charges,
--        and the clock's base estimate has no temperature at all. The effect grows with the warmth (0.7-1.1% a degree
--        below 20 °C, 1.5% with the two warm runs), as a derate past a threshold does. The fast-charge band is narrow
--        because the clock gives every fast charge one spread: charges of 15-30 minutes hold it, charges over 30
--        minutes (where a battery passes 35 °C) run wider, and a few top-offs run far off. On L2 the band holds. The
--        arrivals the futures miss are in the tails: cars the kernel recalls because their telemetry went stale, which
--        the futures never do, and reserve returns on short trips, about 6 minutes late. One review and one fit: single
--        readings, not ranges.
--
--       Written 2026-10-08, 6:20 PM CT. Read-only. Twin depot 11111111-…; the review's 7 days (2026-10-01 22:50:37 to
--       10-08 22:50:37 UTC: 12 runs, 458 fast and 613 L2 charges on fine ticks) against fit 3, the depot's clock since
--       0625 (21:49:32 UTC). The window is inside fit 3's own evidence, as the audit says (out_of_sample false).
--
-- ══ §1 THE REVIEW (reproduce: (1)) ══
--
--   rank  status    impact tier  area                                 title
--      1  open        22%    2   arrival_spread                       A few cars come home far from their forecast
--      2  open        15%    2   charge_clock_misses_air_temperature  The charge clock does not see the air
--                                                                     temperature
--      3  open        15%    2   charge_clock_band_dcfc               The charge clock is surer than the charges
--                                                                     on fast chargers
--      4  open        15%    4   forecast_faults                      Charger faults it never sampled moved its
--                                                                     verdicts
--      5  open         -     5   simulator_structure                  Its simulator places a plug-in 11 minutes
--                                                                     off, even given what happened
--      6  open         -     5   chargers_left_out                    It never adds back a charger whose hold ends
--      7  open, thin   -     5   bar_stricter                         Taking none of these orders would have done
--                                                                     better
--      8  open, thin   -     5   futures_uninformative                Its odds of winning predict no better than
--                                                                     the base rate
--      9  built       24%    4   forecast_appeared                    Cars it never saw coming moved its verdicts
--     10  built       24%    2   forecast_running                     Charges under way ended sooner than it
--                                                                     expected
--     11  built       15%    3   charge_clock_l2                      Some makes' charges on L2 chargers ran off
--                                                                     its forecast
--
--   Impact is the share of what made the check's verdicts wrong that the area's part carries (0621's split over the 15
--   orders of 61 graded that it attributes; the parts changed 7 of their verdicts). Built means the part was rebuilt
--   after these orders were made: they were timed by charge_time_v1 and the depot's clock is now charge_time_v2 (fit
--   3), and the check now sends cars out and brings them back (0623/0624), so those three are history until new orders
--   are graded. Thin means it rests on too little to act on (2 orders taken, 18 decisions). No title, finding or action
--   names a table, a function or a migration.
--
--   0622's review in the same place put air temperature first, at 26-28% of the clock's residuals, with class and make
--   levels on fast chargers (G360). v3 names air temperature on its slopes within and between runs, and names neither
--   class nor make: fit 3 cut the stale levels (G359). Its scan of the clock's world finds nothing to name since 0573.
--
-- ══ §2 RANK 2: AIR TEMPERATURE (G361; reproduce: (2)) ══
--
--   The slopes, as the audit reports them (a share of the charge's minutes per degree of air at its start):
--                    within runs                           between runs (charge-weighted, runs of 5+ charges)
--     fast chargers  +0.97% a degree, t 4.89, sd 2.21 °C   +1.54% a degree, R² 0.781, 10 runs, 14.4-27.3 °C (p10-p90)
--     L2             +0.81% a degree, t 2.83, sd 1.41 °C   +1.50% a degree, R² 0.902, 11 runs, 12.8-25.5 °C
--   Within runs the air temperature explains 6.2% of the fast-charge residuals' variance and 2.9% of L2's; beyond the
--   levels the clock has, 5.2% and 1.5%.
--
--   The mechanism is in the source, in both branches. ottoq_sim_compute_charge_rate multiplies the rate by a thermal
--   factor on the BATTERY's temperature after the DC and L2 branches part: 1 from 15 to 35 °C, 2% less for each degree
--   past 35 (floor 0.30), 0.65 from 0 to 10 °C, blended from 10 to 15. twin.ottoq_sim_advance_charge_sessions sets the
--   battery's temperature each tick to the charge's air temperature + 5 + a draw up to 8 (per car, run and start) + 5
--   for each 10 minutes charged, at most 15. Half an hour in, a battery on a 20 °C day runs 40-48 °C and charges at
--   0.74-0.90 of its rate; on a 25 °C day 45-53 °C and 0.64-0.80. The clock's base estimate, 0614's
--   ottoq_charge_minutes_estimate, takes no temperature, so the whole effect lands in the clock's residual, and the
--   clock has no level to put it in. The other run-wide multipliers do not confound it: every run here has the same
--   scenario and a variability multiplier of 1 on charge_time (ottoq_profile_rate_mult), and the ledger's two
--   temperatures agree (ambient_temp_c, which the physics reads, and depot_air_c, the site's air at the start: 1,065
--   of 1,071 equal).
--
--   The effect grows with the warmth. Between runs, below 20 °C: +0.69% a degree on fast chargers (8 runs, 12.4-19.8
--   °C) and +1.11% on L2 (8 runs, 12.4-18.2 °C); with the two warm runs (512404f7 at 24.0 °C, cde5a21c at 26.3 °C)
--   +1.54% and +1.50%. cde5a21c's charges ran +0.161 (fast) and +0.157 (L2) past the clock against -0.02 to -0.03 for
--   the runs at 16-17 °C: about 2% a degree, what the derate predicts once a battery is past 35 °C. By band (fit 3):
--
--              fast chargers                    L2
--     °C       n   residual  within run        n   residual  within run
--     10-12   30    -0.042    +0.031          54    -0.045    +0.017
--     12-14   12    -0.007    -0.007          44    -0.042    -0.018
--     14-16   85    -0.054    -0.018         161    -0.022    -0.001
--     16-18  133    -0.050    -0.014         188    -0.006    -0.006
--     18-20   32    -0.029    -0.008          40    +0.025    +0.021
--     20-22   66    +0.007    +0.027          22    +0.025    +0.014
--     22-24   27    +0.020    +0.040           -        -         -
--     24-26   42    +0.067    -0.037          91    +0.113    -0.017
--     26-28    6    +0.137    -0.024           2    +0.244    +0.087
--     28-30   10    +0.150    -0.011           7    +0.316    +0.159
--     30-32   15    +0.283    +0.121           4    +0.212    +0.055
--
--   A straight line through 11-31 °C reads the middle and misses both ends. A level per band of air temperature,
--   pooled toward its neighbours, or a hinge fitted within runs, would carry the shape. The warm end rests on two runs.
--   Not established: why the runs at 12-20 °C move less than the source's derate predicts there (a battery at 35-43 °C
--   from 15 °C air should run 2% a degree slower; they run 0.7-1.1%).
--
-- ══ §3 RANK 3: THE FAST-CHARGE BAND (G362; reproduce: (3) and (4)) ══
--
--   The clock's spread for a charge (ottoq_charge_clock's sd) is one number per class and kind: the class's robust
--   spread (1.4826 x the weighted median of the absolute residual its levels leave, ottoq_charge_time_v2_params_cut),
--   narrowed by the share of the variance the car's own level explains (sqrt(1 - icc x s): fit 3's icc 0.698 on fast
--   chargers and 0.302 on L2, s the car's weight, mean 0.869 and 0.763). The futures draw a charge's minutes on it.
--   Against the charges:
--                                       fast chargers          L2
--     the clock's sd, mean (range)      0.065 (0.058-0.078)    0.114 (0.110-0.122)
--     residual sd across runs           0.118                  0.117
--     residual sd within runs           0.096                  0.099
--       its robust spread               0.072                  0.098
--     within runs, less air temperature 0.093                  0.098
--     inside the 80% band               64.2%                  82.7%
--       within runs                     69.7%                  87.6%
--       within runs, less air           70.7%                  87.9%
--
--   The narrowing is about right: the car's level takes 69.6% of the fast-charge variance within runs (0.173 to 0.096),
--   and the robust spread of what is left (0.072) is close to what the formula gives on a robust start (0.067). What
--   is wrong is one spread for every length of charge. Fast charges within runs, with the car's level, by length:
--     minutes   charges  soc gained  residual sd  robust  80th pct |res|  clock sd  inside 80% band
--     < 15          99        8.2        0.115     0.062        0.149      0.066        69.7%
--     15-30         78       12.7        0.071     0.056        0.083      0.065        79.5%
--     30-60        144       43.2        0.090     0.085        0.118      0.065        66.0%
--     60+          137       54.8        0.092     0.074        0.118      0.064        67.9%
--   Charges of 15-30 minutes are as the clock says. Top-offs under 15 minutes are mostly as tight as it says and a few
--   are far off (sd 0.115 against a robust 0.062); not established what puts them there (ticks are a mean 0.22 minutes,
--   too fine to explain it). Charges over 30 minutes are wider throughout (robust 0.074-0.085). Those are the charges
--   whose battery passes 35 °C (it warms 5 °C for each 10 minutes), and the twin draws each battery's starting offset
--   up to 8 °C, which no forecast from the air can see: a spread that grows with the charge's length, and with the air
--   temperature, is what the physics gives. On L2 the residuals are near normal (robust 0.098 against sd 0.099) and the
--   clock's spread is wider than they are, so the band holds.
--
--   Air temperature as a level does not close the band: taking its slope out within runs moves it by one point.
--
-- ══ §4 RANK 1: ARRIVALS (G363; the review's arrival_tails, and by return trigger: reproduce (5)) ══
--
--   Of the 2,510 cars the futures expected home, 79.9% came inside the band they sample, against 80%. The bulk (2,337)
--   is as wide as the futures sample it (z sd 0.924, mean +0.187). The misses are in the tails (|z| > 3):
--     early   69 (2.7%)    a mean 15.4 minutes early   38.3 minutes from the reserve when they came
--     late   104 (4.1%)    a mean 7.7 minutes late     15.8 minutes from the reserve, against 38.8 for the bulk
--   The futures call a car home only when its battery reaches the learned reserve (0620's ottoq_charge_line_inbound),
--   and spread its return in proportion to the time to the reserve.
--
--   Each car's return carries the trigger the kernel's recall decision gave it
--   (ottoq_vehicle_dispatches.return_trigger, on the dispatch the car was on at the order). By tail:
--     bulk    low_soc_reserve 2,319 (+0.8 minutes)   comms_stale 18
--     early   comms_stale 54 (-16.9 minutes, 44.8 from the reserve)   low_soc_reserve 12 (-0.7, 2.0 from it)
--             rider_flag_cleaning 3 (-45.9)
--     late    low_soc_reserve 87 (+6.0 minutes, 12.5 from the reserve)   comms_stale 17 (+16.5)
--   So the early tail is cars the kernel recalls because their telemetry went stale (54 of 69) or a rider flagged them
--   (3): ottoq_recall_naive_threshold_v1 recalls a car whose last packet is older than its comms-stale limit, at
--   once, and nothing in the futures does. The late tail is reserve returns on short trips (87 of 104): about 6
--   minutes of delay that a spread in proportion to a 12-minute wait cannot hold. Both are things the depot can see:
--   each car's packet age at the order, and the delay its own returns show.
--
-- ══ §5 REPRODUCE ══
--
--   Each runs inside the SQL editor's 58 s on live.

SET statement_timeout = '58s';

-- (1) the ranked list, as the review wrote it
SELECT (x ->> 'rank')::int AS rank, x ->> 'status' AS status, x ->> 'thin' AS thin, x ->> 'impact' AS impact,
       x ->> 'tier' AS tier, x ->> 'area' AS area, x ->> 'title' AS title, x ->> 'action' AS action
  FROM public.ottoq_arbiter_assessments a, jsonb_array_elements(a.improvement_areas) x
 WHERE a.assessment_id = 3 ORDER BY 1;

-- (2) air temperature: the clock's residual (fit 3) by two-degree band, across and within runs; the run-level slopes
--     are in the review's own clock_audit block: assessment -> 'clock_audit' -> 'by_kind' -> kind -> 'air_temperature'
WITH m AS (SELECT jsonb_build_object('params', f.params) AS j2 FROM public.ottoq_charge_clock_fits f WHERE f.fit_id = 3),
e AS (
  SELECT l.sim_run_id AS run, l.charger_type AS kind, l.ambient_temp_c AS air,
         ln((l.duration_min / est.m)::numeric) - (public.ottoq_charge_clock(m.j2, l.charger_type, w.j, l.battery_kwh,
                                                     l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw, NULL) ->> 'f')::numeric AS res
    FROM m, public.ottoq_charge_duration_ledger l
    JOIN public.vehicles v ON v.id = l.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                    l.vehicle_kw) AS m) est
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.recorded_at >= '2026-10-01 22:50:37+00'
     AND l.recorded_at <= '2026-10-08 22:50:37+00' AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2')
     AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0 AND l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1),
r AS (SELECT e.*, e.res - avg(e.res) OVER (PARTITION BY e.kind, e.run) AS rw FROM e)
SELECT r.kind, (2 * floor(r.air / 2))::int AS air_from, count(*) AS n, count(DISTINCT r.run) AS runs,
       round(avg(r.res), 3) AS mean_res, round(avg(r.rw), 3) AS mean_res_within_run
  FROM r GROUP BY 1, 2 ORDER BY 1, 2;

-- (3) the band: the clock's sd against the residuals' spread, across and within runs, with and without the car's level
WITH m AS (SELECT f.params, jsonb_build_object('params', f.params) AS j2 FROM public.ottoq_charge_clock_fits f WHERE f.fit_id = 3),
e AS (
  SELECT l.sim_run_id AS run, l.charger_type AS kind,
         (ln((l.duration_min / est.m)::numeric) - (c.c ->> 'f')::numeric)::float8 AS res,
         COALESCE((m.params #>> ARRAY['vehicle_cells', l.charger_type || '|' || (w.j ->> 'veh'), 'off'])::float8, 0) AS voff,
         (c.c ->> 'sd')::float8 AS sd
    FROM m, public.ottoq_charge_duration_ledger l
    JOIN public.vehicles v ON v.id = l.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                    l.vehicle_kw) AS m) est
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(m.j2, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end,
                                                         l.charger_kw, l.vehicle_kw, NULL) AS c) c
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.recorded_at >= '2026-10-01 22:50:37+00'
     AND l.recorded_at <= '2026-10-08 22:50:37+00' AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2')
     AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0 AND l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1),
r AS (SELECT e.*, e.res - avg(e.res) OVER (PARTITION BY e.kind, e.run) AS rw,
             (e.res + e.voff) - avg(e.res + e.voff) OVER (PARTITION BY e.kind, e.run) AS rw_nocar FROM e)
SELECT r.kind, count(*) AS n, round(avg(r.sd)::numeric, 4) AS clock_sd,
       round(stddev_samp(r.res)::numeric, 4) AS sd_res, round(stddev_samp(r.rw)::numeric, 4) AS sd_within,
       round((1.4826 * percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(r.rw)))::numeric, 4) AS robust_within,
       round(stddev_samp(r.rw_nocar)::numeric, 4) AS sd_within_without_car,
       round((1 - var_samp(r.rw) / NULLIF(var_samp(r.rw_nocar), 0))::numeric, 3) AS share_car_explains_within,
       round(avg((abs(r.res) <= 1.2816 * r.sd)::int)::numeric, 3) AS in80,
       round(avg((abs(r.rw) <= 1.2816 * r.sd)::int)::numeric, 3) AS in80_within
  FROM r GROUP BY r.kind ORDER BY 1;

-- (4) the fast-charge band by the charge's length, within runs, with the car's level
WITH m AS (SELECT jsonb_build_object('params', f.params) AS j2 FROM public.ottoq_charge_clock_fits f WHERE f.fit_id = 3),
e AS (
  SELECT l.sim_run_id AS run, l.duration_min::float8 AS dur, l.soc_start, l.soc_end,
         (ln((l.duration_min / est.m)::numeric) - (c.c ->> 'f')::numeric)::float8 AS res, (c.c ->> 'sd')::float8 AS sd
    FROM m, public.ottoq_charge_duration_ledger l
    JOIN public.vehicles v ON v.id = l.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                    l.vehicle_kw) AS m) est
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(m.j2, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end,
                                                         l.charger_kw, l.vehicle_kw, NULL) AS c) c
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.recorded_at >= '2026-10-01 22:50:37+00'
     AND l.recorded_at <= '2026-10-08 22:50:37+00' AND l.stopped_reason = 'completed' AND l.charger_type = 'dcfc'
     AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0 AND l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1),
r AS (SELECT e.*, e.res - avg(e.res) OVER (PARTITION BY e.run) AS rw FROM e)
SELECT CASE WHEN r.dur < 15 THEN 'a <15' WHEN r.dur < 30 THEN 'b 15-30' WHEN r.dur < 60 THEN 'c 30-60' ELSE 'd 60+' END AS minutes,
       count(*) AS n, round(avg(r.soc_end - r.soc_start)::numeric, 1) AS mean_soc_gain,
       round(stddev_samp(r.rw)::numeric, 4) AS sd_within,
       round((1.4826 * percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(r.rw)))::numeric, 4) AS robust_within,
       round(percentile_cont(0.8) WITHIN GROUP (ORDER BY abs(r.rw))::numeric, 4) AS q80_abs_within,
       round(avg(r.sd)::numeric, 4) AS clock_sd, round(avg((abs(r.rw) <= 1.2816 * r.sd)::int)::numeric, 3) AS in80_within
  FROM r GROUP BY 1 ORDER BY 1;

-- (5) the arrival tails by the trigger of each car's return (the dispatch it was on at the order)
WITH h AS (
  SELECT h.order_id, h.realized, s.state, s.sim_run_id, s.sim_clock
    FROM public.ottoq_charge_order_hindsight h JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
   WHERE h.depot_id = '11111111-1111-1111-1111-111111111111' AND h.graded_at >= '2026-10-01 22:50:37+00'
     AND h.graded_at <= '2026-10-08 22:50:37+00'
), ar AS (
  SELECT h.sim_run_id, h.sim_clock, (ib.value ->> 'id')::uuid AS vid, ib.value ->> 'src' AS src, (ib.value ->> 'eta')::numeric AS fc,
         COALESCE((ib.value ->> 'trip')::numeric, 0) AS trip, COALESCE((ib.value ->> 'esd')::numeric, 0) AS esd,
         COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false) AS arrived,
         (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::numeric AS act
    FROM h CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h.state -> 'inbound', '[]'::jsonb)) ib
), z AS (
  SELECT ar.*, ar.act - ar.fc AS err, ar.fc - ar.trip AS hz, ln((ar.act - ar.trip) / (ar.fc - ar.trip)) / ar.esd AS z
    FROM ar WHERE ar.arrived AND ar.src = 'forecast' AND ar.esd > 0 AND ar.act > ar.trip AND ar.fc > ar.trip
), t AS (
  SELECT z.*, (SELECT d.return_trigger FROM public.ottoq_vehicle_dispatches d
                WHERE d.sim_run_id = z.sim_run_id AND d.vehicle_id = z.vid AND d.dispatched_at <= z.sim_clock
                ORDER BY d.dispatched_at DESC LIMIT 1) AS trig,
         CASE WHEN z.z < -3 THEN 'early' WHEN z.z > 3 THEN 'late' ELSE 'bulk' END AS tail
    FROM z
)
SELECT t.tail, COALESCE(t.trig, '(none)') AS return_trigger, count(*) AS n, round(avg(t.err), 1) AS mean_err_min,
       round(avg(t.hz), 1) AS mean_min_to_reserve
  FROM t GROUP BY 1, 2 ORDER BY 1, 3 DESC;
