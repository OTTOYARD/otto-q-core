-- 0403  **The door, the gate's clock and the seat order: the first operator run under 0544 and 0545, beside 9eab647f.**
--
--       Written on 2026-09-27 (CT) for the validation run after 0544 (a car that is not finished cannot be dispatched:
--       the door refuses, the dispatch ledger rejects) and 0545 (G269: the readiness gate times a hold from the car's
--       return, not from its first hold; G270: a bay seat goes to the most overdue car first; G271: a charger goes to the
--       car with the highest response ratio, not the lowest charge). Read-only.
--       The run is 4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c. Cron 773 started it at 04:13 UTC (11:13 PM CT), once all nine
--       canon columns had passed under 0545 (verdicts 540-548). It is busy_day at 8x on 9eab647f's seed, so it opens at
--       the same sim minute (4:41 AM CT) and draws the same world. What differs is the engine: 0544 and 0545 together.
--       0544 changes nothing a run writes when the deploy plan filters first, so a difference below is 0545's.
--
--       **9eab647f's side is §0, read before this run purged it** (`ottoq_purge_prior_runs`, class 'engine').

-- ══ §0 BEFORE: 9eab647f (0402's READs) ══════════════════════════════════════════════════════════════════════════════
--
--   Read 2026-09-28 03:25-04:10 UTC (10:25-11:10 PM CT). §1-§6 are 0402's READs; §5's hold line and §7 were measured
--   on 9eab647f's rows with this file's queries before this run purged them.
--     §1  the governor stopped the run at sim 1:47 PM CT: 546 sim-minutes, 1,086 ticks. KPI 1 asset hours 124.45 · KPI 2
--         turns per point 3.01 · KPI 3 peak site kW 1,090.5 (demand 1,118.6) · KPI 4 touches per turn 1.006 · KPI 5 p95
--         time to service 248.6 min (p50 9.3), 22 returns unserved. Charge wait p50 52.6, p95 333, max 475.1 min; 153 of
--         179 visits owing a charge charged. Supply gap 229.2 of 355.6 demand car-hours unmet (64.5%), 126.4 deployed,
--         peak shortfall 40. Archive: 116 dispatches, 174 charge sessions, 514 tasks completed.
--     §2  112 departures, 0 below 99%, 0 with a service open.
--     §3  0544 was not yet applied: no door, no floor.
--     §4  4 escalations to a person. The first was G269's false alarm: Tesla-AV-061, "held 285.8 min, missing charge",
--         charging on an L2 inside the counted hold (2 state changes). The other three each waited 240 minutes at 100%
--         for a deep clean, with no state change.
--     §5  32 needs-card seats. 15 went to cars due out later (2 to 758 minutes ahead), 10 to cars with no deploy time and
--         7 to late cars (wash 6, detail 1): 25 of 32 to cars that were not late (G270). Gate holds on this run's clock:
--         94 cars held, mean longest hold 48 min, longest 323.3 min, 4 at the cap. (28 cars carried a prior run's stamp
--         into the boot. Counted without the run filter they read 100 held, longest 1,350 min, 30 at the cap.)
--     §6  41 recheck events. 4 escalated. The gate held at most 32 cars at once (the boot tick). Staging overflow peaked
--         at 54. Bay entries: 32 wash, 12 detail, 27 service.
--     §7  126 waits on need_charge. By how each ended:
--           to a charger: 49 below 90% (p50 8.6, p95 361.3, max 462.2 min) and 18 top-offs (every one 1.7 min);
--           back to the gate: 36, all at 100%, each under 2 min;
--           still waiting at the teardown: 22.
--         Of the 22 still waiting, 15 were boot cars set on need_charge at 4:51 AM at 91-98%: Tesla-AV-042, -045, -051,
--         -052, -056, -063, -068, Tesla-RT-006, Waymo-005, Waymo-AV-007, -025, -036, Zoox-AV-078, -094, -100 (the last
--         with no charge in the stream). They waited all 536 minutes and their charge never moved. A sixteenth,
--         Waymo-AV-015, waited 510 minutes from 5:17 AM at 89%. 14 of the 16 had no visit. That is **142.5 car-hours
--         idle, more than the 126.4 deployed (G271)**. The other 6 still waiting were 51-83% cars that joined from
--         7:34 AM on, the longest waiting 373 minutes (Waymo-AV-006, 83%).

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0403 §1 — the run and its scorecard ==='
SELECT r.sim_run_id, r.run_by, r.status, r.random_seed, r.sim_clock_start, r.sim_clock_current, r.tick_count,
       r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c';
SELECT public.ottoq_kpi_five('4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c');
SELECT public.ottoq_kpi_charge_wait('4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c');
SELECT public.ottoq_kpi_supply_gap('4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c') - 'by_hour_ct';
-- READ: pending.

-- ══ §2 RULE 9 STILL HOLDS: NO DEPARTURE WITH A SERVICE OPEN OR A CHARGE SHORT ═════════════════════════════════════════
--
--   0402 §2's query. Both must be 0.

\echo '=== 0403 §2 — departures, and any that left unfinished ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c'),
dep AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS left_at
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' IN ('en_route_to_deployment', 'deployed')
     AND e.payload->'diff'->'current_state'->>'from' NOT IN ('en_route_to_deployment', 'deployed')
     AND e.sim_clock_at > run.t0),
