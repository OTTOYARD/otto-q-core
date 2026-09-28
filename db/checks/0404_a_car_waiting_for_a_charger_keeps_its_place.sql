-- 0404  **A car waiting for a charger keeps its place in line: the first operator run under 0546, beside 4acf0b1d.**
--
--       Written on 2026-09-28 (CT) for the validation run after 0546 (applied 20260928053318): (a) the service flow's
--       deadlock breaker stamps `last_state_change` only when it moves a car into staging, so a waiting car's stamp says
--       when it began to wait (G272); (b) the gate's release drops a flag the gate raised (G273); (c) the charge cursor
--       reads a car with no visit as not an immediate dispatch instead of NULL, so it is no longer sorted behind every car
--       with a visit (G271); (d) a car held on `need_charge` or `need_service` past the gate's hard cap is escalated to a
--       person once per wait (G274). Read-only.
--       The run is dbdffd5c-a878-43ce-8b64-578bd776c813. Cron 774 started it at 06:02:24 UTC (1:02 AM CT), once all nine canon columns had passed
--       under 0546 (verdicts 549-557, 12:34-1:02 AM CT, every one equal on all fourteen atoms). It is busy_day at 8x on
--       4acf0b1d's seed (and 9eab647f's), and it opens at the same sim minute, 4:41 AM CT.
--       **One difference from 0403's pairing: the sim day.** A busy run opens on the CT date it starts on. 9eab647f and
--       4acf0b1d started before midnight CT and ran Sunday 2026-09-27; this one started after midnight and runs Monday
--       2026-09-28. The random draws key on the seed, the entity and the minutes since the run's start, not on the date,
--       but the tariff, the building load and the grid read the day of the week (`twin.ottoq_sim_current_tariff`,
--       `ottoq_sim_compute_building_load_kw`, `ottoq_sim_advance_grid`), and the weather and a charger's heat stress
--       read the day of the year. So §1's comparison is looser than 0403's: its demand side is checked against
--       4acf0b1d's 358 demand car-hours before any difference is read as 0546's.
--
--       **4acf0b1d's side is §0, read before this run purged it** (`ottoq_purge_prior_runs`, class 'engine').

