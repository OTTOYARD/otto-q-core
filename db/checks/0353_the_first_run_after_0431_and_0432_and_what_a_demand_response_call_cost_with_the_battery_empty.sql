-- 0353  **The first busy_day run after 0431 and 0432, measured end to end. Both fixes hold. Two defects in the energy
--       layer that the ranked review could only argue from source now have their costs measured.**
--       (a) The battery reached the expensive afternoon empty. 98.5% of its discharge went at $0.052–$0.092/kWh,
--           after the month's peak was already billed, so it bought no demand charge.
--       (b) A demand-response call then froze every new charge for three and a half hours, while solar held the
--           site's grid import well under the call's cap.
--
--       Run `7a42982a-a905-4464-83f9-b602b076c5dc` (busy_day, twin depot `11111111-…`, operator_demo, armed; agent
--       v19; governor raised to 900 sim-minutes so the run crosses the 14:00–19:00 CT DR window). Started 23:22 UTC
--       on 2026-09-22 (6:22 PM CT). Measured 00:00–01:20 UTC on 2026-09-23 (7:00–8:20 PM CT), while and after it ran.
--
--       What each section answers:
--         §1  0431 — departures without the readiness check: 2 of 124, both through the door 0437 now closes.
--         §2  0432 + v19 — the agent: 0 writes to the demand dial, 247 of 247 passes grounded, reversals 87 → 2.
--         §3  G160 — the DR call: its cost under today's gate, and the counterfactual allowance under 0433 and
--             0433 + 0435.
--         §4  G169 — the battery: where its 2,274 kWh went, by price band.
--         §5  G173 — the solver's power headroom while the battery shaved (16 kW average over 811 ticks).
--         §6  G162 — fast-tracks: 250 events moving 426 vehicles.
--         §7  the twin, 2D and 3D, during the DR call.

\echo '=== 0353 §1 — departures that left with the readiness check still pending (0431) ==='
SELECT (SELECT count(*) FROM public.ottoq_vehicle_dispatches WHERE sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc') AS dispatches,
       (SELECT count(*) FROM public.ottoq_assert_departure_readiness('7a42982a-a905-4464-83f9-b602b076c5dc')) AS violations;
-- MEASURED_S1_TOTALS
-- Before 0431: 24 of 93 (0682752c) and 26 of 106 (6a8a7029), i.e. 24.5–25.8%.
--
-- The path each violation took (vehicle.state_changed, diff->current_state):
SELECT e.entity_id AS vehicle_id, to_char(e.sim_clock_at AT TIME ZONE 'America/Chicago','HH24:MI:SS') AS sim_ct,
       e.payload->'diff'->'current_state'->>'from' AS from_state, e.payload->'diff'->'current_state'->>'to' AS to_state
  FROM public.ottoq_events e
 WHERE e.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND e.event_type = 'vehicle.state_changed'
   AND e.entity_id IN (SELECT vehicle_id FROM public.ottoq_assert_departure_readiness('7a42982a-a905-4464-83f9-b602b076c5dc'))
   AND e.payload->'diff' ? 'current_state'
 ORDER BY e.entity_id, e.sim_clock_at;
-- 7ec698b8…  07:03:50 staged_awaiting_service → charging_l2 · 07:56:04 charging_l2 → staged_awaiting_service
--            · 07:56:04 staged_awaiting_service → deployed
-- 72ccc3d4…  10:54:03 charging_l2 → staged_awaiting_service · 10:54:25 staged_awaiting_service → deployed
-- Both left through staged_awaiting_service (svc_step 'ready'), where the check step never performed the check.
-- That is G170, and 0437 closes it.

\echo '=== 0353 §2 — the agent on v19 (0432): demand dial, grounding, dither, holds ==='
SELECT count(*) AS agent_passes,
       count(*) FILTER (WHERE d.context_frame->'board_blocks'->>'grounding' = 'true') AS grounded,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(d.enacted_action->'applied','[]')) a
                                       WHERE a->>'key' = 'deploy_peak_fraction')) AS passes_writing_demand
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND d.resolved_action_context = 'orchestrator_agent';
-- MEASURED_S2_PASSES
-- 0682752c (v18): 106 writes to deploy_peak_fraction, the first at tick 1 (0.95 from a board value of 0.90).

-- dither, 0352 §3's definition (consecutive set_policy writes on one dial that reverse direction):
WITH w AS (
  SELECT d.tick_seq, a->>'key' AS dial, (a->>'value')::numeric AS v
    FROM public.ottoq_decisions d, jsonb_array_elements(coalesce(d.enacted_action->'applied','[]')) a
   WHERE d.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND d.resolved_action_context = 'orchestrator_agent'
     AND a->>'type' = 'set_policy'),
s AS (
  SELECT dial, tick_seq, v, lag(v) OVER (PARTITION BY dial ORDER BY tick_seq) AS prev,
         lag(v, 2) OVER (PARTITION BY dial ORDER BY tick_seq) AS prev2
    FROM w)