dv AS (
  SELECT d.*,
         (SELECT vn.visit_id FROM public.ottoq_visit_needs vn, run
           WHERE vn.vehicle_id = d.vehicle_id AND vn.sim_run_id = run.id AND vn.arrived_at <= d.left_at
           ORDER BY vn.arrived_at DESC, vn.created_at DESC LIMIT 1) AS visit_id,
         (SELECT x.soc_at_dispatch_pct FROM public.ottoq_vehicle_dispatches x, run
           WHERE x.vehicle_id = d.vehicle_id AND x.sim_run_id = run.id
             AND x.dispatched_at BETWEEN d.left_at - interval '2 minutes' AND d.left_at + interval '2 minutes'
           ORDER BY abs(extract(epoch FROM x.dispatched_at - d.left_at)) LIMIT 1) AS soc
    FROM dep d),
open_at AS (
  SELECT dv.vehicle_id, dv.left_at, a->>'svc' AS svc
    FROM dv JOIN public.ottoq_visit_needs vn ON vn.visit_id = dv.visit_id
    CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
   WHERE a->>'svc' <> 'readiness_check'
     AND NOT (COALESCE(a->>'status', 'pending') IN ('done', 'cancelled')
              AND COALESCE((a->>'done_at')::timestamptz, (a->>'closed_at')::timestamptz, dv.left_at) <= dv.left_at))
SELECT (SELECT count(*) FROM dv) AS departures,
       (SELECT count(*) FROM dv WHERE soc < 99) AS below_99,
       (SELECT min(soc) FROM dv) AS min_soc,
       (SELECT count(DISTINCT (vehicle_id, left_at)) FROM open_at) AS left_with_open_work;
-- READ: pending.

-- ══ §3 THE DOOR AND THE FLOOR (0544): NEITHER SHOULD EVER FIRE ════════════════════════════════════════════════════════
--
--   The deploy plan offers only a departure-clear car, so the door never refuses and the trigger never rejects. A
--   refusal here means some path offered an unfinished car; a tick failure naming 0544 means one wrote the row itself.

\echo '=== 0403 §3 — door refusals and floor rejections ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.dispatch_refused_unfinished') AS door_refusals,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed') AS tick_failures,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed' AND e.payload::text LIKE '%0544 (CLAUDE.md rule 9)%') AS floor_rejections
  FROM public.ottoq_events e WHERE e.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c';
-- READ: pending. All three must be 0.

-- ══ §4 G269: AN ESCALATION IS A CAR THAT WAITED, NOT ONE THAT WAS SERVED ═══════════════════════════════════════════════
--
--   For each escalation, did the car change state (charger, bay) inside the time the gate counted? Under 0545 none
--   should: the gate times a hold from the car's last state change.

\echo '=== 0403 §4 — escalations, and whether the car was served inside its counted hold ==='
SELECT v.display_name, e.sim_clock_at AT TIME ZONE 'America/Chicago' AS escalated_ct,
       (e.payload->>'held_min')::numeric AS held_min, e.payload->'missing' AS missing,
       (SELECT count(*) FROM public.ottoq_events s
         WHERE s.sim_run_id = e.sim_run_id AND s.entity_id = e.entity_id AND s.event_type = 'vehicle.state_changed'
           AND s.payload->'diff' ? 'current_state'
           AND s.sim_clock_at > e.sim_clock_at - make_interval(secs => (e.payload->>'held_min')::numeric * 60)
           AND s.sim_clock_at < e.sim_clock_at) AS state_changes_inside_the_hold
  FROM public.ottoq_events e LEFT JOIN public.vehicles v ON v.id = e.entity_id
 WHERE e.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c' AND e.event_type = 'twin.deploy_gate_escalated'
 ORDER BY e.sim_clock_at;
