-- 0433  **Waymo's California filing for Apr-Jun 2026, read against the twin: a real robotaxi drives at least 49.7 miles
--        per charging session, the twin's physics world drives 47-52 and busy_day's stress world 18.2; the dispatch
--        ledger's miles read 2-68% of what the cars drove; and the twin's collision rate is about a 25th of the
--        filing's.**
--        Part A of the twin data contract review (2026-10-08), items 1 (CPUC duty cycles) and 2 (incident rates, first
--        read). The filing and its definitions: docs/research/direct/2026-10-10-cpuc-waymo-q2-2026-duty-cycle.md.
--        Measured 2026-10-10 05:20-05:50 UTC (12:20-12:50 AM CT), read-only, twin depot 11111111-…; the throughput sweep
--        was running, so nothing here touches a row, it only reads.
--
-- ══ §1 THE FILING ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Waymo LLC, CPUC driverless deployment program, 2026-04-01 to 2026-06-30, filed 2026-08-03
--   (https://www.cpuc.ca.gov/-/media/cpuc-website/divisions/consumer-protection-and-enforcement-division/documents/tlab/av-programs/waymo-deployment-2026q2.zip,
--   sha256 8897db06…b89c8, downloaded 2026-10-10). Every per-trip, per-charger and per-session column is redacted, and
--   the stoppage data sets are too; what is left are monthly totals and row counts:
--     4,220,075 trips, 28,143,285 miles, all electric; 6.67 miles per trip, 41.1% with no passenger (26.3% between
--     trips, 14.8% to the pickup); 16.6 minutes waiting per trip (the dictionary: drop-off to the next accepted trip,
--     in hours, so depot and charging time included);
--     566,282 charging sessions on 324 chargers (whole passenger fleet, pilot program included, per the filing's own
--     note): 19.2 sessions per charger per day, and 28,143,285 / 566,282 = 49.7 deployment miles per session as a
--     FLOOR (the miles exclude the pilot program's, the sessions do not).
--   No distribution can be fitted from that, so nothing goes into the calibration corpus (a corpus row forces a
--   recertification, and one mean per quarter is a target, not a draw).
--
-- ══ §2 THE TWIN AGAINST IT (G407) ═════════════════════════════════════════════════════════════════════════════
--
--   Twin-depot runs of the 7 days to 2026-10-10 whose events span 4-72 sim-hours (1). Miles are taken from the cars'
--   own telemetry speeds over each dispatch (avg speed_kmh x minutes out), not from the ledger (§3). Not independent
--   observations (pairs share seeds, G153): levels, not rates with ranges.
--
--                                   normal_day      busy_day pairs     busy_day, operator   Waymo CA Q2 2026
--                                   (no profile)    (no profile)       (profile)
--     runs / sim hours              4 / 24          24 / 264           32 / 565             -
--     minutes out per return        132             150                42                   -
--     miles per return              48.5            54.0               23.3                 -
--     miles per charging session    46.7            51.6               18.2                 >= 49.7
--     sessions per charger-day      10.6            6.7                12.0                 19.2
--     battery points per hour out   5.5             6.3                41.3                 -
--     Waymo I-Pace kWh/100 mi       25.6            27.9               109.5                EPA 44 (at the wall)
--
--   (a) The physics world (no variability profile) sits at the real fleet's floor on miles per session. busy_day's
--       profile is declared: soc_on_arrival {shift -30}, which since 0486 (G219) drains 30 battery points per hour
--       out as power, with trip duration x0.3 and idle fraction x1.9. So the operator's busy_day charges 2.7 times as
--       often per mile as Waymo's California fleet at least, by design. 32 of the 60 runs above are that world.
--   (b) Energy per mile: EPA rates the 2021 Jaguar I-Pace EV400 at 44 kWh/100 mi combined, measured at the wall
--       (https://www.fueleconomy.gov/feg/noframes/43889.shtml, read 2026-10-10). The twin's physics draws 25.6-27.9 from
--       the battery. Part of that gap is charging loss (EPA counts it, a battery-side figure does not) and part is the
--       0.3 kW always-on AV load in twin.ottoq_sim_compute_discharge_rate; neither part is measured here.
--   (c) Chargers: 19.2 sessions per charger-day in California against 6.7-12.0 in the twin, whose 45 chargers are 35
--       L2 units of 19.2 kW and 10 fast chargers of 350 kW. Waymo's charger types are redacted.
--
-- ══ §3 THE DISPATCH LEDGER'S MILES COUNT A PACKET AS A MINUTE (G406) ════════════════════════════════════════════
--
--   twin.ottoq_sim_advance_deployed_telemetry closes a dispatch with
--     miles_driven = (SELECT COALESCE(SUM(speed_kmh) / 60.0 * 0.621371, 0) FROM ottoq_telemetry_packets WHERE ...)
--   which treats every packet as one minute of driving. A deployed car emits one packet per tick (speed_kmh = its
--   average speed times its active fraction that tick), and its packets come 1.5 to 45 sim minutes apart depending on
--   the run's tick length.
--   Recorded over driven (2): 0.021 on normal_day (45 sim minutes per packet), 0.024 on the busy_day pairs (41),
--   0.679 on the operator's busy_day (1.5). The same function already computes the tick's true miles
--   (v_miles := v_avg_speed * v_active_frac * p_tick_minutes / 60 * 0.621371) for the incident roll, and accrues the
--   tick's energy on the dispatch; it never accrues the miles.
--   Readers (3): public.ottoq_twin_kpi_board ('miles' on the KPI tab), public.ottoq_twin_offsite_window (miles p50,
--   miles per trip-minute) and twin.ottoq_sim_build_arrival_payload (the arrival webhook's odometer_mi = the car's
--   lifetime miles + SUM(miles_driven)). No decision reads any of them, and no app or edge function reads the column.
--   So it is a reporting defect: the KPI tab understates the miles a run drove by 1.5x to 48x.
--
-- ══ §4 COLLISIONS: THE FILING'S RATE IS ABOUT 25 TIMES THE TWIN'S (G408) ════════════════════════════════════════
--
--   The incident file keeps its yes/no flags. Streamed across its seven parts (4,888,011 rows, of which 2,064 carry
--   any content): 291 rows flag a collision (63 of them at a pickup or drop-off), and all 291 carry an NHTSA Standing
--   General Order 2021-01 report id (redacted); 258 involve another motor vehicle; 26 carry an injury flag, 2 severe,
--   0 fatal. Per the dictionary, one row is one incident ("A single collision may be entered in more than 1 field if
--   multiple actors were involved"). Over 28,143,285 miles: 10.3 collisions per million miles, 0.92 with an injury
--   flag, 0.07 severe.
--   The twin: twin.ottoq_sim_maybe_incident fires any incident at 5e-7 per mile ("DMV-calibrated ... 1 per 2M miles"),
--   82% of them collisions, so 0.41 collisions per million miles, and busy_day's profile multiplies it by 0.4. Over
--   the 7 days the twin depot drove about 440,000 miles (4) and recorded 0 incidents, as its rate predicts (0.15
--   expected). At the filing's rate about 4.5 collisions would be expected.
--   What this cannot say: how many of the 291 sent the car to a depot, and for how long. That share sets the body and
--   inspection bay demand the review asked about, and it is not in the filing. Even at the filing's rate a twin run
--   (about 5,800 miles) meets a collision about once in 17 runs, so the leverage on any one run's KPIs is small.
--
-- ══ REPRODUCE ══
--
-- The filing's figures: python3 -I over the zip (docs/research/direct/2026-10-10-cpuc-waymo-q2-2026-duty-cycle.md).

-- (1) the twin's three worlds: miles, sessions, energy, battery points per hour
WITH r AS (
  SELECT r.sim_run_id, r.scenario_code || CASE WHEN vp.sim_run_id IS NULL THEN ' (no profile)' ELSE ' (profile)' END AS world
    FROM public.ottoq_sim_runs r LEFT JOIN public.ottoq_variability_profiles vp ON vp.sim_run_id = r.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.scenario_code IN ('normal_day','busy_day')
     AND r.started_at > now() - interval '7 days' AND r.status <> 'active'),
span AS (SELECT e.sim_run_id, extract(epoch FROM (max(e.sim_clock_at) - min(e.sim_clock_at))) / 3600.0 AS sim_h
           FROM public.ottoq_events e JOIN r USING (sim_run_id) WHERE e.sim_clock_at IS NOT NULL GROUP BY 1),
d AS (
  SELECT d.sim_run_id, d.dispatch_id, d.vehicle_id, d.dispatched_at, d.actual_return_at, d.actual_duration_min,
         d.miles_driven, d.energy_consumed_kwh, d.soc_at_dispatch_pct - d.soc_at_return_pct AS soc_used, v.make
    FROM public.ottoq_vehicle_dispatches d JOIN r USING (sim_run_id) JOIN public.vehicles v ON v.id = d.vehicle_id
   WHERE d.status = 'completed' AND d.actual_duration_min > 0),
p AS (
  SELECT d.dispatch_id, avg(t.speed_kmh) * d.actual_duration_min / 60.0 * 0.621371 AS miles, count(*) AS packets
    FROM d JOIN public.ottoq_telemetry_packets t
      ON t.sim_run_id = d.sim_run_id AND t.vehicle_id = d.vehicle_id
     AND t.sim_clock_at >= d.dispatched_at AND t.sim_clock_at <= d.actual_return_at AND t.speed_kmh IS NOT NULL
   GROUP BY d.dispatch_id, d.actual_duration_min),
agg AS (
  SELECT r.world, d.sim_run_id, count(*) AS returns, sum(p.miles) AS miles, sum(d.miles_driven) AS miles_rec,
         sum(d.soc_used) AS soc_used, sum(d.actual_duration_min) AS out_min, sum(p.packets) AS packets,
         sum(p.miles) FILTER (WHERE d.make IN ('Waymo','Jaguar')) AS ipace_miles,
         sum(d.energy_consumed_kwh) FILTER (WHERE d.make IN ('Waymo','Jaguar')) AS ipace_kwh
    FROM d JOIN p USING (dispatch_id) JOIN r USING (sim_run_id) GROUP BY 1, 2),
s AS (SELECT o.sim_run_id, count(*) AS sessions FROM public.ocpp_sessions o JOIN r USING (sim_run_id) GROUP BY 1)
SELECT a.world, count(*) AS runs, round(sum(span.sim_h)::numeric, 0) AS sim_h,
       round((sum(a.out_min) / sum(a.returns))::numeric, 1) AS min_out_per_return,
       round((sum(a.miles) / sum(a.returns))::numeric, 1) AS miles_per_return,
       round((sum(a.miles) / NULLIF(sum(s.sessions), 0))::numeric, 1) AS miles_per_session,
       round((sum(s.sessions) / NULLIF(sum(45 * span.sim_h / 24.0), 0))::numeric, 1) AS sessions_per_charger_day,
       round((sum(a.soc_used) / sum(a.out_min) * 60)::numeric, 1) AS soc_pts_per_h_out,
       round((100 * sum(a.ipace_kwh) / NULLIF(sum(a.ipace_miles), 0))::numeric, 1) AS ipace_kwh_per_100mi
  FROM agg a JOIN span USING (sim_run_id) LEFT JOIN s USING (sim_run_id)
 WHERE span.sim_h BETWEEN 4 AND 72
 GROUP BY 1 ORDER BY 1;

-- (2) the ledger's miles against the miles the telemetry speeds give, and sim minutes per packet (same CTEs as (1))
--     SELECT world, sum(miles_rec) / sum(miles) AS recorded_over_driven, sum(out_min) / sum(packets) AS sim_min_per_packet
--       FROM agg GROUP BY 1;

-- (3) every reader of the column
SELECT n.nspname || '.' || p.proname AS fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.prosrc ~ 'miles_driven' AND n.nspname IN ('public','twin','ottoq') ORDER BY 1;

-- (4) the twin's incidents and miles over the same window
WITH r AS (
  SELECT r.sim_run_id FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.started_at > now() - interval '7 days' AND r.status <> 'active'),
d AS (
  SELECT d.sim_run_id, d.dispatch_id, d.vehicle_id, d.dispatched_at, d.actual_return_at
    FROM public.ottoq_vehicle_dispatches d JOIN r USING (sim_run_id)
   WHERE d.status IN ('completed','aborted') AND d.actual_return_at IS NOT NULL),
p AS (
  SELECT d.dispatch_id, avg(t.speed_kmh) * extract(epoch FROM (d.actual_return_at - d.dispatched_at)) / 3600.0 * 0.621371 AS miles
    FROM d JOIN public.ottoq_telemetry_packets t
      ON t.sim_run_id = d.sim_run_id AND t.vehicle_id = d.vehicle_id
     AND t.sim_clock_at >= d.dispatched_at AND t.sim_clock_at <= d.actual_return_at AND t.speed_kmh IS NOT NULL
   GROUP BY d.dispatch_id, d.actual_return_at, d.dispatched_at)
SELECT round(sum(p.miles)) AS miles,
       (SELECT count(*) FROM public.ottoq_vehicle_incidents i JOIN r USING (sim_run_id)) AS incidents
  FROM p;