-- ══ §0 BEFORE: 4acf0b1d (0403's READs, and §7 and §11 measured before the purge) ══════════════════════════════════════
--
--   §1-§6 and §8-§10 are 0403's READs. §7's need_service rows, its car-hours and its 240-minute counts, and all of §11,
--   were measured on 4acf0b1d's rows with this file's queries on 2026-09-28 05:45-06:00 UTC (12:45-1:00 AM CT), before
--   this run purged them.
--     §1  the governor stopped the run at sim 1:50 PM CT: 550 sim-minutes, 1,090 ticks. KPI 1 asset hours 121.7 · KPI 2
--         turns per point 3.01 · KPI 3 peak site kW 1,037.8 (demand 1,012.5) · KPI 4 touches per turn 1.119 · KPI 5 p95
--         time to service 243.1 min (p50 45.2), 18 returns unserved. Charge wait (visits) p50 47.2, p95 290.6, max 447.9
--         min; 138 of 178 visits owing a charge charged, 40 still waiting. Supply gap 236.2 of 358 demand car-hours unmet
--         (66%), 121.7 deployed, peak shortfall 43. Archive: 120 dispatches, 166 charge sessions, 487 tasks completed.
--     §2  116 departures, 0 below 99%, 0 with a service open.
--     §3  0 door refusals, 0 tick failures, 0 floor rejections.
--     §4  1 escalation, a real one: Tesla-AV-050, held 240 minutes at 100% for a deep clean, 0 state changes inside the
--         counted hold. No car waiting for a charger or the service bay could be escalated (G274).
--     §5  31 needs-card seats: 16 to cars due out later, 6 with no deploy time, 7 late. 77 cars held at the gate, mean
--         longest hold 16 min, longest 286.1, 1 at the cap.
--     §6  42 recheck events. The gate held at most 32 cars at once. Staging overflow peaked at 54. Bay entries: 28 wash,
--         23 detail, 21 service.
--     §7  need_charge, by how each wait ended:
--           to a charger: 24 below 90% (p50 23.7, p95 138.2, max 279.6 min), 34 top-offs at 90-98% (p50 1.5, max 43.7),
--             2 with no SoC in the stream;
--           to the service bay: 2; back to the gate: 34, all at 100%, each under 2 min;
--           still waiting at the teardown: 40, 38 of them below 90% (12-83%) and 2 top-offs (91, 96%). By visit, 14 boot
--             cars with no visit (78-96%) and 26 standard visits (12-49%). **297.3 car-hours between them**, and 32 had
--             waited past 240 minutes. One more wait reached 240 minutes and then a charger (279.6).
--         need_service: 94 waits. 16 reached the service bay (p50 14.3, max 74.6 min), 3 were still waiting at the
--           teardown (38.7-108.6 min), and the rest went back to the gate or to a wash or detail bay within 11 minutes.
--           None reached 240 minutes.
--     §8  5 releases kept `deploy_gate_stuck`, on 4 cars; 1 of them was later in a service bay.
--     §9  at tick 95 (sim 5:35 AM CT): 17 cars staged on need_charge stamped that tick with no state change, all 17
--         below 80% with an open charge atom (STEP 0's set, G272), and 14 deployed cars (the deployed telemetry).
--     §10 from 5:00 AM, 122 charge sessions started and **0 went to a car with no visit** (51 immediate dispatches, 69
--         standard visits, 2 technician holds). Before 5:00 AM, 20 no-visit cars had charged at 84-98%.
--     §11 **The depot was charger-bound, and the fast chargers' free time was faults.** From 5 AM to 1 PM, 32.7-38.0
--         cars waited on need_charge on average in each hour, beside 1.4-4.9 fast chargers and 0.3-2.1 L2 chargers free
--         by the stall pointer. The 10 fast chargers ran 54 sessions for 59.8 of their 91.6 stall-hours (65.3%); the 30
--         L2 chargers ran 112 sessions for 260.9 of 274.8 (95.0%). **Seven of the ten fast chargers faulted**, with the
--         calibrated repair times of the ChargerHelp fault mix: DCFC-08 330 min from 4:51 AM, -09 152 from 4:54, -05 371
--         from 5:27, -07 1,077 from 7:48 (out for the rest of the day), -03 153 from 8:56, -01 178 from 9:08 and -06 90
--         from 10:37. That is about 27 of the fast chargers' 31.4 free stall-hours. **Each one took its next car within
--         0.6-2.2 minutes of its repair ending**, so the free time was not a gap in the schedule. Three L2 chargers
--         faulted (L2-07 10 min, L2-15 37, L2-05 516 from 8:08 AM).
--         What that means under rule 9: the waiting cars are a capacity finding. The answers are fewer faults, faster
--         repair, more chargers and the order in which the waiting cars are served, never a shorter charge.

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0404 §1 — the run and its scorecard ==='
SELECT r.sim_run_id, r.run_by, r.status, r.random_seed, r.sim_clock_start, r.sim_clock_current, r.tick_count,
       r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813';
SELECT public.ottoq_kpi_five('dbdffd5c-a878-43ce-8b64-578bd776c813');
SELECT public.ottoq_kpi_charge_wait('dbdffd5c-a878-43ce-8b64-578bd776c813');
SELECT public.ottoq_kpi_supply_gap('dbdffd5c-a878-43ce-8b64-578bd776c813') - 'by_hour_ct';

-- ══ §2 RULE 9 STILL HOLDS: NO DEPARTURE WITH A SERVICE OPEN OR A CHARGE SHORT ═════════════════════════════════════════
--
--   0402 §2's query. Both must be 0.

\echo '=== 0404 §2 — departures, and any that left unfinished ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813'),
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
-- READ mid-run (2026-09-28 06:39 UTC, 1:39 AM CT; sim 9:29 AM CT): **75 departures, 0 below 99% (the lowest was 99), 0
--   with a service open.** 4acf0b1d's mid-run probe had 61 departures by 9:08 AM.

-- ══ §3 THE DOOR AND THE FLOOR (0544): NEITHER SHOULD EVER FIRE ════════════════════════════════════════════════════════

\echo '=== 0404 §3 — door refusals and floor rejections ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.dispatch_refused_unfinished') AS door_refusals,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed') AS tick_failures,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed' AND e.payload::text LIKE '%0544 (CLAUDE.md rule 9)%') AS floor_rejections
  FROM public.ottoq_events e WHERE e.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813';
-- READ mid-run (06:39 UTC): 0 door refusals, 0 tick failures, 0 floor rejections.

-- ══ §4 ESCALATIONS: THE GATE'S (G269) AND THE WAITS FOR A CHARGER OR THE SERVICE BAY (0546 (d), G274) ══════════════════
--
--   Every escalation, with its reason. A gate escalation (`must_do_work_open`) is a car held for bay work or its
--   check; 0545 (a) times it from the car's last state change, so no state change should fall inside its counted
--   hold. A remedy-wait escalation (0546 (d), `waiting_for_a_charger` or `waiting_for_the_service_bay`) is a car on
--   need_charge or need_service whose last state change is 240 minutes old; (a) makes that the start of its wait, so
--   again no state change should fall inside it. The `remedy_wait` stamp holds the run and the start of the wait, so a
--   car is escalated once per wait: `per_car_and_start` must be 1 everywhere.

\echo '=== 0404 §4 — escalations, by reason, and whether the car changed state inside the counted wait ==='
SELECT v.display_name, e.sim_clock_at AT TIME ZONE 'America/Chicago' AS escalated_ct,
       e.payload->>'reason' AS reason,
       (e.payload->>'held_min')::numeric AS held_min, e.payload->>'soc' AS soc, e.payload->'missing' AS missing,
       (SELECT count(*) FROM public.ottoq_events s
         WHERE s.sim_run_id = e.sim_run_id AND s.entity_id = e.entity_id AND s.event_type = 'vehicle.state_changed'
           AND s.payload->'diff' ? 'current_state'
           AND s.sim_clock_at > e.sim_clock_at - make_interval(secs => (e.payload->>'held_min')::numeric * 60)
           AND s.sim_clock_at < e.sim_clock_at) AS state_changes_inside_the_wait,
       count(*) OVER (PARTITION BY e.entity_id,
                      date_trunc('minute', e.sim_clock_at - make_interval(secs => (e.payload->>'held_min')::numeric * 60))) AS per_car_and_start
  FROM public.ottoq_events e LEFT JOIN public.vehicles v ON v.id = e.entity_id
 WHERE e.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND e.event_type = 'twin.deploy_gate_escalated'
 ORDER BY e.sim_clock_at;