-- READ: pending. state_changes_inside_the_hold must be 0 on every row.

-- ══ §5 G270: WHO GOT THE BAY SEATS ═══════════════════════════════════════════════════════════════════════════════════
--
--   The needs card's deploy time for each car seated by the bay admission (4b), from the decision's context frame. On
--   9eab647f 25 of 32 seats went to cars due out later or with no deploy time, while late cars waited.

\echo '=== 0403 §5 — needs-card seats by the seated car''s deploy time ==='
SELECT d.enacted_action->>'purpose' AS purpose,
       CASE WHEN d.context_frame->>'minutes_to_deploy' IS NULL THEN 'no deploy time'
            WHEN (d.context_frame->>'minutes_to_deploy')::int < 0 THEN 'late'
            ELSE 'due later' END AS seated_car,
       count(*) AS seats,
       min((d.context_frame->>'minutes_to_deploy')::int) AS min_mtd, max((d.context_frame->>'minutes_to_deploy')::int) AS max_mtd
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c' AND d.enacted_action->>'source' = 'needs_card' AND d.outcome_status = 'enacted'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- the longest a car waited at the gate before it was seated or released, by whether it was late when it left the gate
WITH holds AS (
  SELECT e.entity_id, max((e.payload->'diff'->'config'->'to'->'deploy_gate'->>'held_min')::numeric) AS held
    FROM public.ottoq_events e
   WHERE e.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate' ? 'held_min'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate'->>'run' = e.sim_run_id::text   -- not a prior run's stamp
   GROUP BY 1)
SELECT count(*) AS cars_held, round(avg(held)) AS mean_max_hold_min, max(held) AS longest_hold_min,
       count(*) FILTER (WHERE held >= 240) AS reached_the_cap
  FROM holds;
-- READ: pending.

-- ══ §6 WHAT HOLDING COSTS ═════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0403 §6 — the gate, staging and the bays ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS recheck_events,
       count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_escalated') AS escalated_to_a_person,
       max((e.payload->>'held')::int) FILTER (WHERE e.event_type = 'twin.deploy_gate_summary') AS gate_held_max,
       max((e.payload->>'overflow')::int) FILTER (WHERE e.event_type = 'twin.staging_overflow') AS staging_overflow_max
  FROM public.ottoq_events e WHERE e.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c';
SELECT (SELECT jsonb_object_agg(to_state, k) FROM (
          SELECT e.payload->'diff'->'current_state'->>'to' AS to_state, count(*) AS k
            FROM public.ottoq_events e WHERE e.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c' AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
           GROUP BY 1) q) AS bay_entries;
-- READ: pending.

-- ══ §7 G271: NO CAR STARVES ON need_charge ════════════════════════════════════════════════════════════════════════════
--
--   Every wait on need_charge, from the signed state stream: it starts where a staged car's step becomes need_charge and
--   ends at its next change of state or step, to a charger or anywhere else. The teardown's `offline` at the run's last
--   sim minute is not an end: a wait still open then is counted as waiting to the end. The SoC at the start is the
--   stream's last SoC for the car at or before it. Under 0545 (c) a top-off rises to the front within minutes, so no
--   top-off should be waiting at the end, and the longest wait of any band should fall well below 9eab647f's 536 minutes.

\echo '=== 0403 §7 — waits on need_charge, by SoC at the start and by how each ended ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c'),
st AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'current_state'->>'to' AS to_state,
         e.payload->'diff'->'config'->'to'->>'svc_step' AS step_to,
         e.payload->'diff'->'config'->'from'->>'svc_step' AS step_from,
         e.payload->'diff' ? 'config' AS has_cfg, e.payload->'diff' ? 'current_state' AS has_state,
         (e.payload->'diff'->'current_soc'->>'to')::numeric AS soc_to
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'),
starts AS (
  SELECT s.vehicle_id, s.at AS began, s.seq,
         (SELECT s0.soc_to FROM st s0 WHERE s0.vehicle_id = s.vehicle_id AND s0.soc_to IS NOT NULL AND s0.seq <= s.seq
           ORDER BY s0.seq DESC LIMIT 1) AS soc_at_start
    FROM st s WHERE s.has_cfg AND s.step_to = 'need_charge' AND COALESCE(s.step_from, '') <> 'need_charge'),
