-- 0482  **The one-line on its first production run: every tick measured, a tripped transformer's four cars all re-seated,
--        and a right-size reading that passed on temperature alone.** (0810, 0811 applied; G538, 0812 pending)
--        Production, 2026-11-11, 15:16-15:32 UTC (9:16-9:32 AM CT). Rule 8: the twin depot. Rule 12: one demo run to
--        show a finished change working; no pair, no sweep.
--
-- ══ (1) WHAT WAS APPLIED, AND HOW ════════════════════════════════════════════════════════════════════════════════════
--
--   On Chase's instruction of 9:15 AM CT ("Apply 0810 and 0811 to the otto-q-core production database, deploy
--   otto-twin-control, and start demo runs at the twin depot as needed"):
--     0810  ledger 20261111151626   stored statement md5 1986d5e6, equal to the file as committed
--     0811  ledger 20261111151643   stored statement md5 aa745902, equal to the file as committed
--     otto-twin-control v31, version string 1.11.0-power-zone (15:17 UTC), from edge-functions/ in this repo
--   Every precondition was read on live first (no run live, no pair in flight, 30 posts, no power table). After 0810:
--   42 nodes, service voltage 13,800, both triggers present. After 0811: 30 chargers in service. The engine hash moved
--   from e4521543 to 0de67b72 (0810's functions are hashed).
--   FOUND WHILE DEPLOYING: ottoyarddepot-sim's copy of otto-twin-control was two versions behind this repo's (1.9.1
--   against the deployed 1.10.0: no ottoq_operator_start_run, no charge_wait). Deploying it would have undone 0564 and
--   0501 in production. This repo's copy is the one deployed; the other repo's copy is now the same file.
--
-- ══ (2) THE RUN: 54c0d20f (busy_day, operator_demo, live playback at 8x, 169 ticks, sim 8:00-9:45 AM CT) ═════════════
--
--   Started through ottoq_operator_start_run, as the cockpit's start does. Stopped by hand at 15:31 UTC.
--     - 169 snapshots, 169 measured: the posts' sum equals total_ev_charging_kw on 169 of 169 ticks.
--     - the cockpit's read, ottoq_power_one_line, answered through the public key with 42 nodes and live readings;
--       ottoq_twin_trip_power_node answered 401 to the same key.
--     - at the run's stop the study got its engine hash, the right-size reading and the resilience reading.
SELECT count(*) AS snapshots,
       count(*) FILTER (WHERE abs(s.total_ev_charging_kw - t.kw_dc) > 0.2) AS mismatched
  FROM public.site_energy_snapshots s
  JOIN public.ottoq_power_node_ticks t ON t.sim_run_id = s.sim_run_id AND t.node_code = 'SERVICE' AND t.sim_clock_at = s."timestamp"
 WHERE s.sim_run_id = '54c0d20f-f38e-4e9f-a6e0-f72f21aa9ffa';
--
-- ══ (3) THE TRIP: TX-B1 AT SIM 8:17 AM CT FOR 60 MINUTES, FOUR CARS CHARGING ═════════════════════════════════════════
--
--   Five posts faulted together; four sessions ended as faults. 29 of the 30 posts were busy at the time, so the cars
--   queued behind a full line of 25 posts (rule 9 allows queueing, never releasing):
--     car at 35%  on a post under TX-A2 two minutes later; 98% and still charging when the run was stopped
--     car at 98%  on TX-C1 after 17 minutes; ended at 100%
--     car at 90%  on TX-C2 after 21 minutes; ended at 100%
--     car at 88%  parked in the depot (staged_awaiting_service) for 55 minutes; on TX-A1 at 9:12; ended at 100% at 9:32
--   No interrupted car left below its target. TX-B1's five posts read Available again after 9:17, on time.
SELECT left(o.vehicle_id::text, 8) AS car, n.parent_code AS transformer, o.started_at, o.ended_at, o.soc_start, o.soc_end, o.stopped_reason
  FROM public.ocpp_sessions o JOIN public.stalls s ON s.id = o.stall_id
  JOIN public.ottoq_power_nodes n ON n.charger_id = s.ocpp_charger_id
 WHERE o.sim_run_id = '54c0d20f-f38e-4e9f-a6e0-f72f21aa9ffa'
   AND o.vehicle_id IN (SELECT vehicle_id FROM public.ocpp_sessions
                         WHERE sim_run_id = '54c0d20f-f38e-4e9f-a6e0-f72f21aa9ffa' AND stopped_reason = 'fault.operator_injected')
 ORDER BY o.vehicle_id, o.started_at;
--
-- ══ (4) WHAT THE RUN DREW (one run, 1.76 sim-hours of a busy morning: a reading, not a range) ════════════════════════
--
--   SERVICE: peak 1,256 kVA, busiest half hour 1,124 kVA (6.4% of the 17,500 kVA installed). The cars took 1,912 kWh.
--   Net of the battery and solar the grid side read 1,640 kWh against the site meter's 1,449 kWh (13% more; the
--   transformers' own loss was 50.9 kWh of it). The hottest winding was 24.0 C, in 5 to 7 C air.
--   The most any post delivered was 179.9 kW; 3 of 108 charges passed 150 kW; the lowest battery at plug-in was 22%.
--   (The lab's day read 122.5 kW and 39%: a live busy_day starts with cars lower than a certification arm's.)
--   All thirty posts were full at 8:07 AM, so at that moment no transformer's five cars had a free post elsewhere.
SELECT st.node_code, st.rated_kva, round(st.peak_kva) AS peak_kva, st.peak_30min_kva, round(st.energy_kwh_dc) AS kwh_dc,
       round(st.loss_kwh, 1) AS kwh_lost, st.max_hot_spot_c, st.rightsize->>'smallest_kva_this_day_fits' AS fits_on, st.resilience - 'is' AS resilience
  FROM public.ottoq_power_node_study st
 WHERE st.sim_run_id = '54c0d20f-f38e-4e9f-a6e0-f72f21aa9ffa' AND st.kind IN ('transformer', 'utility_service') ORDER BY 1;
--
-- ══ (5) G538: THE RIGHT-SIZE READING PASSED ON TEMPERATURE ALONE ═════════════════════════════════════════════════════
--
--   The stored reading for this run says every transformer's day "fits on 300 kVA", TX-AUX included, which peaked at
--   1,230 kVA and carried 434 kVA through its busiest half hour. The test was thermal only, and oil takes about three
--   hours to warm: on a 1.76-hour run, or under a short surge, a size no one would install stays cool. The charger
--   units' own half hours were 217 to 374 kVA, so 300 is wrong for four of those six as well.
--   0812 adds the missing condition (a size at or above the busiest full half hour) and names the figure it used.
--   Lab, same function body as production (md5 1136d5f4): the 2-minute day's readings do not change (TX-AUX 1,000, the
--   six charger units 300), and with this run's TX-AUX figures it reads 500. 0812 is PENDING: the instruction named
--   0810 and 0811, and the session's gate refused a third apply. Until it is applied and the reader is run again on
--   this run, do not quote this run's "fits on" figures.