-- READ mid-run (06:38 UTC, 1:38 AM CT; sim 9:27 AM CT): **10 escalations, every one `waiting_for_a_charger`, all at
--   8:54 AM, each at 240.1 minutes, 0 state changes inside the wait, `per_car_and_start` 1 for all ten.** 0546 (d) fired
--   once per wait, as designed. All ten are standard visits at 12-30% (missing the charge and cabin work) that joined
--   need_charge together at 4:54 AM: the boot's low cars. An immediate dispatch goes first on the cursor's first key,
--   and a low car's ratio climbs slowest (one point per minute over 70-88 points to charge), so under a saturated
--   charger bank these are the cars left waiting. That is the order working as written, and the escalation is what a
--   person is for (§7b).

-- ══ §5 G270: WHO GOT THE BAY SEATS ═══════════════════════════════════════════════════════════════════════════════════

\echo '=== 0404 §5 — needs-card seats by the seated car''s deploy time, and the gate''s holds ==='
SELECT d.enacted_action->>'purpose' AS purpose,
       CASE WHEN d.context_frame->>'minutes_to_deploy' IS NULL THEN 'no deploy time'
            WHEN (d.context_frame->>'minutes_to_deploy')::int < 0 THEN 'late'
            ELSE 'due later' END AS seated_car,
       count(*) AS seats,
       min((d.context_frame->>'minutes_to_deploy')::int) AS min_mtd, max((d.context_frame->>'minutes_to_deploy')::int) AS max_mtd
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND d.enacted_action->>'source' = 'needs_card' AND d.outcome_status = 'enacted'
 GROUP BY 1, 2 ORDER BY 1, 2;
WITH holds AS (
  SELECT e.entity_id, max((e.payload->'diff'->'config'->'to'->'deploy_gate'->>'held_min')::numeric) AS held
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate' ? 'held_min'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate'->>'run' = e.sim_run_id::text   -- not a prior run's stamp
   GROUP BY 1)
SELECT count(*) AS cars_held, round(avg(held)) AS mean_max_hold_min, max(held) AS longest_hold_min,
       count(*) FILTER (WHERE held >= 240) AS reached_the_cap
  FROM holds;

-- ══ §6 WHAT HOLDING COSTS ═════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0404 §6 — the gate, staging and the bays ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS recheck_events,
       count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_escalated') AS escalated_to_a_person,
       max((e.payload->>'held')::int) FILTER (WHERE e.event_type = 'twin.deploy_gate_summary') AS gate_held_max,
       max((e.payload->>'overflow')::int) FILTER (WHERE e.event_type = 'twin.staging_overflow') AS staging_overflow_max
  FROM public.ottoq_events e WHERE e.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813';
SELECT (SELECT jsonb_object_agg(to_state, k) FROM (
          SELECT e.payload->'diff'->'current_state'->>'to' AS to_state, count(*) AS k
            FROM public.ottoq_events e WHERE e.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
           GROUP BY 1) q) AS bay_entries;

-- ══ §7 G271: NO CAR STARVES WAITING FOR A CHARGER OR THE SERVICE BAY ═════════════════════════════════════════════════
--
--   0403 §7's waits, widened to need_service, with the car-hours and the waits that reached 240 minutes. A wait starts
--   where a staged car's step becomes need_charge (or need_service) and ends at its next change of state or step. The
--   teardown's `offline` at the run's last sim minute is not an end. The SoC at the start is the stream's last SoC for
--   the car at or before it. `visit` is the urgency of the car's latest visit at the wait's start, or 'no visit'.
--   Under 0546 (a) and (c) no group should be passed over all day: a boot car with no visit now competes on its ratio,
--   and a waiting car's ratio rises with its wait.

\echo '=== 0404 §7 — waits on need_charge and need_service, by SoC at the start and by how each ended ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813'),
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
  SELECT s.vehicle_id, s.at AS began, s.seq, s.step_to AS step,
         (SELECT s0.soc_to FROM st s0 WHERE s0.vehicle_id = s.vehicle_id AND s0.soc_to IS NOT NULL AND s0.seq <= s.seq
           ORDER BY s0.seq DESC LIMIT 1) AS soc_at_start
    FROM st s WHERE s.has_cfg AND s.step_to IN ('need_charge', 'need_service') AND COALESCE(s.step_from, '') <> s.step_to),