ends AS (
  SELECT b.*, x.at AS ended, x.to_state, x.step_to
    FROM starts b LEFT JOIN LATERAL (
      SELECT s2.* FROM st s2, run WHERE s2.vehicle_id = b.vehicle_id AND s2.seq > b.seq
         AND NOT (s2.to_state = 'offline' AND s2.at >= run.t1)
         AND ((s2.has_state AND s2.to_state <> 'staged_awaiting_service')
           OR (s2.has_cfg AND COALESCE(s2.step_to, '') <> 'need_charge'))
       ORDER BY s2.seq LIMIT 1) x ON true),
w AS (
  SELECT e.*, extract(epoch FROM (COALESCE(e.ended, run.t1) - e.began)) / 60.0 AS wait_min,
         CASE WHEN e.ended IS NULL THEN 'still waiting at the end'
              WHEN e.to_state IN ('charging_l2', 'charging_dcfc') THEN 'to a charger'
              WHEN e.step_to = 'need_deploy' THEN 'back to the gate'
              ELSE COALESCE(e.to_state, e.step_to, 'other') END AS how,
         CASE WHEN e.soc_at_start >= 90 THEN 'top-off (>=90%)' WHEN e.soc_at_start IS NULL THEN 'unknown' ELSE 'below 90%' END AS band
    FROM ends e, run)
SELECT band, how, count(*) AS waits,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY wait_min)::numeric, 1) AS p50_min,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY wait_min)::numeric, 1) AS p95_min,
       round(max(wait_min)::numeric, 1) AS max_min, min(soc_at_start) AS min_soc, max(soc_at_start) AS max_soc
  FROM w GROUP BY 1, 2 ORDER BY 1, 2;
-- READ: pending.

-- ══ §8 THE GATE'S FLAG OUTLIVES THE HOLD (0545 §4; G208, G218) ════════════════════════════════════════════════════════
--
--   The gate flags a car it has held past its patience (`deploy_gate_stuck`, 45 min) or its hard cap
--   (`deploy_gate_hard_cap`, 240 min) with `flagged_issue`. Its release drops the `deploy_gate` stamp and keeps the flag,
--   and only a service-bay seat clears it (0475). Counted here: releases that kept the flag, and whether the car was
--   later in a service bay. Measured, not fixed: 0545 §4 left it out.
--   9eab647f (measured 04:12 UTC, before the purge): 8 releases kept the flag, on 7 cars. 7 releases on 6 cars kept
--   `deploy_gate_stuck`, and 1 of those 6 cars was later in a service bay. 1 release kept `deploy_gate_hard_cap`. Only
--   4 cars were escalated, and three were held to the teardown (0402 §4), so that release is Tesla-AV-061: G269's
--   false alarm left carrying the flag.

\echo '=== 0403 §8 — gate releases that kept the flag ==='
WITH rel AS (
  SELECT e.entity_id, e.event_seq, e.payload->'diff'->'config'->'to'->>'flagged_issue_type' AS flag_type
    FROM public.ottoq_events e
   WHERE e.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'from' ? 'deploy_gate'
     AND NOT (e.payload->'diff'->'config'->'to' ? 'deploy_gate')
     AND (e.payload->'diff'->'config'->'to'->>'flagged_issue')::boolean)
SELECT flag_type, count(*) AS releases_keeping_the_flag, count(DISTINCT entity_id) AS cars,
       count(DISTINCT entity_id) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_events e3
          WHERE e3.sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c' AND e3.entity_id = rel.entity_id
            AND e3.event_type = 'vehicle.state_changed' AND e3.event_seq > rel.event_seq
            AND e3.payload->'diff'->'current_state'->>'to' = 'in_service_bay')) AS later_in_service_bay
  FROM rel GROUP BY flag_type ORDER BY flag_type;
-- READ: pending.

-- ══ §9 LIVE PROBE: WHO STAMPS last_state_change WITHOUT A STATE CHANGE (G272) ══════════════════════════════════════════
--
--   0545 (a) and (c) read `vehicles.last_state_change` as the time a car last changed state. A car whose stamp is this
--   tick with no state change in the signed stream was re-stamped by a writer, and the stream cannot show it:
--   `ottoq_vehicles_state_change` drops a diff of clock keys alone (0015). Run while the run is live.

