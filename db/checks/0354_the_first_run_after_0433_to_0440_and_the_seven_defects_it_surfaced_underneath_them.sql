-- 0354  **The first busy_day run after 0433–0440, measured end to end.**
--
--       The fixes it validates:
--       - 0431/0437 readiness: 0 of 224 departures skipped the check.
--       - 0432/v20 agent: 288 of 288 passes grounded, 0 rejections, 0 writes to a dead dial.
--       - 0433 (A)/(C) DR cap and ignition: one call; its cap is baseline − reduction.
--       - 0435 day plan: on-peak discharge 1,153 kWh against 35.
--       - 0436: the temperature peak moved to 14:00 CT.
--       - CP-SAT: 9 enactments against 0.
--
--       Beneath them it surfaced the defects 0442–0450 now fix:
--       - G177 the boot surge set the billed peak.
--       - G178 the battery answered a tick late.
--       - G179 zero-energy DCFC loops.
--       - G180 an afternoon 4.7 °C past the record.
--       - G181 a maintenance recall loop that left the depot meeting 2–25% of demand.
--       - G182 stale hold stamps.
--       - G183 a battery that could not cool, so it sat out the DR call.
--
--       And it surfaced three that are not fixed tonight:
--       - G184 no running session is ever curtailed, by doctrine.
--       - G185 the twin's day turns over at 00:00 UTC, 7 PM CDT.
--       - G186 the EV pack has no thermal management, and the charge model's heat derate is uncalibrated.
--
--       Run `324eb0f1-957a-455f-9023-3fb7feeab9a0`: busy_day, twin depot `11111111-…`, the same seed as `7a42982a`,
--       agent v20, governor 900 sim-minutes. Started 02:18 UTC 2026-09-23 (9:18 PM CT on 09-22) and ended 04:12 UTC
--       (11:12 PM CT) at sim 19:18 CT after 1,887 ticks (0.48 sim-min per tick). Measured 03:40–04:20 UTC, during and
--       after the run, before any teardown.
--
--       The run's code, for the record:
--       - It started on 0431–0440.
--       - A concurrent session applied its own 0441 at 02:33 UTC, mid-run: a class='evidence' ledger for HW.006
--         failures, forces_recert FALSE, no change to enforcement or dispatch.
--       - 0442–0450 were applied 04:20–04:27 UTC, after the run ended.
--
--       What each section answers:
--         §1  readiness (0431/0437)        §2  fast-tracks (0434)          §3  temperature (0436, G180, G185)
--         §4  battery by price (0435)      §5  the DR call (0433, G183, G184)
--         §6  CP-SAT (G167/G173)           §7  the agent (v20)             §8  realised site cost and KPIs
--         §9  G177 boot peak               §10 G178 one-tick lag           §11 G179 zero-energy DCFC
--         §12 sessions by SoC band (G186)  §13 G181 the maintenance loop   §14 G182 stale hold stamps
--         §15 the twin, 2D and 3D