ends AS (
  SELECT b.*, x.at AS ended, x.to_state, x.step_to
    FROM starts b LEFT JOIN LATERAL (
      SELECT s2.* FROM st s2, run WHERE s2.vehicle_id = b.vehicle_id AND s2.seq > b.seq
         AND NOT (s2.to_state = 'offline' AND s2.at >= run.t1)
         AND ((s2.has_state AND s2.to_state <> 'staged_awaiting_service')
           OR (s2.has_cfg AND COALESCE(s2.step_to, '') <> b.step))
       ORDER BY s2.seq LIMIT 1) x ON true),
w AS (
  SELECT e.*, extract(epoch FROM (COALESCE(e.ended, run.t1) - e.began)) / 60.0 AS wait_min,
         CASE WHEN e.ended IS NULL THEN 'still waiting at the end'
              WHEN e.to_state IN ('charging_l2', 'charging_dcfc') THEN 'to a charger'
              WHEN e.to_state = 'in_service_bay' THEN 'to the service bay'
              WHEN e.step_to = 'need_deploy' THEN 'back to the gate'
              ELSE COALESCE(e.to_state, e.step_to, 'other') END AS how,
         CASE WHEN e.soc_at_start >= 90 THEN 'top-off (>=90%)' WHEN e.soc_at_start IS NULL THEN 'unknown' ELSE 'below 90%' END AS band
    FROM ends e, run)
SELECT step, band, how, count(*) AS waits, count(DISTINCT vehicle_id) AS cars,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY wait_min)::numeric, 1) AS p50_min,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY wait_min)::numeric, 1) AS p95_min,
       round(max(wait_min)::numeric, 1) AS max_min, min(soc_at_start) AS min_soc, max(soc_at_start) AS max_soc,
       round(sum(wait_min)::numeric / 60, 1) AS car_hours,
       count(*) FILTER (WHERE wait_min >= 240) AS reached_240
  FROM w GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

--   The same waits still open at the teardown, by whether the car had a visit (0546 (c)), and whether each wait that
--   reached 240 minutes was escalated once in its stay (0546 (d)). A stay is the car's time in staged_awaiting_service
--   since its last state change, which is what (d) times; one stay can hold more than one wait.

\echo '=== 0404 §7b — the waits still open at the end by visit, and the 240-minute waits against their escalations ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813'),
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
  SELECT s.vehicle_id, s.at AS began, s.seq, s.step_to AS step,
         (SELECT s0.soc_to FROM st s0 WHERE s0.vehicle_id = s.vehicle_id AND s0.soc_to IS NOT NULL AND s0.seq <= s.seq
           ORDER BY s0.seq DESC LIMIT 1) AS soc_at_start,
         (SELECT max(s1.at) FROM st s1 WHERE s1.vehicle_id = s.vehicle_id AND s1.has_state AND s1.seq <= s.seq) AS stay_began
    FROM st s WHERE s.has_cfg AND s.step_to IN ('need_charge', 'need_service') AND COALESCE(s.step_from, '') <> s.step_to),
ends AS (
  SELECT b.*, x.at AS ended
    FROM starts b LEFT JOIN LATERAL (
      SELECT s2.* FROM st s2, run WHERE s2.vehicle_id = b.vehicle_id AND s2.seq > b.seq
         AND NOT (s2.to_state = 'offline' AND s2.at >= run.t1)
         AND ((s2.has_state AND s2.to_state <> 'staged_awaiting_service')
           OR (s2.has_cfg AND COALESCE(s2.step_to, '') <> b.step))
       ORDER BY s2.seq LIMIT 1) x ON true),
w AS (
  SELECT e.*, extract(epoch FROM (COALESCE(e.ended, run.t1) - e.began)) / 60.0 AS wait_min,
         COALESCE((SELECT vn.urgency FROM public.ottoq_visit_needs vn
                    WHERE vn.vehicle_id = e.vehicle_id AND vn.sim_run_id = run.id AND vn.arrived_at <= e.began
                    ORDER BY vn.created_at DESC LIMIT 1), 'no visit') AS visit,
         (SELECT count(*) FROM public.ottoq_events x
           WHERE x.sim_run_id = run.id AND x.entity_id = e.vehicle_id AND x.event_type = 'twin.deploy_gate_escalated'
             AND x.payload->>'reason' IN ('waiting_for_a_charger', 'waiting_for_the_service_bay')
             AND x.sim_clock_at >= COALESCE(e.stay_began, e.began) AND x.sim_clock_at <= COALESCE(e.ended, run.t1)) AS escalations_in_stay
    FROM ends e, run)
SELECT step, CASE WHEN ended IS NULL THEN 'still waiting at the end' ELSE 'ended' END AS state, visit,
       wait_min >= 240 AS reached_240, escalations_in_stay, count(*) AS waits,
       min(soc_at_start) AS min_soc, max(soc_at_start) AS max_soc, round(max(wait_min)::numeric, 1) AS max_min
  FROM w
 WHERE ended IS NULL OR wait_min >= 240 OR escalations_in_stay > 0
 GROUP BY 1, 2, 3, 4, 5 ORDER BY 1, 2, 3, 4, 5;

-- ══ §8 G273: NO RELEASE KEEPS A FLAG THE GATE RAISED ═══════════════════════════════════════════════════════════════════
--
--   0403 §8's query. Under 0546 (b) a release drops `deploy_gate_stuck` and `deploy_gate_hard_cap` with its stamp, so
--   those two rows must read 0. A flag raised by anything else is kept, as before, and may appear.