\echo '=== 0403 §9 — cars stamped this tick with no state change ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c' AND status = 'running')
SELECT v.current_state, v.config->>'svc_step' AS step, count(*) AS restamped_without_a_state_change,
       count(*) FILTER (WHERE v.current_soc < 80) AS below_80,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
               WHERE n.vehicle_id = v.id AND n.sim_run_id = r.sim_run_id AND a->>'svc' = 'charge'
                 AND COALESCE(a->>'status', 'open') <> 'done')) AS open_charge_atom,
       r.tick_count
  FROM public.vehicles v, r
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
   AND v.last_state_change = r.sim_clock_current
   AND NOT EXISTS (SELECT 1 FROM public.ottoq_events e WHERE e.sim_run_id = r.sim_run_id AND e.entity_id = v.id
                     AND e.event_type = 'vehicle.state_changed' AND e.sim_clock_at = r.sim_clock_current
                     AND e.payload->'diff' ? 'current_state')
 GROUP BY 1, 2, r.tick_count ORDER BY 3 DESC;
-- READ (2026-09-28 04:20 UTC, 11:20 PM CT; tick 95, sim 5:35 AM CT): **17 cars staged on need_charge were stamped this
--   tick with no state change, all 17 below 80% with an open charge atom**, plus 14 deployed cars (11 `ready`, 3 with no
--   step). The 17 are exactly STEP 0's set in `twin.ottoq_sim_advance_service_flow`, the stranded under-floor deadlock
--   breaker. Each tick it writes `staged_awaiting_service` / `need_charge` / `last_state_change = <this tick>` onto
--   every car below `deploy_floor_soc` with an open charge atom, even one already exactly there. The 14 deployed cars
--   are the deployed telemetry, which stamps with each SoC drain.
--   The first probe had shown the effect before the cause (tick 41, sim 5:08 AM): 24 cars on need_charge at 12-46%,
--   every one with a visit, read a wait of 0 minutes, beside boot cars at 78-96% with 18-21 minutes. So 0545 (c)'s
--   ratio is exactly 1 for every waiting visit car below 80%, and those cars fall back to lowest charge first among
--   themselves. The readiness gate is not affected: its six held cars at the probe read the same minutes from
--   `last_state_change` as from their hold stamp (22 and 22), because STEP 0 does not touch need_deploy cars at or
--   above the floor. G272. The fix is 0546, applied after this run.

-- ══ §10 G271 AGAIN: WHO THE CHARGERS WENT TO, BY WHETHER THE CAR HAD A VISIT ══════════════════════════════════════════
--
--   0545 (c) orders OTTO-Q's charge cursor by response ratio, but only after its first key: `(SELECT vn.urgency =
--   'immediate_dispatch' FROM ottoq_visit_needs vn ...) DESC NULLS LAST`. For a car with no open visit that subquery is
--   NULL, and NULLS LAST sorts it after every car with a visit, whatever it has waited. G271's cars were mostly boot
--   cars with no visit. Each charge session here is placed by when it started and whether its car had a visit.

\echo '=== 0403 §10 — charge sessions by start time and by whether the car had a visit ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '4acf0b1d-f32d-4a24-9f12-2d3049e7ab0c'),
s AS (
  SELECT o.vehicle_id, o.started_at, o.soc_start,
         (SELECT vn.urgency FROM public.ottoq_visit_needs vn
           WHERE vn.vehicle_id = o.vehicle_id AND vn.sim_run_id = r.sim_run_id AND vn.arrived_at <= o.started_at
           ORDER BY vn.created_at DESC LIMIT 1) AS urgency
    FROM public.ocpp_sessions o, r WHERE o.sim_run_id = r.sim_run_id)
SELECT CASE WHEN started_at < timestamptz '2026-09-27 10:00:00+00' THEN 'before 5:00 AM CT' ELSE 'from 5:00 AM CT' END AS started,
       COALESCE(urgency, 'no visit') AS car, count(*) AS sessions, min(soc_start) AS min_soc, max(soc_start) AS max_soc
  FROM s GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-28 04:27 UTC, 11:27 PM CT; tick 202, sim 6:30 AM CT): **from 5:00 AM, 35 sessions started, every one on
--   a car with a visit** (18 immediate dispatches at 16-56%, 17 standard visits at 26-69%). **None went to a car with no
--   visit**, while 14 boot cars at 78-96% waited on need_charge, one of them for 102 minutes. Before 5:00 AM, 20 no-visit
--   cars had charged (at 84-98%), when the boot left chargers free, beside 24 visit cars. The ratio can only order cars
--   inside the first key's groups, and a car with no visit is always in the last group. That is the rest of G271, and
--   0546 (c) makes a car with no visit read as not an immediate dispatch (false) instead of NULL.