\echo '=== 0354 §1 — departures with the readiness check pending (0431 + 0437) ==='
SELECT (SELECT count(*) FROM public.ottoq_vehicle_dispatches WHERE sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0') AS dispatches,
       (SELECT count(*) FROM public.ottoq_assert_departure_readiness('324eb0f1-957a-455f-9023-3fb7feeab9a0')) AS violations;
-- 224 dispatches, 0 violations.
-- 7a42982a (0431 only): 2 of 168, both via the staged_awaiting_service door 0437 closed. Before 0431: 24.5–25.8%.

\echo '=== 0354 §2 — deploy-pressure fast-tracks (0434) ==='
SELECT count(*) AS events, sum((payload->>'fasttracked')::int) AS vehicles
  FROM public.ottoq_events WHERE sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND event_type = 'twin.deploy_pressure_fasttrack';
-- 379 events moving 505 vehicles (7a42982a: 349 / 690). Fewer vehicles per event (1.33 against 1.98), because one
-- resolver now sets the demand. The pressure itself is G181's: the depot kept falling short of demand (§13).

\echo '=== 0354 §3 — ambient temperature by hour (0436, G180) ==='
SELECT to_char(date_trunc('hour', w.sim_clock_at AT TIME ZONE 'America/Chicago'), 'HH24') AS hr_ct,
       round(avg(w.ambient_temp_c), 1) AS t_c
  FROM public.ottoq_weather_snapshots w WHERE w.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' GROUP BY 1 ORDER BY 1;
-- 04 29.0 · 06 32.2 · 08 36.5 · 10 40.9 · 12 44.1 · 13 45.0 · 14 45.3 · 15 45.0 · 16 44.1 · 18 40.9 · 19 30.3
-- 0436 holds: the peak is at 14:00 CT (7a42982a peaked at 20:00).
-- G180: the level is 4.7 °C past September's record of 40.6. The day card is 31.1 °C against 22.8 ± 3.3 (+2.5 sigma,
-- legitimate), and busy_day's spread of 1.4 was applied around the all-year mean of 17.53, which adds 0.4 × (T − 17.53).
-- 0449 centres the widening on the hour's normal and clamps to the record. On this run's own card, 0449's V2 gives
-- 14:00 = 40.6, 12:00 = 39.8 and 10:00 = 37.5.
-- G185: the 19:00 row is not weather. The day cards are keyed `p_sim_clock_now::date − 2020-01-01` in a UTC
-- session, so the twin's day turns over at 00:00 UTC, which is 19:00 CDT:
SELECT to_char(w.sim_clock_at AT TIME ZONE 'America/Chicago', 'HH24:MI:SS') AS sim_ct, w.ambient_temp_c
  FROM public.ottoq_weather_snapshots w WHERE w.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0'
   AND w.sim_clock_at BETWEEN '2026-09-22 23:59:00+00' AND '2026-09-23 00:01:00+00' ORDER BY w.sim_clock_at;
-- 18:59:19 40.9 · 18:59:38 40.9 · 19:00:06 30.3. A new card, day:2457, was dealt: 25.05 after AR(1) on a raw 17.43.
-- The same `::date − DATE '2020-01-01'` key appears in 13 functions: weather, grid, the service flow, the recall
-- policy, telemetry, faults, precipitation and more. Only ottoq_derive_visit_needs uses a CT date. So the whole
-- twin's day rolls at 7 PM CDT, inside every demo run. Not fixed tonight: a cross-cutting change to the certified
-- path (FINDINGS G185).