\echo '=== 0404 §8 — gate releases that kept a flag ==='
WITH rel AS (
  SELECT e.entity_id, e.event_seq, e.payload->'diff'->'config'->'to'->>'flagged_issue_type' AS flag_type
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'from' ? 'deploy_gate'
     AND NOT (e.payload->'diff'->'config'->'to' ? 'deploy_gate')
     AND (e.payload->'diff'->'config'->'to'->>'flagged_issue')::boolean)
SELECT flag_type, count(*) AS releases_keeping_the_flag, count(DISTINCT entity_id) AS cars,
       count(DISTINCT entity_id) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_events e3
          WHERE e3.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND e3.entity_id = rel.entity_id
            AND e3.event_type = 'vehicle.state_changed' AND e3.event_seq > rel.event_seq
            AND e3.payload->'diff'->'current_state'->>'to' = 'in_service_bay')) AS later_in_service_bay
  FROM rel GROUP BY flag_type ORDER BY flag_type;

-- ══ §9 LIVE PROBE: NO STAGED CAR IS RE-STAMPED WITHOUT A STATE CHANGE (G272) ═══════════════════════════════════════════
--
--   0403 §9's probe. Under 0546 (a), STEP 0 stamps only a car it moves into staging, which is a state change, so no
--   staged car should appear. The deployed telemetry still stamps deployed cars with each SoC drain (0546 §4: measured,
--   not changed), so deployed rows are expected. Run while the run is live.

\echo '=== 0404 §9 — cars stamped this tick with no state change ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND status = 'running')
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
-- READ (2026-09-28 06:05 UTC, 1:05 AM CT; tick 21, sim 5:01 AM CT): **no staged car was stamped that tick without a
--   state change.** 2 deployed cars and 1 car en route to the depot were (the deployed telemetry, 0546 §4). On 4acf0b1d
--   at tick 95, 17 staged cars on need_charge were (G272).
--   Mid-run (06:38 UTC, 1:38 AM CT; tick 537, sim 9:27 AM CT): still no staged car; 7 deployed cars (the telemetry).

--   §9b, the same moment from the queue's side: every car on need_charge with the wait the charge cursor reads (sim now
--   minus `last_state_change`), by whether it has a visit and by its charge.

\echo '=== 0404 §9b — the charge queue and the wait each car reads ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813')
SELECT CASE WHEN EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn WHERE vn.vehicle_id = v.id AND vn.sim_run_id = r.sim_run_id)
            THEN 'visit' ELSE 'no visit' END AS car,
       CASE WHEN v.current_soc >= 90 THEN 'top-off (>=90%)' WHEN v.current_soc >= 80 THEN '80-89%' ELSE 'below 80%' END AS band,
       count(*) AS cars, min(v.current_soc) AS min_soc, max(v.current_soc) AS max_soc,
       round(min(extract(epoch FROM (r.sim_clock_current - v.last_state_change)) / 60)::numeric, 1) AS min_wait_min,
       round(max(extract(epoch FROM (r.sim_clock_current - v.last_state_change)) / 60)::numeric, 1) AS max_wait_min,
       count(*) FILTER (WHERE v.last_state_change = r.sim_clock_current) AS wait_zero,
       r.tick_count, r.sim_clock_current AT TIME ZONE 'America/Chicago' AS sim_ct
  FROM public.vehicles v, r
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
   AND v.current_state = 'staged_awaiting_service' AND v.config->>'svc_step' = 'need_charge'
 GROUP BY 1, 2, r.tick_count, r.sim_clock_current ORDER BY 1, 2;
-- READ (06:05 UTC, 1:05 AM CT; tick 25, sim 5:03 AM CT): 39 cars on need_charge, **none reading a wait of 0.** The 24
--   visit cars below 80% (12-46%) read 8.7 minutes, where on 4acf0b1d at tick 41 the same group read 0 (0403 §9). 11
--   visit top-offs at 90-98% and 2 visit cars at 88-89% read 10.0; the 2 no-visit boot cars at 91-96% read 7.6-11.8.
--   Mid-run (06:38 UTC; tick 539, sim 9:28 AM CT): **14 cars on need_charge, every one a visit car below 80% (12-69%),
--   none reading 0**, waits 25.3-274.0 minutes. No top-off and no car without a visit was waiting. At 9:08 AM on
--   4acf0b1d, 14 no-visit cars had waited about 260 minutes and the 19 cars below 50% read 0.

-- ══ §10 G271: WHO THE CHARGERS WENT TO, BY WHETHER THE CAR HAD A VISIT ══════════════════════════════════════════════════
--
--   0403 §10's query. On 4acf0b1d no car without a visit got a charger after 5:00 AM. Under 0546 (c) they compete on
--   their ratio, and a top-off's ratio is high, so they should appear from 5:00 AM on.