SELECT dial, count(*) AS writes, count(*) FILTER (WHERE v = prev) AS unchanged_resend,
       count(*) FILTER (WHERE prev IS NOT NULL AND v <> prev) AS changes,
       count(*) FILTER (WHERE prev IS NOT NULL AND prev2 IS NOT NULL AND sign(v - prev) * sign(prev - prev2) < 0) AS reversals
  FROM s GROUP BY 1 ORDER BY 2 DESC;
-- MEASURED_S2_DITHER

-- what v19's holds stopped (enacted_action->'rejected'):
SELECT coalesce(r->>'reason', r->>'error') AS reason, coalesce(r->>'key', r->>'action') AS dial, count(*) AS n
  FROM public.ottoq_decisions d, jsonb_array_elements(coalesce(d.enacted_action->'rejected','[]')) r
 WHERE d.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND d.resolved_action_context = 'orchestrator_agent'
 GROUP BY 1, 2 ORDER BY 3 DESC;
-- MEASURED_S2_HOLDS
-- NEW (G174): the agent's energy writes land on dials that do nothing in the mode it chose. With
-- energy_reserve_shave on (the agent turned it on at 23:32 UTC), ottoq_energy_orchestrate replaces the
-- factor-based target with the water-fill's, so energy_demand_factor_peak and energy_demand_factor_expensive
-- have no effect.

\echo '=== 0353 §3 — the DR call (G160) ==='
SELECT to_char(c.issued_at AT TIME ZONE 'America/Chicago','HH24:MI:SS') AS issued_ct,
       to_char(c.expires_at AT TIME ZONE 'America/Chicago','HH24:MI') AS expires_ct, round(c.duration_minutes) AS dur_min,
       round(c.required_load_cap_kw) AS cap_kw, c.reason, c.program
  FROM public.ottoq_dr_calls c WHERE c.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' ORDER BY c.issued_at;
-- MEASURED_S3_CALLS
-- At ignition: ambient 36.5 °C · battery SoC 13.8% (the discharge gate is floor 10 + uncertainty + 3) · grid 357 kW,
-- EV 629 kW, building 108 kW, solar 380 kW · baseline (mean grid over the prior 60 sim-min) 329 kW.