\echo '=== 0354 §4 — the battery by price band (0435) ==='
WITH s AS (
  SELECT e.timestamp, e.bess_output_kw, e.grid_import_kw, e.current_rate_per_kwh AS rate,
         EXTRACT(EPOCH FROM (lead(e.timestamp) OVER (ORDER BY e.timestamp) - e.timestamp)) / 3600.0 AS dt_h
    FROM public.site_energy_snapshots e WHERE e.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0')
SELECT CASE WHEN rate <= 0.052 THEN 'off_peak' WHEN rate < 0.1 THEN 'mid_peak' ELSE 'on_peak' END AS band,
       round(sum(GREATEST(0, bess_output_kw) * dt_h)::numeric) AS discharged_kwh,
       round(sum(GREATEST(0, grid_import_kw) * dt_h)::numeric) AS grid_kwh,
       round(sum(GREATEST(0, grid_import_kw) * dt_h * rate)::numeric, 2) AS grid_usd
  FROM s WHERE dt_h IS NOT NULL AND dt_h < 0.5 GROUP BY 1 ORDER BY 1;
--   band      discharged   grid kWh   grid $       7a42982a discharged
--   off_peak        2 kWh     1,652     85.88       379
--   mid_peak        0 kWh     4,781    439.87     1,860
--   on_peak     1,153 kWh     2,516    462.76        35
-- 0435 holds: the battery's energy went to the expensive afternoon (99.8%, against 1.5%). It started at 2,870 kWh
-- and ended at 1,581 kWh, charging 0 kWh in the run (no cheap window before 19:18).
-- Grid energy is 8,952 kWh against 5,581 on 7a42982a. That is a different demand, not a regression:
--   - dispatches rose 168 → 224;
--   - the DR call no longer froze charging (§5).

\echo '=== 0354 §5 — the DR call (0433), and why it was not complied with (G183, G184) ==='
SELECT to_char(c.issued_at AT TIME ZONE 'America/Chicago','HH24:MI:SS') AS issued_ct,
       to_char(c.expires_at AT TIME ZONE 'America/Chicago','HH24:MI') AS expires_ct,
       round(c.required_load_cap_kw, 1) AS cap_kw, e.payload->>'baseline_kw' AS baseline_kw,
       e.payload->>'required_reduction_kw' AS reduction_kw, e.payload->>'temp_c' AS temp_c
  FROM public.ottoq_dr_calls c
  LEFT JOIN LATERAL (SELECT ev.payload FROM public.ottoq_events ev WHERE ev.event_type = 'twin.dr_call_issued'
                        AND ev.payload->>'dr_call_id' = c.dr_call_id::text LIMIT 1) e ON true
 WHERE c.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0';
-- One call, 14:01:54 → 17:27 CT (205 min): baseline 404.8, reduction 343.2, cap 61.6 kW, heat-triggered at 45.3 °C.
-- 0433 (A) holds: the cap is baseline − reduction, not the reduction. 0433 (C) holds: one ignition, where 7a42982a
-- re-ignited 42 s after its first call expired.
WITH c AS (SELECT issued_at, expires_at, required_load_cap_kw AS cap FROM public.ottoq_dr_calls WHERE sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0'),
e AS (SELECT e.grid_import_kw, e.bess_output_kw, e.total_ev_charging_kw AS ev, e.solar_generation_kw AS pv, e.building_load_kw AS bldg, c.cap
        FROM public.site_energy_snapshots e JOIN c ON e.timestamp >= c.issued_at AND e.timestamp < c.expires_at
       WHERE e.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0')
SELECT count(*) AS samples, round(avg(grid_import_kw)) AS grid_mean, round(max(grid_import_kw)) AS grid_max,
       count(*) FILTER (WHERE grid_import_kw > cap + 1) AS over_cap, round(avg(ev)) AS ev_mean, round(avg(bess_output_kw)) AS bess_mean,
       round(avg(pv)) AS pv_mean, round(avg(bldg)) AS bldg_mean
  FROM e;
-- 432 samples: grid 376 kW mean (max 876) against 62; 363 over the cap. EV 603, battery 138, solar 247,
-- building 156.
WITH c AS (SELECT issued_at, expires_at FROM public.ottoq_dr_calls WHERE sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0')
SELECT x.reason->>'mode' AS mode, count(*) AS n, round(avg(x.setpoint_kw)) AS setpoint_mean,
       round(min((x.reason->>'soc_pct')::numeric), 1) AS soc_min, round(max((x.reason->>'soc_pct')::numeric), 1) AS soc_max
  FROM public.ottoq_energy_commands x JOIN c ON x.issued_at >= c.issued_at AND x.issued_at < c.expires_at
 WHERE x.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND x.command_type = 'bess_setpoint_kw' GROUP BY 1 ORDER BY 2 DESC;
-- thermal_hold 317 (setpoint 0) · discharge_dr 114 (mean 524 kW) · plan_hold 1; SoC 77.8–93.0% throughout.
-- G183: the pack sat at its 48 °C hold with about 2,000 kWh above its floor. Holding the cap needed about 450 kW for
-- 3.4 h (≈ 1,530 kWh), inside what it held, so the binding limit was temperature. 0450 gives it its coolant loop.
-- 0450's V2 replays this call: 46.6 → 26.0 °C in 30 sim-min at −1,492 kW in 45.3 °C air.
-- G184: the EV side, 15 minutes at a time. Starts fell from 17 per 15 min before the call to 3–9 in it, but 33–38
-- sessions stayed active in every window (mostly 19.2 kW L2, lasting hours) and EV load stayed at 485–700 kW.
-- `twin.ottoq_sim_advance_charge_sessions` opens "VEHICLE-FIRST DOCTRINE: charging is NEVER held back" and reads no
-- cap. Under N1 a DR cap is the battery's alone. That is a decision for Chase (FINDINGS G184).

\echo '=== 0354 §6 — CP-SAT (G167 / G173) ==='
SELECT f.status, count(*) AS fires, sum(f.n_submitted) AS submitted,
       count(*) FILTER (WHERE f.fire->>'error' ILIKE '%not one is offerable%') AS no_offerable_charger
  FROM public.ottoq_proposer_fire_log f WHERE f.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' GROUP BY 1;
-- empty 249 (all 249 "not one is offerable") · submitted 33 fires / 1,841 proposals.
SELECT p.status, p.disposition_reason, count(*) FROM public.ottoq_external_proposals p
 WHERE p.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' GROUP BY 1, 2 ORDER BY 3 DESC;
--   refused proposer_abstained 988 · superseded entity_decided_by_other_proposal 761 · superseded newer 59
--   refused stall_reserved 20 · enacted_by_kernel 9 · refused stall_occupied 4
-- 9 enacted, against 0 of 179 on 7a42982a. 0435 took the power cap out of the way. 249 of 282 fires then found no
-- offerable charger at all, so chargers bind the solver on this run, not power. G173's descriptor fix (hard cap =
-- allowance − committed) stays open and is not the binding constraint here.

\echo '=== 0354 §7 — the agent on v20 ==='
SELECT count(*) AS passes, count(*) FILTER (WHERE d.context_frame->'board_blocks'->>'grounding' = 'true') AS grounded,
       count(*) FILTER (WHERE jsonb_array_length(coalesce(d.enacted_action->'rejected','[]')) > 0) AS with_rejections
  FROM public.ottoq_decisions d WHERE d.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND d.resolved_action_context = 'orchestrator_agent';
-- 288 passes, 288 grounded, 0 with rejections. One dial write in the run: energy_reserve_shave on its first pass,
-- switching the day plan on. No write to a dead dial. v20's KNOBS hold.

\echo '=== 0354 §8 — realised site cost and the five KPIs (0439''s metric on the demo run) ==='
SELECT public.ottoq_dial_arm_metrics('324eb0f1-957a-455f-9023-3fb7feeab9a0', '11111111-1111-1111-1111-111111111111',
         (SELECT (c.reason->>'soc_pct')::numeric / 100 * 3000 FROM public.ottoq_energy_commands c
           WHERE c.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND c.command_type = 'bess_setpoint_kw'
           ORDER BY c.tick_seq LIMIT 1)) AS metrics;
-- site $2,040.37/day. That is energy $989.14 + demand $958.26/day + battery wear $23.13 + terminal SoC $69.84.
-- Peak 30-min 1,337.4 kW. KPIs: asset hours available 81.16/day, turns per point 4.95/day, touch events per turn
-- 0.026, p95 time to service 53.8 min. Unserved returns 14. Safety-critical failures 81, all refused (0
-- unprevented). DR-deferred assignments 4,666.
-- Not comparable with 7a42982a's $1,612.73: 56 more dispatches, and a DR call that no longer froze charging. The
-- dial experiments, not demo runs, are the instrument for cost claims.

\echo '=== 0354 §9 — G177: the boot hour set the billed peak ==='
SELECT to_char(date_trunc('hour', e.timestamp AT TIME ZONE 'America/Chicago'),'HH24') AS hr_ct,
       round(max(e.grid_import_kw)) AS grid_max, round(avg(e.total_ev_charging_kw)) AS ev_avg,
       round(avg(e.bess_output_kw)) AS bess_avg, round(max(e.billing_period_peak_kw)) AS billed_peak
  FROM public.site_energy_snapshots e WHERE e.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' GROUP BY 1 ORDER BY 1 LIMIT 3;
-- 04: grid max 1,624, EV 1,142 mean, battery 3 kW mean, billed peak 1,624, and it never moved again all run.
-- The day plan forecast the running sessions only, not the fleet queued for chargers. 0444 adds the queue.

\echo '=== 0354 §10 — G178: the battery answered the tick''s new sessions one tick late ==='
WITH t AS (
  SELECT c.issued_at, (c.reason->>'net_load_kw')::numeric AS net_seen
    FROM public.ottoq_energy_commands c WHERE c.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND c.command_type = 'bess_setpoint_kw'),
s AS (
  SELECT t.*, (SELECT count(*) FROM public.ocpp_sessions x WHERE x.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND x.started_at = t.issued_at) AS started,
         (SELECT e.grid_import_kw + e.bess_output_kw FROM public.site_energy_snapshots e
           WHERE e.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND e.timestamp = t.issued_at LIMIT 1) AS net_actual
    FROM t)
SELECT count(*) FILTER (WHERE started > 0) AS ticks_with_starts, sum(started) AS sessions_started,
       round(avg(net_actual - net_seen) FILTER (WHERE started > 0)) AS unseen_kw_start_ticks,
       round(avg(net_actual - net_seen) FILTER (WHERE started = 0)) AS unseen_kw_other_ticks
  FROM s;
-- 387 ticks started 635 sessions. On those ticks the orchestrator under-saw the net load by 39 kW, against −21 kW on
-- other ticks. That is a 60 kW bias at demo cadence (a 0.48-min tick). At the harness's 30-min tick it is a whole
-- billing interval. 0445 moves the dispatch after reconciliation.

\echo '=== 0354 §11 — G179: zero-energy DCFC sessions at the daytime cap ==='
SELECT count(*) AS sessions, count(DISTINCT s.vehicle_id) AS vehicles, count(DISTINCT s.stall_id) AS stalls,
       min(to_char(s.started_at AT TIME ZONE 'America/Chicago','HH24:MI')) AS first_ct,
       max(to_char(s.started_at AT TIME ZONE 'America/Chicago','HH24:MI')) AS last_ct, round(sum(s.energy_delivered_kwh), 3) AS kwh
  FROM public.ocpp_sessions s JOIN public.stalls st ON st.id = s.stall_id
 WHERE s.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND st.stall_type::text = 'dcfc'
   AND s.soc_start >= 89.5 AND s.energy_delivered_kwh < 0.1;
-- 340 sessions, 3 vehicles, 3 of the 10 fast chargers, 10:11–14:01 CT, 0.000 kWh, 118 charger-minutes.
-- 0446's picker refuses a stall whose own cap would stop the session before it starts. Its V1 ran at apply on live
-- rows (rolled back): by day at 90% → L2; with L2 faulted → abstain; at 40% → DCFC; by night at 90% → DCFC.

\echo '=== 0354 §12 — charge sessions by starting SoC (the heat derate, G186) ==='
SELECT st.stall_type::text AS kind,
       CASE WHEN s.soc_start < 40 THEN 'a <40' WHEN s.soc_start < 60 THEN 'b 40-59' WHEN s.soc_start < 75 THEN 'c 60-74'
            WHEN s.soc_start < 85 THEN 'd 75-84' ELSE 'e 85+' END AS band,
       count(*) AS n, round(sum(s.energy_delivered_kwh)) AS kwh,
       round(sum(s.energy_delivered_kwh) / NULLIF(sum(EXTRACT(EPOCH FROM (s.ended_at - s.started_at))/3600.0), 0)) AS eff_kw
  FROM public.ocpp_sessions s JOIN public.stalls st ON st.id = s.stall_id
 WHERE s.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND s.ended_at IS NOT NULL GROUP BY 1, 2 ORDER BY 1, 2;
-- dcfc: <40 32 sessions 57 kW · 40–59 98 sessions 40 kW · 60–74 5 sessions 51 kW · 85+ 340 at 0 (§11)
-- l2:   12–15 kW effective across bands (19.2 kW chargers, 0.88 AC→DC)
-- G186: `ottoq_sim_compute_charge_rate` derates 2% per °C of battery temperature above 35 °C, and its own comment calls
-- the cold side INL-calibrated and the heat side "unchanged". The session puts the pack at ambient + 5 + U·8 + up to
-- 15, with no thermal management. A liquid-cooled robotaxi pack would not sit at 60–70 °C on a charger. 0449 lowers
-- ambient by up to 4.7 °C; the pack model stays passive. Fix it with a sourced curve, not a guess.

\echo '=== 0354 §13 — G181: the maintenance loop ==='
SELECT coalesce(d.return_trigger, '(open)') AS trigger, count(*) AS n, round(avg(d.actual_duration_min)::numeric, 1) AS mean_min,
       count(DISTINCT d.vehicle_id) AS vehicles
  FROM public.ottoq_vehicle_dispatches d WHERE d.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' GROUP BY 1 ORDER BY 2 DESC;
-- service_interval_due 180 of 224 (80%), 76 vehicles, 21.5 min mean · sensor_soil 23 · comms_stale 8 ·
-- run_stopped 4 · overnight_prestage 4 · wash_cadence 4 · prime_inbound 1
SELECT to_char(date_trunc('hour', e.sim_clock_at AT TIME ZONE 'America/Chicago'),'HH24') AS hr,
       round(avg((e.payload->>'deployed')::numeric), 1) AS deployed, round(avg((e.payload->>'desired')::numeric), 1) AS desired
  FROM public.ottoq_events e WHERE e.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND e.event_type = 'twin.auto_dispatch_emit'
 GROUP BY 1 ORDER BY 1;
-- 05 9.9/14 · 06 11.8/25 · 07 5.1/37 · 08 7.4/45 · 09 5.5/49 · 10 6.9/50 · 11 4.3/49 · 12 2.5/48 · 13 4.2/48
-- 14 0.9/49 · 15 2.6/50 · 16 3.6/52 · 17 2.8/52 · 18 3.0/52 · 19 4.8/49
-- After 07:00 CT the depot met 2–25% of demand. This is the largest defect the run carried, and it is upstream of
-- every energy number here. 0448 registers implementation 3 (parked) and the v1-vs-v3 experiment. The next
-- validation run takes implementation 3 at run scope.

\echo '=== 0354 §14 — G182: the readiness gate''s escape hatch ==='
SELECT count(*) AS overrides, round(max((e.payload->>'held_min')::numeric), 1) AS max_held_min,
       count(*) FILTER (WHERE (e.payload->>'held_min')::numeric > EXTRACT(EPOCH FROM (e.sim_clock_at - r.sim_clock_start))/60) AS older_than_run,
       round(min((e.payload->>'held_min')::numeric), 1) AS min_held_min
  FROM public.ottoq_events e JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
 WHERE e.sim_run_id = '324eb0f1-957a-455f-9023-3fb7feeab9a0' AND e.event_type = 'twin.deploy_gate_override';
-- 14 overrides. 7 had held longer than the run existed (max 30,586.5 min: a stamp from a certification date). The
-- smallest, 307 min, is a genuine in-run hold past the 240-min cap. 0447 scopes the stamp to its run.

-- ══ §15 THE TWIN, 2D AND 3D (cockpit on :8080, headless probe, 150–170 s per window) ══════════════════════════
--   morning    110 cars, 70 samples, 0 stuck
--   afternoon  111 cars, 70 samples, 0 stuck
--   DR call    116 cars, 70 samples, 0 stuck (stopped share 0.098 while the gate held starts)
--   evening    112 cars, 68 samples, 0 stuck
--   Header at the evening probe: deployed 5, charging 35, staged 55, battery 54%, solar 0 kW. That is G181 as the
--   operator sees it.
--   Each probe logged one ERR_CERT_AUTHORITY_INVALID resource load in the sandbox browser, the same single error on
--   all four. It is not an engine signal.
--   Two display notes for later:
--   - The header clock shows the sim clock in UTC while the timeline shows CT.
--   - Chaos Mode reads "ON ×2.5" while the run's profile carries spread 1.4.