\echo '=== 0404 §10 — charge sessions by start time and by whether the car had a visit ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813'),
s AS (
  SELECT o.vehicle_id, o.started_at, o.soc_start,
         (SELECT vn.urgency FROM public.ottoq_visit_needs vn
           WHERE vn.vehicle_id = o.vehicle_id AND vn.sim_run_id = r.sim_run_id AND vn.arrived_at <= o.started_at
           ORDER BY vn.created_at DESC LIMIT 1) AS urgency
    FROM public.ocpp_sessions o, r WHERE o.sim_run_id = r.sim_run_id)
SELECT CASE WHEN started_at < timestamptz '2026-09-28 10:00:00+00' THEN 'before 5:00 AM CT' ELSE 'from 5:00 AM CT' END AS started,
       COALESCE(urgency, 'no visit') AS car, count(*) AS sessions, min(soc_start) AS min_soc, max(soc_start) AS max_soc
  FROM s GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-28 06:06 UTC, 1:06 AM CT; tick 46, sim 5:12 AM CT): before 5:00 AM, **32 sessions went to boot cars with
--   no visit** (at 78-98%) and 8 to immediate dispatches (82-97%); from 5:00 AM, 7 more immediate dispatches (29-97%). On
--   4acf0b1d, 20 no-visit cars had charged before 5:00 AM and none after. The top-offs now go first on their ratio, which
--   is what the ratio is for (a short job's ratio climbs fastest); the standard visits at 12-46% had not yet had a
--   charger. Whether they wait too long is what §7 and the mid-run read answer.
--   Mid-run (06:40 UTC, 1:40 AM CT; sim ~9:30 AM CT): from 5:00 AM, **87 sessions: 45 immediate dispatches (16-97%),
--   39 standard visits (27-98%), 3 cars with no visit (89-96%).** On 4acf0b1d by 9:08 AM, 61 from 5:00 AM and none on a
--   car with no visit.

-- ══ §11 THE CHARGERS: HOW BUSY, HOW MANY FAULTED, AND WHAT WAS FREE WHILE CARS WAITED ═══════════════════════════════════
--
--   Session hours against nameplate time by charger kind; every fault with its repair time and how long its charger
--   stood before its next car; and, per hour, the cars waiting on need_charge beside the chargers free by the stall
--   pointer. A charger free while cars wait is either faulted (capacity lost to faults), between two cars (turnover),
--   or a gap in the schedule, which is the only one of the three that orchestration alone can close.

\echo '=== 0404 §11 — charger use by kind ==='
WITH r AS (SELECT sim_run_id, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813'),
k AS (SELECT s.stall_type::text AS kind, count(*) AS stalls FROM public.stalls s
       WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text IN ('dcfc', 'l2') GROUP BY 1),
x AS (
  SELECT st.stall_type::text AS kind,
         extract(epoch FROM (LEAST(COALESCE(o.ended_at, r.t1), r.t1) - GREATEST(o.started_at, r.t0))) / 60.0 AS mins
    FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id, r
   WHERE o.sim_run_id = r.sim_run_id)
SELECT x.kind, k.stalls, count(*) AS sessions, round(sum(mins)::numeric / 60, 1) AS session_hours,
       round((sum(mins) / (k.stalls * extract(epoch FROM (r.t1 - r.t0)) / 60.0) * 100)::numeric, 1) AS pct_of_nameplate_time
  FROM x JOIN k USING (kind), r GROUP BY x.kind, k.stalls, r.t0, r.t1 ORDER BY 1;

\echo '=== 0404 §11b — every charger fault, its repair time, and how long its charger stood before its next car ==='
WITH f AS (
  SELECT e.sim_clock_at AS at, o.stall_id, e.payload->>'reason' AS reason, (e.payload->>'repair_minutes')::numeric AS repair_min
    FROM public.ottoq_events e JOIN public.ocpp_sessions o ON o.id::text = e.entity_id::text
   WHERE e.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND e.event_type = 'charge.session_faulted')
SELECT s.stall_code, f.at AT TIME ZONE 'America/Chicago' AS fault_ct, f.reason, f.repair_min,
       round(extract(epoch FROM ((SELECT min(o2.started_at) FROM public.ocpp_sessions o2
                                   WHERE o2.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND o2.stall_id = f.stall_id AND o2.started_at > f.at)
                                 - f.at))::numeric / 60, 1) AS stood_until_next_car_min
  FROM f JOIN public.stalls s ON s.id = f.stall_id ORDER BY f.at;
-- READ mid-run (06:42 UTC; through sim ~9:30 AM CT): DCFC-08 437 min from 4:54 AM (out through the probe), DCFC-03 three
--   times (81 min from 5:47, 12 from 8:29, 26 from 9:02); L2-30 47 min, L2-19 36, L2-32 25, L2-28 151. Two fast chargers
--   faulted by 9:30 AM, against five on 4acf0b1d by then: the fault draws read the day (§ header), so this is a different
--   world on the fault side. DCFC-03's second repair ended 9.5 minutes before its next car, the one gap not explained.

\echo '=== 0404 §11c — per hour: cars waiting on need_charge, and chargers free by the stall pointer ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813'),
st AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'current_state'->>'to' AS to_state,
         e.payload->'diff'->'config'->'to'->>'svc_step' AS step_to,
         e.payload->'diff'->'config'->'from'->>'svc_step' AS step_from,
         e.payload->'diff' ? 'config' AS has_cfg, e.payload->'diff' ? 'current_state' AS has_state
    FROM public.ottoq_events e, run WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND (e.payload->'diff' ? 'config' OR e.payload->'diff' ? 'current_state')),