-- the cost, by 15-minute bucket (stall_assignment decisions; energy snapshots):
WITH c AS (SELECT issued_at, expires_at, required_load_cap_kw AS cap FROM public.ottoq_dr_calls
            WHERE sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' ORDER BY issued_at LIMIT 1),
e AS (SELECT to_char(date_trunc('hour', e.timestamp AT TIME ZONE 'America/Chicago')
                     + floor(EXTRACT(MINUTE FROM e.timestamp) / 15) * interval '15 min', 'HH24:MI') AS b,
             e.total_ev_charging_kw, e.grid_import_kw, e.solar_generation_kw, e.bess_output_kw
        FROM public.site_energy_snapshots e, c
       WHERE e.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND e.timestamp >= c.issued_at - interval '30 minutes'
         AND e.timestamp < c.expires_at + interval '30 minutes'),
d AS (SELECT to_char(date_trunc('hour', d.sim_clock AT TIME ZONE 'America/Chicago')
                     + floor(EXTRACT(MINUTE FROM d.sim_clock) / 15) * interval '15 min', 'HH24:MI') AS b, d.outcome_status
        FROM public.ottoq_decisions d, c
       WHERE d.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND d.action_context = 'stall_assignment'
         AND d.sim_clock >= c.issued_at - interval '30 minutes' AND d.sim_clock < c.expires_at + interval '30 minutes'),
ea AS (SELECT b, round(avg(total_ev_charging_kw)) AS ev_kw, round(avg(grid_import_kw)) AS grid_kw,
              round(avg(solar_generation_kw)) AS solar_kw, round(avg(bess_output_kw)) AS bess_kw FROM e GROUP BY b),
da AS (SELECT b, count(*) FILTER (WHERE outcome_status = 'deferred_site_power_cap') AS deferred,
              count(*) FILTER (WHERE outcome_status = 'enacted') AS enacted FROM d GROUP BY b)
SELECT ea.*, COALESCE(da.deferred, 0) AS deferred, COALESCE(da.enacted, 0) AS enacted
  FROM ea LEFT JOIN da USING (b) ORDER BY b;
-- MEASURED_S3_TIMELINE

-- The counterfactual, from the same rows. Today's gate compares committed EV kW with the call's 241 kW. 0433 reads
-- the 241 as a REDUCTION: cap = baseline 329 − 241 = 88 kW of grid, and EV may draw cap − building + solar +
-- sustainable battery discharge.
--   0433 alone, battery empty (as here):  88 − 145 + 368 + 0            ≈ 311 kW of EV
--   0433 + 0435's 600 kWh reserve:        88 − 145 + 368 + 600/3.5 h    ≈ 482 kW of EV
--   today's gate:                          241 kW of committed EV, against 629 kW at ignition
-- So 0433 alone recovers about 70 kW. Most of the recovery needs a battery that still holds energy at 14:15,
-- which is 0435's job. That is why the two ship together.
-- MEASURED_S3_COMPLIANCE

\echo '=== 0353 §4 — where the battery''s energy went (G169) ==='
WITH s AS (
  SELECT e.timestamp, e.bess_output_kw, e.current_rate_per_kwh AS rate,
         EXTRACT(EPOCH FROM (lead(e.timestamp) OVER (ORDER BY e.timestamp) - e.timestamp)) / 3600.0 AS dt_h
    FROM public.site_energy_snapshots e WHERE e.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc')
SELECT CASE WHEN rate <= 0.052 THEN 'off_peak 0.052' WHEN rate < 0.1 THEN 'mid_peak 0.085-0.092' ELSE 'on_peak 0.158-0.235' END AS band,
       round(sum(GREATEST(0, bess_output_kw) * dt_h)::numeric) AS discharged_kwh,
       round(sum(GREATEST(0, -bess_output_kw) * dt_h)::numeric) AS charged_kwh,
       round(sum(GREATEST(0, bess_output_kw) * dt_h * rate)::numeric, 2) AS grid_cost_displaced_usd
  FROM s WHERE dt_h IS NOT NULL AND dt_h < 0.5 GROUP BY 1 ORDER BY 1;
-- MEASURED_S4_BANDS
-- The billing-period peak (the demand ratchet) was 1,657 kW, set in the 04:00 boot burst, so no discharge after
-- 04:30 bought any demand charge. The water-fill's target by hour, 05–10: 973 → 192 → 262 → 544 → 478 → 679 kW,
-- against net load 764 → 699 → 848 → 790 → 715 → 668 kW. SoC 94.7% at 04:12 → 13.7% by 14:00.
-- Why the target was so low: ottoq_forecast_net_load sees EV load only from sessions already running and
-- dispatches already returning, and on this depot a dispatch lasts 0.3–0.6 sim-hours. So its 8-hour horizon
-- was base load almost everywhere, and the water-fill shaved a load it believed was about to vanish (0435 §1).

\echo '=== 0353 §5 — the solver''s power headroom while the battery shaved (G173) ==='
WITH cc AS (SELECT c.tick_seq, c.issued_at, c.setpoint_kw AS cap_kw FROM public.ottoq_energy_commands c
             WHERE c.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND c.command_type = 'charge_cap_kw'),
b AS (SELECT c.tick_seq, c.reason->>'mode' AS mode FROM public.ottoq_energy_commands c
       WHERE c.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND c.command_type = 'bess_setpoint_kw'),
j AS (SELECT cc.*, b.mode, e.total_ev_charging_kw AS ev, cc.cap_kw - e.total_ev_charging_kw AS headroom
        FROM cc JOIN b USING (tick_seq)
        JOIN public.site_energy_snapshots e ON e.sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND e.timestamp = cc.issued_at)
SELECT mode, count(*) AS ticks, round(avg(headroom)) AS avg_headroom_kw,
       count(*) FILTER (WHERE headroom < 100) AS under_100kw
  FROM j GROUP BY 1 ORDER BY 2 DESC;
-- measured at 00:27 UTC (tick ~1,060):
--   discharge_reserve_shave   811 ticks   16 kW avg headroom   808 under 100 kW
--   hold_reserve              117         117                   64
--   idle                      112         920                   12
--   discharge_shave            20          11                   20
-- ottoq_build_site_descriptor gives CP-SAT power_cap_kw_hard = floor(LEAST(service_max, this cap)), and
-- solvers/cpsat/model.py spends it in AddCumulative. With 16 kW of headroom a new charge can start only after
-- another ends, which is G167's "planned to start at +N min, beyond this tick's 30-min window".

\echo '=== 0353 §6 — deploy-pressure fast-tracks (G162) ==='
SELECT count(*) AS events, sum((payload->>'fasttracked')::int) AS vehicles
  FROM public.ottoq_events WHERE sim_run_id = '7a42982a-a905-4464-83f9-b602b076c5dc' AND event_type = 'twin.deploy_pressure_fasttrack';
-- MEASURED_S6

-- §7 the twin, 2D and 3D (scratchpad live_probe.mjs against the cockpit dev server, 120 s at sim 14:42 CT, during
-- the call): 58 samples, 109 cars rendered, 25 samples with a moving vehicle, 0 stopped, 0 stuck. Header: deployed 7
-- · charging 28 · staged 77 · BESS 14% · solar 369 kW · DCFC 2/10 · L2 27/30 · staging 78/113. That is the call's
-- cost made visible: eight fast chargers idle while 77 vehicles wait in staging.