starts AS MATERIALIZED (SELECT s.vehicle_id, s.at AS began, s.seq FROM st s
                         WHERE s.has_cfg AND s.step_to = 'need_charge' AND COALESCE(s.step_from, '') <> 'need_charge'),
waits AS MATERIALIZED (
  SELECT b.vehicle_id, b.began, COALESCE(x.at, run.t1) AS ended
    FROM starts b CROSS JOIN run LEFT JOIN LATERAL (
      SELECT s2.at FROM st s2 WHERE s2.vehicle_id = b.vehicle_id AND s2.seq > b.seq
         AND NOT (s2.to_state = 'offline' AND s2.at >= run.t1)
         AND ((s2.has_state AND s2.to_state <> 'staged_awaiting_service') OR (s2.has_cfg AND COALESCE(s2.step_to, '') <> 'need_charge'))
       ORDER BY s2.seq LIMIT 1) x ON true),
ch AS MATERIALIZED (SELECT id, stall_type::text AS kind FROM public.stalls
                     WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type::text IN ('dcfc', 'l2')),
sev AS MATERIALIZED (
  SELECT e.entity_id AS stall_id, ch.kind, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'status'->>'from' AS st_from, e.payload->'diff'->'status'->>'to' AS st_to
    FROM public.ottoq_events e JOIN ch ON ch.id = e.entity_id, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'stall.state_changed' AND e.payload->'diff' ? 'status'),
seg AS MATERIALIZED (
  SELECT stall_id, kind, st_to AS status, at AS a, COALESCE(lead(at) OVER w, (SELECT t1 FROM run)) AS b
    FROM sev WINDOW w AS (PARTITION BY stall_id ORDER BY seq)
  UNION ALL
  (SELECT DISTINCT ON (stall_id) stall_id, kind, st_from, (SELECT t0 FROM run), at FROM sev ORDER BY stall_id, seq)),
t AS MATERIALIZED (SELECT generate_series(run.t0 + interval '1 minute', run.t1 - interval '1 minute', interval '2 minutes') AS at FROM run),
g AS (
  SELECT t.at,
         (SELECT count(*) FROM waits w WHERE w.began <= t.at AND w.ended > t.at) AS cars_waiting,
         (SELECT count(*) FROM seg WHERE seg.kind = 'dcfc' AND seg.status = 'available' AND seg.a <= t.at AND seg.b > t.at) AS dcfc_free,
         (SELECT count(*) FROM seg WHERE seg.kind = 'l2' AND seg.status = 'available' AND seg.a <= t.at AND seg.b > t.at) AS l2_free
    FROM t)
SELECT to_char(date_trunc('hour', at AT TIME ZONE 'America/Chicago'), 'HH12 AM') AS hour_ct,
       round(avg(cars_waiting), 1) AS avg_cars_waiting, round(avg(dcfc_free), 1) AS avg_dcfc_free, round(avg(l2_free), 1) AS avg_l2_free,
       sum(dcfc_free) FILTER (WHERE cars_waiting > 0) * 2 AS dcfc_free_min_while_waiting,
       sum(l2_free) FILTER (WHERE cars_waiting > 0) * 2 AS l2_free_min_while_waiting
  FROM g GROUP BY date_trunc('hour', at AT TIME ZONE 'America/Chicago') ORDER BY date_trunc('hour', at AT TIME ZONE 'America/Chicago');
-- READ mid-run (06:41 UTC, 1:41 AM CT; through sim ~9:30 AM CT): cars waiting on need_charge on average in each hour,
--   this run against 4acf0b1d: 4 AM 16.3 / 23.7 · 5 AM 35.8 / 34.4 · 6 AM 17.6 / 32.7 · 7 AM 12.4 / 33.5 · 8 AM 12.3 /
--   34.3 · 9 AM 13.9 / 34.7. **From 6 AM the queue is about 60% shorter.** Fewer fast-charger faults (§11b) account for
--   some of it; the rest is the order: the top-offs and the no-visit cars now clear in minutes.
--   Fast chargers free by the pointer while cars waited, per hour: 26, 130, 156, 88, 104, 98 stall-minutes. DCFC-08's
--   fault is most of it; §12 is another part.

-- ══ §12 G276: A FAST CHARGER KEEPS ITS CAR'S POINTER AFTER THE CAR LEAVES FOR A BAY ═══════════════════════════════════
--
--   Found at the mid-run probe. At sim 9:41 AM DCFC-04 read `status = 'available'` with `current_vehicle_id` still set
--   to Zoox-AV-078, which was in the service bay. `ottoq_decide_tick` offers a charger only when `current_vehicle_id IS
--   NULL`, so the fast charger could not be given to any of the 14 cars waiting.
--   The signed stream shows the order (sim 9:40:53-9:41:15): the charge completes; the car goes to
--   charge_complete_holding, then staged_awaiting_service (need_service), then `in_service_bay`; then its
--   `current_stall_id` and its tether are emptied; then DCFC-04's update lands with only `status` changed. The update
--   that empties the stall is refused by `public.ottoq_trg_reassignment_guard` (BEFORE UPDATE ON stalls): when a stall's
--   pointer is emptied, it reads the car's state, and for a car in a bay or charging it asks
--   `ottoq_indepot_reassignment_guard(..., 'automated_reassignment', ...)`, which declines and restores
--   `NEW.current_vehicle_id := OLD.current_vehicle_id`. It reads the car's state and never where the car is, so a car
--   that has already left this stall for a bay reads as work in progress here. The rest of the update (status) goes
--   through, which is why the stream shows the status moving alone: the pointer was put back inside the BEFORE trigger.
--   This is the mechanism behind G121's three `dcfc` stalls held by nobody.

\echo '=== 0404 §12a — charger time stuck with a pointer to a car that left, from the stall stream ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813'),
ch AS MATERIALIZED (SELECT id, stall_type::text AS kind FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111'),
ev AS MATERIALIZED (
  SELECT e.entity_id AS stall_id, e.sim_clock_at AS at, e.event_seq AS seq, e.payload->'diff' AS d
    FROM public.ottoq_events e, run WHERE e.sim_run_id = run.id AND e.event_type = 'stall.state_changed'
     AND e.entity_id IN (SELECT id FROM ch) AND (e.payload->'diff' ? 'status' OR e.payload->'diff' ? 'current_vehicle_id')),
st AS (
  SELECT stall_id, at, seq,
         (array_remove(array_agg(d->'status'->>'to') OVER w, NULL))[array_length(array_remove(array_agg(d->'status'->>'to') OVER w, NULL), 1)] AS status,
         (array_remove(array_agg(CASE WHEN d ? 'current_vehicle_id' THEN COALESCE(d->'current_vehicle_id'->>'to', 'NULL') END) OVER w, NULL))[array_length(array_remove(array_agg(CASE WHEN d ? 'current_vehicle_id' THEN COALESCE(d->'current_vehicle_id'->>'to', 'NULL') END) OVER w, NULL), 1)] AS ptr
    FROM ev WINDOW w AS (PARTITION BY stall_id ORDER BY seq ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)),
seg AS (SELECT st.*, COALESCE(lead(at) OVER (PARTITION BY stall_id ORDER BY seq), (SELECT t1 FROM run)) AS until FROM st)
SELECT ch.kind, count(*) AS episodes, count(DISTINCT seg.stall_id) AS stalls,
       round(sum(extract(epoch FROM (seg.until - seg.at)) / 60)::numeric, 1) AS stuck_minutes,
       round(max(extract(epoch FROM (seg.until - seg.at)) / 60)::numeric, 1) AS longest_min
  FROM seg JOIN ch ON ch.id = seg.stall_id
 WHERE seg.status = 'available' AND seg.ptr IS NOT NULL AND seg.ptr <> 'NULL'
 GROUP BY ch.kind ORDER BY 1;
-- READ mid-run (06:47 UTC, 1:47 AM CT; through sim 9:47 AM CT): **8 episodes on 7 of the 10 fast chargers, 132.5
--   fast-charger minutes, the longest 45.7**, DCFC-04's still open. None on L2 or on a bay.

\echo '=== 0404 §12b — the guard''s refusals, by where the car was when it asked ==='
WITH a AS (
  SELECT a.vehicle_id, (a.payload->>'from_stall')::uuid AS from_stall, (a.payload->>'requested_at_sim')::timestamptz AS at_sim,
         a.payload->>'state' AS state, s.stall_type::text AS from_kind, a.status
    FROM public.ottoq_ops_approvals a JOIN public.stalls s ON s.id = (a.payload->>'from_stall')::uuid
   WHERE a.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND a.payload->>'reason' = 'automated_reassignment'),
pos AS (
  SELECT a.*,
         (SELECT e.payload->'diff'->'current_stall_id'->>'to' FROM public.ottoq_events e
           WHERE e.sim_run_id = 'dbdffd5c-a878-43ce-8b64-578bd776c813' AND e.entity_id = a.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_stall_id' AND e.sim_clock_at <= a.at_sim
           ORDER BY e.event_seq DESC LIMIT 1) AS car_stall_at_request
    FROM a)
SELECT from_kind, state, status,
       CASE WHEN car_stall_at_request IS NULL THEN 'car on no stall' WHEN car_stall_at_request = from_stall::text THEN 'car on this stall'
            ELSE 'car on another stall' END AS car_position,
       count(*) AS n
  FROM pos GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
-- READ mid-run (06:49 UTC): the two populations separate exactly. **Every refusal with the car on this stall is the
--   guard doing its job**: 57 on L2 (53 declined, 1 approved, 3 pending) and 3 on fast chargers, all with the car
--   charging there. **Every refusal with the car on no stall is G276**: 19 on fast chargers, the car already in a
--   service bay (9), wash bay (7) or detail bay (3). So the fix is to judge a stall by whether the car is on it
--   (`current_stall_id` or its tether), as `ottoq_release_vacated_spaces` already does, not by the car's state alone.
