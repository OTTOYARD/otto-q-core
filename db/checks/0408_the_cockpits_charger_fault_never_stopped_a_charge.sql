-- 0408  **A fast-charger outage on the fresh-seed day, and the cockpit's fault door that never stopped a charge (G281).**
--
--       Written on 2026-09-28 (CT). Read-only. The run is ca448d95-6526-40b6-b36e-a5e02273fff3: busy_day at 8x under 0549,
--       on 0405bf42's seed (1092115219118377967), sim day and start minute (Monday 2026-09-28, 4:26 AM CT). I started it at
--       14:58:59 UTC (9:58 AM CT), with no certification in flight and the canon at 9 of 9. It is the research wing's stress
--       test, in the twin (rule 10). Nothing in the engine changes.
--
--       **The one designed difference.** One-shot pg_cron job 777 takes three DC fast chargers offline when the run reaches
--       sim 6:58 AM CT. It goes through the cockpit's own door, `ottoq_twin_inject_charger_fault` (0451), which does two things:
--         - reports each fault through `twin.ottoq_report_charger_fault`, which replans the car on the charger
--           (`ottoq_replan_after_charger_fault`);
--         - stamps a 120 sim-minute repair on the sim clock, for `twin.ottoq_sim_recover_chargers`.
--       The door picks a fast charger with a car on it first, in stall order. The job records what it did on the run's payload
--       (`stress_injection_0408`, §17a) and unschedules itself. This is the outage `charger_outage_morning_rush` declares and
--       no code implements (0237, 0319): three fast chargers down through the morning, from about 7:00 AM to 9:00 AM.
--
--       **What it tests.** A charger fault is one of the two reasons rule 9 lets a charge end short, and only if the car is
--       re-queued to finish. The bank is already saturated (0407, G280), and three fast chargers fault at once. The run asks:
--         - does every displaced car resume and finish?
--         - does any car leave short?
--         - what does G279 (a fault sends the car to the back of the line) cost when faults cluster?
--
--       **What happened instead (§17, G281).** The door faulted the three chargers on paper, and not one charge stopped:
--         - two cars finished at 100% on their "faulted" charger;
--         - the third was still charging when its repair clock ran out;
--         - each normal completion put its charger back in service, 19 and 75 minutes into a 120-minute repair.
--       So this run cannot measure the outage it was built for. It is a second day on 0405bf42's seed, perturbed by three
--       phantom reroutes. 0550 fixes the door, and the stress test is repeated on the same seed.
--
--       **The end of the day (16:30 UTC).** Rule 9 held: 132 departures, none below 99% and none with work open (§2), and no
--       charge ended short at any of the day's 18 twin faults (§16). Beside G281 the day found two more things:
--         - G282: 16 stays at the gate below target reached 240 minutes, the longest 356, and a person was told about none of
--           them. The escalation (0546 (d)) reads only staged cars (§18).
--         - G283: two cars at 100% waited 250 and 330 minutes for a deep clean while the wash bays were 54-57% occupied (§19).
--       G279 on the day's own faults: 15 faults below 99% erased 993.8 minutes of accumulated wait (§16b).
--
--       **Not a paired test.** The two runs share the seed, so they draw from the same streams. A charger's fault card is
--       keyed on the car, the stall and the whole minute its session starts (0058), so the two days' faults agree only
--       while the engine puts the same car on the same charger in the same minute, and a live run's ticks follow the wall
--       clock (0406's caveat). 0405bf42's sessions were purged when this run started, so the two days cannot be compared
--       fault by fault after the fact. A difference from 0405bf42 is read against §11b (the twin's own faults) first.

-- ══ §0 BEFORE: 0405bf42 (0407's end READs), the same day with no outage ══════════════════════════════════════════════
--
--     §1  552.7 sim-minutes, 1,089 ticks. KPI 1 148.8 · KPI 2 3.46 · KPI 3 peak site kW 861.9 · KPI 4 1.179 · KPI 5 p95
--         263.5 min (p50 16.7) · returns unserved 35. Charge wait (visits) p50 62.2, p95 333.8; 144 of 203 charged, 59
--         still waiting at the end. Supply gap: 202.3 of 349.1 demand car-hours unmet (57.9%), 146.8 deployed.
--     §2  132 departures (17 with no visit), 0 below 99%, 0 with a service open.
--     §3  0 door refusals, 0 tick failures, 0 floor rejections.
--     §4  7 escalations, each car once, every one `waiting_for_a_charger`; 0 `must_do_work_open`.
--     §5  48 needs-card seats; 81 cars held at the gate, mean longest hold 23 minutes, 0 at the cap.
--     §6  bay entries wash 36, detail 21, service 29.
--     §7  about 87 car-hours staged on need_charge; 9 waits open at the teardown, 3 past 240 minutes.
--     §11 fast chargers 69 sessions, 75.0 hours, 81.4% of nameplate time; L2 115, 251.0, 90.8%. 19 faults, about 13.2
--         fast-charger fault hours (DCFC-10 207 and 244 minutes, DCFC-08 from 10:06 AM to the end).
--     §12 0 stuck episodes; every guard refusal with the car on the stall.
--     §13 49 bay commands with a booking, 0 early, 0 past the booking.
--     §15 waiting for a charger 45.4% of fleet time (at the gate 37.3%, staged 8.1%); charging 30.5%; working 13.8%. 63
--         of 116 cars were waiting for a charger at the end.
--     §16 19 faults, none left short; 17 below 99%, whose faults erased about 28 hours of accumulated wait (G279).
--   Must read the same here: §2 0 and 0; §3 0, 0 and 0; §12a 0; §13a 0 early; §13c 0 past; §16 0 left short. Expected to
--   move, and read as the outage's only against §11b: §1's deployed hours and returns unserved, §4's escalations, §7 and
--   §15's waits.

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The scorecard, for the shape of the day rather than a comparison: what was demanded, what was deployed, and where
--   cars waited.

\echo '=== 0408 §1 — the run and its scorecard ==='
SELECT r.sim_run_id, r.run_by, r.status, r.random_seed, r.sim_clock_start, r.sim_clock_current, r.tick_count,
       r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3';
SELECT public.ottoq_kpi_five('ca448d95-6526-40b6-b36e-a5e02273fff3');
SELECT public.ottoq_kpi_charge_wait('ca448d95-6526-40b6-b36e-a5e02273fff3');
SELECT public.ottoq_kpi_supply_gap('ca448d95-6526-40b6-b36e-a5e02273fff3') - 'by_hour_ct';
-- READ (end, 16:30 UTC): the governor stopped the run at 11:08 AM CT (16:08 UTC), at sim 1:38 PM CT: 552.2 sim-minutes,
--   1,110 ticks. KPI 1 149.38 · KPI 2 3.55 · KPI 3 peak site kW 877.5 (demand 1,036.9) · KPI 4 1.247 · KPI 5 p95 250.6 min
--   (p50 13.3) · returns unserved 30. Charge wait (visits) p50 44.3, p95 366.2; 153 of 206 charged, 53 still waiting at the
--   end. Supply gap: 203.7 of 349.1 demand car-hours unmet (58.4%), 145.4 deployed. Every figure is within a few percent of
--   0405bf42 (§0): the injected outage stopped no charge (§17), so this was the same day on the same seed.

-- ══ §2 RULE 9 STILL HOLDS: NO DEPARTURE WITH A SERVICE OPEN OR A CHARGE SHORT ═════════════════════════════════════════
--
--   0402 §2's query. Both must be 0.

\echo '=== 0408 §2 — departures, and any that left unfinished ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
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
-- READ mid-run (15:38 UTC, 10:38 AM CT; through sim 9:43 AM CT): 80 departures, 0 below 99% (lowest 99), 0 with work open.
-- READ (end, 16:30 UTC): 132 departures (14 with no visit), 0 below 99% (lowest 99), 0 with a service open. Rule 9 held on
--   the day of the injected outage, as on 0405bf42.

-- ══ §3 THE DOOR AND THE FLOOR (0544): NEITHER SHOULD EVER FIRE ════════════════════════════════════════════════════════

\echo '=== 0408 §3 — door refusals and floor rejections ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.dispatch_refused_unfinished') AS door_refusals,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed') AS tick_failures,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed' AND e.payload::text LIKE '%0544 (CLAUDE.md rule 9)%') AS floor_rejections
  FROM public.ottoq_events e WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3';
-- READ mid-run (15:38 UTC; through sim 9:43 AM CT): 0 door refusals, 0 tick failures.
-- READ (end): 0 door refusals, 0 tick failures, 0 floor rejections.

-- ══ §4 ESCALATIONS: THE GATE'S (G269) AND THE WAITS FOR A CHARGER OR THE SERVICE BAY (0546 (d), G274) ══════════════════
--
--   Every escalation, with its reason. A gate escalation (`must_do_work_open`) is a car held for bay work or its
--   check; 0545 (a) times it from the car's last state change, so no state change should fall inside its counted
--   hold. A remedy-wait escalation (0546 (d), `waiting_for_a_charger` or `waiting_for_the_service_bay`) is a car on
--   need_charge or need_service whose last state change is 240 minutes old; (a) makes that the start of its wait, so
--   again no state change should fall inside it. The `remedy_wait` stamp holds the run and the start of the wait, so a
--   car is escalated once per wait: `per_car_and_start` must be 1 everywhere.

\echo '=== 0408 §4 — escalations, by reason, and whether the car changed state inside the counted wait ==='
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
 WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND e.event_type = 'twin.deploy_gate_escalated'
 ORDER BY e.sim_clock_at;
-- READ (end): 8 escalations, each car once.
--   - 6 `waiting_for_a_charger`, all at 8:37 AM: Zoox-AV-086, Tesla-AV-057, Tesla-AV-051, Waymo-AV-007, Zoox-AV-075 and
--     Zoox-004, at 17% to 32%, each after 240.1 minutes with one state change inside the counted wait (the boot's).
--   - 2 `must_do_work_open`, which 0405bf42 did not have: Tesla-RT-002 at 9:03 AM and Waymo-AV-014 at 11:14 AM, both at 100%,
--     each held 240 minutes for an interior deep clean (§19, G283).

-- ══ §5 G270: WHO GOT THE BAY SEATS ═══════════════════════════════════════════════════════════════════════════════════

\echo '=== 0408 §5 — needs-card seats by the seated car''s deploy time, and the gate''s holds ==='
SELECT d.enacted_action->>'purpose' AS purpose,
       CASE WHEN d.context_frame->>'minutes_to_deploy' IS NULL THEN 'no deploy time'
            WHEN (d.context_frame->>'minutes_to_deploy')::int < 0 THEN 'late'
            ELSE 'due later' END AS seated_car,
       count(*) AS seats,
       min((d.context_frame->>'minutes_to_deploy')::int) AS min_mtd, max((d.context_frame->>'minutes_to_deploy')::int) AS max_mtd
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND d.enacted_action->>'source' = 'needs_card' AND d.outcome_status = 'enacted'
 GROUP BY 1, 2 ORDER BY 1, 2;
WITH holds AS (
  SELECT e.entity_id, max((e.payload->'diff'->'config'->'to'->'deploy_gate'->>'held_min')::numeric) AS held
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate' ? 'held_min'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate'->>'run' = e.sim_run_id::text   -- not a prior run's stamp
   GROUP BY 1)
SELECT count(*) AS cars_held, round(avg(held)) AS mean_max_hold_min, max(held) AS longest_hold_min,
       count(*) FILTER (WHERE held >= 240) AS reached_the_cap
  FROM holds;
-- READ (end): 40 needs-card seats: wash 21 (15 due later, 4 late, 2 with no deploy time), detail 12 (7, 4, 1), service 7
--   (5, 1, 1). 72 cars held at the gate, mean longest hold 30 minutes, longest 320.1; 2 reached the cap, the two deep-clean
--   cars of §4.

-- ══ §6 WHAT HOLDING COSTS ═════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0408 §6 — the gate, staging and the bays ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS recheck_events,
       count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_escalated') AS escalated_to_a_person,
       max((e.payload->>'held')::int) FILTER (WHERE e.event_type = 'twin.deploy_gate_summary') AS gate_held_max,
       max((e.payload->>'overflow')::int) FILTER (WHERE e.event_type = 'twin.staging_overflow') AS staging_overflow_max
  FROM public.ottoq_events e WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3';
SELECT (SELECT jsonb_object_agg(to_state, k) FROM (
          SELECT e.payload->'diff'->'current_state'->>'to' AS to_state, count(*) AS k
            FROM public.ottoq_events e WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
           GROUP BY 1) q) AS bay_entries;
-- READ (end): 46 departure rechecks, 8 escalated to a person, the gate held at most 25 cars, staging overflow peaked at 50.
--   Bay entries: wash 33, detail 24, service 28.

-- ══ §7 G271: NO CAR STARVES WAITING FOR A CHARGER OR THE SERVICE BAY ═════════════════════════════════════════════════
--
--   0403 §7's waits, widened to need_service, with the car-hours and the waits that reached 240 minutes. A wait starts
--   where a staged car's step becomes need_charge (or need_service) and ends at its next change of state or step. The
--   teardown's `offline` at the run's last sim minute is not an end. The SoC at the start is the stream's last SoC for
--   the car at or before it. `visit` is the urgency of the car's latest visit at the wait's start, or 'no visit'.
--   Under 0546 (a) and (c) no group should be passed over all day: a boot car with no visit now competes on its ratio,
--   and a waiting car's ratio rises with its wait.

\echo '=== 0408 §7 — waits on need_charge and need_service, by SoC at the start and by how each ended ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
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
-- READ (end): need_charge, below 90%: 44 waits went to a charger (41 cars), p50 9.3 min, p95 165.6, max 377.2, 30.8
--   car-hours, 2 past 240; 6 were still waiting at the end (17.8 car-hours, 1 past 240); 3 boot waits with no SoC reading at
--   the start waited the whole run, 541.0 minutes each (27.0 car-hours). Top-offs (90% and up): 36 went to a charger, p50 1.9,
--   p95 60.4, max 101.8. need_service: 21 went to the service bay, p50 15.7, max 115.8; the rest went back to the gate within
--   9 minutes.

--   The same waits still open at the teardown, by whether the car had a visit (0546 (c)), and whether each wait that
--   reached 240 minutes was escalated once in its stay (0546 (d)). A stay is the car's time in staged_awaiting_service
--   since its last state change, which is what (d) times; one stay can hold more than one wait.

\echo '=== 0408 §7b — the waits still open at the end by visit, and the 240-minute waits against their escalations ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
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
-- READ (end): every staged wait that reached 240 minutes was escalated: 2 that ended (32%, the longest 377.2) and 4 still
--   waiting at the end (27%, 541.0). Still waiting at the end below 240: 5 on need_charge (48% to 80%, the longest 173.0) and
--   6 on need_service at 100% (the longest 97.9). The waits G282 counts are at the gate, not here (§18).

-- ══ §8 G273: NO RELEASE KEEPS A FLAG THE GATE RAISED ═══════════════════════════════════════════════════════════════════
--
--   0403 §8's query. Under 0546 (b) a release drops `deploy_gate_stuck` and `deploy_gate_hard_cap` with its stamp, so
--   those two rows must read 0. A flag raised by anything else is kept, as before, and may appear.

\echo '=== 0408 §8 — gate releases that kept a flag ==='
WITH rel AS (
  SELECT e.entity_id, e.event_seq, e.payload->'diff'->'config'->'to'->>'flagged_issue_type' AS flag_type
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'from' ? 'deploy_gate'
     AND NOT (e.payload->'diff'->'config'->'to' ? 'deploy_gate')
     AND (e.payload->'diff'->'config'->'to'->>'flagged_issue')::boolean)
SELECT flag_type, count(*) AS releases_keeping_the_flag, count(DISTINCT entity_id) AS cars,
       count(DISTINCT entity_id) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_events e3
          WHERE e3.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND e3.entity_id = rel.entity_id
            AND e3.event_type = 'vehicle.state_changed' AND e3.event_seq > rel.event_seq
            AND e3.payload->'diff'->'current_state'->>'to' = 'in_service_bay')) AS later_in_service_bay
  FROM rel GROUP BY flag_type ORDER BY flag_type;
-- READ (end): no release kept a flag.

-- ══ §9 LIVE PROBE: NO STAGED CAR IS RE-STAMPED WITHOUT A STATE CHANGE (G272) ═══════════════════════════════════════════
--
--   0403 §9's probe. Under 0546 (a), STEP 0 stamps only a car it moves into staging, which is a state change, so no
--   staged car should appear. The deployed telemetry still stamps deployed cars with each SoC drain (0546 §4: measured,
--   not changed), so deployed rows are expected. Run while the run is live.

\echo '=== 0408 §9 — cars stamped this tick with no state change ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND status = 'running')
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
-- READ (end): not run: a live probe, and the run had stopped.

--   §9b, the same moment from the queue's side: every car on need_charge with the wait the charge cursor reads (sim now
--   minus `last_state_change`), by whether it has a visit and by its charge.

\echo '=== 0408 §9b — the charge queue and the wait each car reads ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3')
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
-- READ (end): not run: a live probe, and the run had stopped.

-- ══ §10 G271: WHO THE CHARGERS WENT TO, BY WHETHER THE CAR HAD A VISIT ══════════════════════════════════════════════════
--
--   0403 §10's query. On 4acf0b1d no car without a visit got a charger after 5:00 AM. Under 0546 (c) they compete on
--   their ratio, and a top-off's ratio is high, so they should appear from 5:00 AM on.

\echo '=== 0408 §10 — charge sessions by start time and by whether the car had a visit ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
s AS (
  SELECT o.vehicle_id, o.started_at, o.soc_start,
         (SELECT vn.urgency FROM public.ottoq_visit_needs vn
           WHERE vn.vehicle_id = o.vehicle_id AND vn.sim_run_id = r.sim_run_id AND vn.arrived_at <= o.started_at
           ORDER BY vn.created_at DESC LIMIT 1) AS urgency
    FROM public.ocpp_sessions o, r WHERE o.sim_run_id = r.sim_run_id)
SELECT CASE WHEN started_at < timestamptz '2026-09-28 10:00:00+00' THEN 'before 5:00 AM CT' ELSE 'from 5:00 AM CT' END AS started,
       COALESCE(urgency, 'no visit') AS car, count(*) AS sessions, min(soc_start) AS min_soc, max(soc_start) AS max_soc
  FROM s GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (end): 191 sessions. Before 5:00 AM CT: 18 immediate, 27 with no visit (78% to 97%), 6 standard. From 5:00 AM CT:
--   54 immediate (12% to 85%), 85 standard (27% to 98%), 1 tech hold, and none to a car with no visit.

-- ══ §11 THE CHARGERS: HOW BUSY, HOW MANY FAULTED, AND WHAT WAS FREE WHILE CARS WAITED ═══════════════════════════════════
--
--   Session hours against nameplate time by charger kind; every fault with its repair time and how long its charger
--   stood before its next car; and, per hour, the cars waiting on need_charge beside the chargers free by the stall
--   pointer. A charger free while cars wait is either faulted (capacity lost to faults), between two cars (turnover),
--   or a gap in the schedule, which is the only one of the three that orchestration alone can close.

\echo '=== 0408 §11 — charger use by kind ==='
WITH r AS (SELECT sim_run_id, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
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
-- READ (end): fast 10 stalls, 78 sessions, 76.5 hours, 83.1% of nameplate time; L2 30 stalls, 113 sessions, 263.2 hours,
--   95.3%. Against 0405bf42's 81.4% and 90.8%: higher here, because the injected faults stopped no charge.

\echo '=== 0408 §11d — sessions by charger kind and by charge at the start ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
s AS (
  SELECT o.soc_start, st.stall_type::text AS kind,
         COALESCE((SELECT vn.urgency FROM public.ottoq_visit_needs vn
           WHERE vn.vehicle_id = o.vehicle_id AND vn.sim_run_id = r.sim_run_id AND vn.arrived_at <= o.started_at
           ORDER BY vn.created_at DESC LIMIT 1), 'no visit') AS car,
         extract(epoch FROM (COALESCE(o.ended_at, r.sim_clock_current) - o.started_at)) / 60 AS mins,
         o.ended_at IS NOT NULL AND o.status::text = 'completed' AS finished
    FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id, r WHERE o.sim_run_id = r.sim_run_id)
SELECT kind, CASE WHEN soc_start >= 90 THEN 'a >=90' WHEN soc_start >= 70 THEN 'b 70-89' WHEN soc_start >= 50 THEN 'c 50-69' ELSE 'd <50' END AS band,
       count(*) AS sessions, count(*) FILTER (WHERE car = 'immediate_dispatch') AS immediate,
       round(avg(mins) FILTER (WHERE finished)::numeric, 1) AS avg_min_finished, round(sum(mins)::numeric / 60, 1) AS charger_hours
  FROM s GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (end): fast: 90% and up 17 sessions (finished in 10.6 min on average), 70-89 7 (58.9), 50-69 3 (46.4), below 50 51
--   (88.0; 66.2 charger-hours). L2: 90% and up 21 (28.4), 70-89 20 (72.3), 50-69 2 (170.9), below 50 70 (244.8; 225.0
--   charger-hours). Cars below 50% took 291.2 of the 339.7 charger-hours.

\echo '=== 0408 §11b — every charger fault, its repair time, and how long its charger stood before its next car ==='
WITH f AS (
  SELECT e.sim_clock_at AS at, o.stall_id, e.payload->>'reason' AS reason, (e.payload->>'repair_minutes')::numeric AS repair_min
    FROM public.ottoq_events e JOIN public.ocpp_sessions o ON o.id::text = e.entity_id::text
   WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND e.event_type = 'charge.session_faulted')
SELECT s.stall_code, f.at AT TIME ZONE 'America/Chicago' AS fault_ct, f.reason, f.repair_min,
       round(extract(epoch FROM ((SELECT min(o2.started_at) FROM public.ocpp_sessions o2
                                   WHERE o2.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND o2.stall_id = f.stall_id AND o2.started_at > f.at)
                                 - f.at))::numeric / 60, 1) AS stood_until_next_car_min
  FROM f JOIN public.stalls s ON s.id = f.stall_id ORDER BY f.at;
-- READ (end): 18 twin faults, 7 on fast chargers and 11 on L2. Every faulted charger stood out for its drawn repair, 0.5 to
--   3.5 minutes longer, then took its next car. Fast-charger repairs: DCFC-04 46 and 294 minutes, DCFC-05 32 and 129, DCFC-03
--   72, DCFC-02 68, DCFC-06 22, about 11 hours in all. The three injected faults are not here: they closed no session (§17).

--   §11c counts cars at the gate too (`avg_at_gate`): the charge cursor reads them as well as staged cars on need_charge
--   (§15). A charger that reads free by the pointer may be faulted: §11b lists the faults.
\echo '=== 0408 §11c — per hour: cars waiting on need_charge or at the gate, and chargers free by the stall pointer ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
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
gate AS MATERIALIZED (
  SELECT vehicle_id, at AS began, COALESCE(lead(at) OVER (PARTITION BY vehicle_id ORDER BY seq), (SELECT t1 FROM run)) AS ended, to_state
    FROM st WHERE has_state),
g AS (
  SELECT t.at,
         (SELECT count(*) FROM waits w WHERE w.began <= t.at AND w.ended > t.at) AS cars_waiting,
         (SELECT count(*) FROM gate WHERE gate.to_state = 'arrived_at_gate' AND gate.began <= t.at AND gate.ended > t.at) AS at_gate,
         (SELECT count(*) FROM seg WHERE seg.kind = 'dcfc' AND seg.status = 'available' AND seg.a <= t.at AND seg.b > t.at) AS dcfc_free,
         (SELECT count(*) FROM seg WHERE seg.kind = 'l2' AND seg.status = 'available' AND seg.a <= t.at AND seg.b > t.at) AS l2_free
    FROM t)
SELECT to_char(date_trunc('hour', at AT TIME ZONE 'America/Chicago'), 'HH12 AM') AS hour_ct,
       round(avg(cars_waiting), 1) AS avg_cars_waiting, round(avg(at_gate), 1) AS avg_at_gate,
       round(avg(dcfc_free), 1) AS avg_dcfc_free, round(avg(l2_free), 1) AS avg_l2_free,
       sum(dcfc_free) FILTER (WHERE cars_waiting + at_gate > 0) * 2 AS dcfc_free_min_while_waiting,
       sum(l2_free) FILTER (WHERE cars_waiting + at_gate > 0) * 2 AS l2_free_min_while_waiting
  FROM g GROUP BY date_trunc('hour', at AT TIME ZONE 'America/Chicago') ORDER BY date_trunc('hour', at AT TIME ZONE 'America/Chicago');
-- READ (end): from 8 AM to 1 PM CT, 50 to 57 cars were in the charge queue at any moment (43 to 49 at the gate, 7 to 8.5
--   staged) against 40 chargers, with 1.0 to 2.2 fast and 0.3 to 1.1 L2 free by the stall pointer on average (some of those
--   fast ones faulted, §11b). In the 4 AM hour: 22 staged and 44 at the gate, with 4.8 fast and 9.7 L2 free (the boot).

\echo '=== 0408 §11e — charger turnover: from a session''s end to the charger''s next car, by where the car went ==='
--   Completed sessions only (a faulted session's gap is its repair, §11b). `car_went` is the car's first state after
--   the session other than holding, waiting or charging. Since 0547 a fast charger whose car left for a bay takes its
--   next car as soon as one whose car left for departure does (921e349c: p50 1.3, mean 2.1, max 14.4).
WITH r AS MATERIALIZED (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
se AS MATERIALIZED (
  SELECT o.id, o.stall_id, o.vehicle_id, o.started_at, o.ended_at, o.status::text AS status, st.stall_type::text AS kind,
         lead(o.started_at) OVER (PARTITION BY o.stall_id ORDER BY o.started_at) AS next_start
    FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id, r
   WHERE o.sim_run_id = r.sim_run_id),
ve AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq, e.payload->'diff'->'current_state'->>'to' AS to_state
    FROM public.ottoq_events e, r
   WHERE e.sim_run_id = r.sim_run_id AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'
     AND e.entity_id IN (SELECT vehicle_id FROM se)),
nx AS (
  SELECT se.*, x.to_state AS car_went_to
    FROM se LEFT JOIN LATERAL (
      SELECT ve.to_state FROM ve WHERE ve.vehicle_id = se.vehicle_id AND ve.at >= se.ended_at
         AND ve.to_state NOT IN ('charge_complete_holding', 'staged_awaiting_service', 'charging_dcfc', 'charging_l2')
       ORDER BY ve.seq LIMIT 1) x ON true
   WHERE se.status = 'completed')
SELECT kind, CASE WHEN car_went_to IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN 'a bay' ELSE COALESCE(car_went_to, '-') END AS car_went,
       count(*) AS sessions, count(next_start) AS with_next_car,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM next_start - ended_at) / 60))::numeric, 1) AS p50_gap_min,
       round(avg(extract(epoch FROM next_start - ended_at) / 60)::numeric, 1) AS avg_gap_min,
       round(max(extract(epoch FROM next_start - ended_at) / 60)::numeric, 1) AS max_gap_min
  FROM nx GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (end): a charger took its next car a median 0.8 to 1.7 minutes after the last one finished, whichever way that car
--   went; the longest gap 28.1 minutes.

-- ══ §12 G276 STAYS FIXED: A CHARGER IS FREE ONCE ITS CAR HAS LEFT IT FOR A BAY ══════════════════════════════════════
--
--   0405 §12's queries, kept as a regression check. On 921e349c, ae0597b7 and 0405bf42, §12a read no episode and §12b read
--   no refusal with the car on no stall. Both must read 0 on a new day too. Refusals with the car on this stall are
--   the guard doing its job, and they remain. §12c is the live census G121 was found with, for probes while the run is live.

\echo '=== 0408 §12a — charger time stuck with a pointer to a car that left, from the stall stream ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
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
-- READ (end): 3 episodes, each 0.0 seconds long, on DCFC-02 (7:31:26 AM), DCFC-03 (8:26:45 AM) and DCFC-01 (9:41:23 AM):
--   the injected chargers at the moment their car left, when `sync_stall_occupancy` wrote the status before the pointer in the
--   same instant (§17). No charger time was stuck.

\echo '=== 0408 §12b — the guard''s refusals, by where the car was when it asked ==='
WITH a AS (
  SELECT a.vehicle_id, (a.payload->>'from_stall')::uuid AS from_stall, (a.payload->>'requested_at_sim')::timestamptz AS at_sim,
         a.payload->>'state' AS state, s.stall_type::text AS from_kind, a.status
    FROM public.ottoq_ops_approvals a JOIN public.stalls s ON s.id = (a.payload->>'from_stall')::uuid
   WHERE a.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND a.payload->>'reason' = 'automated_reassignment'),
pos AS (
  SELECT a.*,
         (SELECT e.payload->'diff'->'current_stall_id'->>'to' FROM public.ottoq_events e
           WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND e.entity_id = a.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_stall_id' AND e.sim_clock_at <= a.at_sim
           ORDER BY e.event_seq DESC LIMIT 1) AS car_stall_at_request
    FROM a)
SELECT from_kind, state, status,
       CASE WHEN car_stall_at_request IS NULL THEN 'car on no stall' WHEN car_stall_at_request = from_stall::text THEN 'car on this stall'
            ELSE 'car on another stall' END AS car_position,
       count(*) AS n
  FROM pos GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
-- READ (end): 94 refusals, every one with the car on the stall: fast 9 declined (3 of them the injection's pointer clears),
--   L2 83 declined and 2 expired. None with the car on no stall.

\echo '=== 0408 §12c — live: a stall that reads available with a pointer set, and where its car is ==='
--   Run while the run is live. G121's census, at the twin depot. Under 0547 no charger should appear; a bay may, if a
--   car in it has its own pointer empty (0535 §1's shape), because a car in a bay keeps its bay.
SELECT s.stall_code, s.stall_type::text AS kind, s.status::text, v.display_name AS car, v.current_state::text AS car_state,
       cs.stall_code AS car_on_stall, ts.stall_code AS car_tethered_to
  FROM public.stalls s
  JOIN public.vehicles v ON v.id = s.current_vehicle_id
  LEFT JOIN public.stalls cs ON cs.id = v.current_stall_id
  LEFT JOIN public.stalls ts ON ts.id = v.robotic_tether_stall_id
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.status::text = 'available' AND s.current_vehicle_id IS NOT NULL
 ORDER BY 2, 1;
-- READ (end): not run: a live probe, and the run had stopped.

-- ══ §13 G278 STAYS FIXED: NO CAR HOLDS A BAY BEFORE ITS BOOKING ═══════════════════════════════════════════════════
--
--   0406 §13's queries. On 921e349c, before 0549, 4 early entries held the wash bays for 465 minutes. On ae0597b7, under
--   0549:
--     - §13a read no entry more than 5 minutes before its booking;
--     - §13b had nothing to list (the one early reservation, Waymo-AV-020's, had been moved to start when the car went in);
--     - §13c read no booking longer than its service and no car past its booking.
--   The same must hold here. §13c shows a stretched booking as a long one; a car that stays past its booking shows in the
--   last column.

\echo '=== 0408 §13a — bay entries against their bookings: how early the car went in, and the bay-minutes held before the window ==='
WITH c AS (
  SELECT c.vehicle_id, c.command_type, c.payload->>'purpose' AS purpose, c.issued_at,
         b.during, s.stall_type::text AS bay
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
    JOIN public.stalls s ON s.id = b.stall_id
   WHERE c.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed')
SELECT purpose, count(*) AS entries,
       count(*) FILTER (WHERE lower(during) > issued_at + interval '5 minutes') AS entered_over_5_min_early,
       round(max(extract(epoch FROM lower(during) - issued_at) / 60)::numeric, 1) AS max_early_min,
       round(sum(GREATEST(extract(epoch FROM lower(during) - issued_at), 0) / 60) FILTER (WHERE lower(during) > issued_at + interval '5 minutes')::numeric, 1) AS bay_minutes_held_before_the_window
  FROM c GROUP BY 1 ORDER BY 1;
-- READ (end): 41 bay commands with a booking (wash 21, detail 12, service 8), none more than 5 minutes early.

\echo '=== 0408 §13b — the early entries, and the other cars'' bookings on the same bay while the early car sat there ==='
WITH c AS (
  SELECT c.vehicle_id, c.payload->>'purpose' AS purpose, c.issued_at, b.stall_id, b.during, s.stall_code
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
    JOIN public.stalls s ON s.id = b.stall_id
   WHERE c.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed' AND lower(b.during) > c.issued_at + interval '5 minutes'),
x AS (
  SELECT c.*,
         (SELECT min(e.sim_clock_at) FROM public.ottoq_events e
           WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND e.entity_id = c.vehicle_id
             AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_state'->>'from' IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
             AND e.sim_clock_at > c.issued_at) AS left_bay_at
    FROM c)
SELECT v.display_name AS car, x.stall_code AS bay, x.purpose,
       to_char(x.issued_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS entered_ct,
       to_char(lower(x.during) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') || '-' || to_char(upper(x.during) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS booking_ct,
       round((extract(epoch FROM upper(x.during) - lower(x.during)) / 60)::numeric, 1) AS booked_min,
       to_char(x.left_bay_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS left_bay_ct,
       round((extract(epoch FROM x.left_bay_at - x.issued_at) / 60)::numeric, 1) AS minutes_in_bay,
       (SELECT jsonb_agg(jsonb_build_object('car', v2.display_name, 'window', to_char(lower(b2.during) AT TIME ZONE 'America/Chicago', 'HH12:MI') || '-' || to_char(upper(b2.during) AT TIME ZONE 'America/Chicago', 'HH12:MI'),
                                            'state', b2.state, 'released', b2.release_reason) ORDER BY lower(b2.during))
          FROM public.ottoq_stall_bookings b2 LEFT JOIN public.vehicles v2 ON v2.id = b2.vehicle_id
         WHERE b2.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND b2.stall_id = x.stall_id
           AND b2.vehicle_id IS DISTINCT FROM x.vehicle_id
           AND b2.during && tstzrange(x.issued_at, COALESCE(x.left_bay_at, upper(x.during)))) AS other_bookings_while_it_sat
  FROM x JOIN public.vehicles v ON v.id = x.vehicle_id
 ORDER BY x.issued_at;
-- READ (end): nothing to list.

\echo '=== 0408 §13c — every bay command''s booking and time in the bay, by purpose (a stretched booking shows as a long one) ==='
WITH c AS (
  SELECT c.vehicle_id, c.payload->>'purpose' AS purpose, c.issued_at, b.during
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
   WHERE c.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed'),
x AS (
  SELECT c.*,
         extract(epoch FROM upper(c.during) - lower(c.during)) / 60 AS booked_min,
         extract(epoch FROM (SELECT min(e.sim_clock_at) FROM public.ottoq_events e
                              WHERE e.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND e.entity_id = c.vehicle_id
                                AND e.event_type = 'vehicle.state_changed'
                                AND e.payload->'diff'->'current_state'->>'from' IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
                                AND e.sim_clock_at > c.issued_at) - c.issued_at) / 60 AS in_bay_min
    FROM c)
SELECT purpose, count(*) AS entries,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY booked_min))::numeric, 1) AS p50_booked_min,
       round(max(booked_min)::numeric, 1) AS max_booked_min,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY in_bay_min))::numeric, 1) AS p50_in_bay_min,
       round(max(in_bay_min)::numeric, 1) AS max_in_bay_min,
       count(*) FILTER (WHERE in_bay_min > booked_min + 5) AS stayed_past_the_booking
  FROM x GROUP BY 1 ORDER BY 1;
-- READ (end): none past its booking. Median booked and in-bay minutes: wash 9 and 9.3, detail 25 and 25.2, service 40 and
--   40.0.

-- ══ §14 G195 RE-MEASURED: PARKING HOLDS THAT OUTLIVE THEIR CAR, AND WHETHER STAGING EVER BINDS ═══════════════════════
--
--   G195's open half is the parking holds (`temp_hold`, `perimeter_hold`) that stay on the calendar after their car has
--   left the stall; its remedy, the departure sweep (`space_departure_release_enabled`), is off. It costs nothing while
--   staging has room, so §14a counts the leak (0372 §2(c)'s query) and §14b whether staging ever came near full, every
--   ten sim-minutes, from the calendar: stalls with a live booking, and among them stalls whose booked car had left.

\echo '=== 0408 §14a — parking holds that outlived their car, over the whole run (0372 §2(c)) ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
h AS (
  SELECT b.*, (date_trunc('day', lower(b.during)) + (substring(b.why from '\d\d:\d\d-(\d\d:\d\d)'))::time) AS booked_end
    FROM public.ottoq_stall_bookings b JOIN r ON b.sim_run_id = r.run
   WHERE b.purpose IN ('temp_hold','perimeter_hold')),
x AS (
  SELECT h.*, (upper(h.during) > h.booked_end + interval '1 minute') AS renewed,
         (SELECT min(e.sim_clock_at) FROM public.ottoq_events e, r
           WHERE e.sim_run_id = r.run AND e.entity_id = h.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_stall_id'->>'from' = h.stall_id::text
             AND e.sim_clock_at > lower(h.during)) AS left_at
    FROM h),
y AS (
  SELECT x.*, EXTRACT(epoch FROM LEAST(upper(during), COALESCE(released_at, 'infinity'::timestamptz), (SELECT t FROM r))
                                 - left_at) / 60 AS m
    FROM x WHERE left_at < upper(during) AND left_at < COALESCE(released_at, 'infinity'::timestamptz))
SELECT x.purpose, x.renewed, count(*) AS holds,
       (SELECT count(*) FROM y WHERE y.purpose = x.purpose AND y.renewed IS NOT DISTINCT FROM x.renewed) AS outlived_their_car,
       (SELECT round(sum(m)::numeric) FROM y WHERE y.purpose = x.purpose AND y.renewed IS NOT DISTINCT FROM x.renewed) AS stall_min_after_car_left,
       (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY m))::numeric, 1) FROM y
         WHERE y.purpose = x.purpose AND y.renewed IS NOT DISTINCT FROM x.renewed) AS p50_min,
       (SELECT round(max(m)::numeric, 1) FROM y WHERE y.purpose = x.purpose AND y.renewed IS NOT DISTINCT FROM x.renewed) AS max_min
  FROM x GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (end): holds that outlived their car: temp_hold 140 of 164 unrenewed (2,451 stall-minutes, p50 14.2, max 47.6) and
--   116 of 195 renewed (939); perimeter_hold 12 of 13 unrenewed (772, p50 61.1, max 119.4) and 4 of 6 renewed (46).

\echo '=== 0408 §14b — staging stalls on the calendar every ten sim-minutes, and how many of them held a car that had left ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
stg AS (SELECT id FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type::text = 'staging'),
b AS (
  SELECT b.booking_id, b.stall_id, b.vehicle_id, b.purpose, b.state, lower(b.during) AS lo,
         LEAST(upper(b.during), COALESCE(b.released_at, 'infinity'::timestamptz)) AS hi
    FROM public.ottoq_stall_bookings b JOIN r ON b.sim_run_id = r.run
   WHERE b.stall_id IN (SELECT id FROM stg) AND b.state IN ('held', 'active', 'done', 'interrupted')),
bl AS (
  SELECT b.*,
         (SELECT min(e.sim_clock_at) FROM public.ottoq_events e, r
           WHERE e.sim_run_id = r.run AND e.entity_id = b.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_stall_id'->>'from' = b.stall_id::text
             AND e.sim_clock_at > b.lo) AS left_at
    FROM b),
t AS (SELECT generate_series((SELECT t0 FROM r), (SELECT t1 FROM r), interval '10 minutes') AS at),
c AS (
  SELECT t.at,
         count(DISTINCT bl.stall_id) FILTER (WHERE bl.lo <= t.at AND bl.hi > t.at) AS stalls_on_calendar,
         count(DISTINCT bl.stall_id) FILTER (WHERE bl.lo <= t.at AND bl.hi > t.at AND bl.left_at IS NOT NULL AND bl.left_at <= t.at) AS leaked
    FROM t CROSS JOIN bl GROUP BY t.at)
SELECT (SELECT count(*) FROM stg) AS staging_stalls, max(stalls_on_calendar) AS peak_on_calendar,
       round(avg(stalls_on_calendar), 1) AS mean_on_calendar, max(leaked) AS peak_leaked, round(avg(leaked), 1) AS mean_leaked
  FROM c;
-- READ (end): staging peaked at 57 of 113 stalls on the calendar (mean 33.6); at most 14 were held for a car that had left
--   (mean 4.4). Staging never binds, so G195 stays latent.

-- ══ §15 WHERE THE FLEET'S HOURS WENT ═══════════════════════════════════════════════════════════════════════════════════
--
--   0407 §15's query. Each car's time from the run's first minute to its last tick, split by what it was doing, taken
--   from the state and step each `vehicle.state_changed` event leaves it in. A staged car is split by its step. A car at
--   the gate has its own row. The decide tick's charge cursor reads cars at the gate as well as staged cars on need_charge,
--   so a car below its target at the gate is waiting for a charger too. §7 counts only the staged waits, so the
--   time spent waiting for a charger is roughly rows c and d together. The boot puts every car into a state at the first
--   minute, so the first half hour carries the boot's backlog.

\echo '=== 0408 §15 — car-hours by what the car was doing, over the run ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
ev AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'current_state'->>'to' AS s_to,
         CASE WHEN e.payload->'diff' ? 'config' THEN COALESCE(e.payload->'diff'->'config'->'to'->>'svc_step', '-') END AS step_to
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND (e.payload->'diff' ? 'current_state' OR e.payload->'diff' ? 'config')),
g AS (
  SELECT ev.*, count(s_to) OVER w AS gs, count(step_to) OVER w AS gc
    FROM ev WINDOW w AS (PARTITION BY vehicle_id ORDER BY seq)),
f AS (
  SELECT vehicle_id, at, seq,
         first_value(s_to) OVER (PARTITION BY vehicle_id, gs ORDER BY seq) AS state,
         first_value(step_to) OVER (PARTITION BY vehicle_id, gc ORDER BY seq) AS step
    FROM g),
seg AS (
  SELECT f.*, COALESCE(lead(at) OVER (PARTITION BY vehicle_id ORDER BY seq), (SELECT t1 FROM run)) AS b FROM f),
lab AS (
  SELECT CASE WHEN state IN ('deployed', 'en_route_to_deployment') THEN 'a working (deployed or leaving)'
              WHEN state = 'en_route_to_depot' THEN 'b returning to the depot'
              WHEN state = 'arrived_at_gate' THEN 'c at the gate'
              WHEN state = 'staged_awaiting_service' AND step = 'need_charge' THEN 'd staged, waiting for a charger'
              WHEN state = 'staged_awaiting_service' THEN 'e staged, ' || COALESCE(NULLIF(step, '-'), 'no step')
              WHEN state IN ('charging_l2', 'charging_dcfc') THEN 'f ' || state
              WHEN state = 'charge_complete_holding' THEN 'g charge complete, holding'
              WHEN state IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay') THEN 'h ' || state
              WHEN state = 'staged_for_departure' THEN 'i staged for departure'
              ELSE 'j ' || COALESCE(state, '?') END AS what,
         extract(epoch FROM (b - at)) AS secs
    FROM seg WHERE b > at)
SELECT what, round((sum(secs) / 3600)::numeric, 1) AS car_hours,
       round((100 * sum(secs) / (SELECT 116 * extract(epoch FROM (t1 - t0)) FROM run))::numeric, 1) AS pct_of_fleet_time
  FROM lab GROUP BY 1 ORDER BY 1;
-- READ (end): waiting for a charger 43.4% of fleet time (at the gate 35.1%, staged 8.3%); charging 31.9% (L2 24.7%, fast
--   7.2%); working 13.6%; staged on need_deploy 4.0% (42.2 car-hours, about 9.7 of them the two deep-clean waits of §19).
--   Against 0405bf42: 45.4%, 30.5% and 13.8%.

-- ══ §16 RULE 9 AT A CHARGER FAULT: EVERY INTERRUPTED CAR IS RE-QUEUED TO FINISH ═════════════════════════════════════
--
--   0407 §16's query. A charger fault is one of the two reasons rule 9 lets a charge end short, and only if the car is
--   re-queued to finish. For every faulted session this query takes the car's charge at the fault, its next session
--   (when, on what kind of charger, and how it ended) and its next dispatch. `left without resuming` is allowed only for
--   a car already at 99% or more at the fault (the charge rule treats the target minus 1 as charged, 0493). The last
--   column must be 0. On 0405bf42, the same day without the outage, it read 0 over 19 faults (§0).

\echo '=== 0408 §16 — every charger fault: what the car did next, and at what charge it left ==='
WITH r AS (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
f AS (
  SELECT o.id, o.vehicle_id, st.stall_type::text AS kind, o.ended_at AS faulted_at, o.soc_end AS soc_at_fault, o.stopped_reason
    FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id, r
   WHERE o.sim_run_id = r.sim_run_id AND o.status::text = 'faulted'),
x AS (
  SELECT f.*, nx.started_at AS resumed_at, nx.kind AS resumed_on, nx.status AS resumed_status, nx.soc_end AS resumed_soc_end,
         dep.left_at, dep.soc_at_departure
    FROM f
    LEFT JOIN LATERAL (
      SELECT o2.started_at, st2.stall_type::text AS kind, o2.status::text AS status, o2.soc_end
        FROM public.ocpp_sessions o2 JOIN public.stalls st2 ON st2.id = o2.stall_id, r
       WHERE o2.sim_run_id = r.sim_run_id AND o2.vehicle_id = f.vehicle_id AND o2.started_at >= f.faulted_at
       ORDER BY o2.started_at LIMIT 1) nx ON true
    LEFT JOIN LATERAL (
      SELECT d.dispatched_at AS left_at, d.soc_at_dispatch_pct AS soc_at_departure
        FROM public.ottoq_vehicle_dispatches d, r
       WHERE d.sim_run_id = r.sim_run_id AND d.vehicle_id = f.vehicle_id AND d.dispatched_at > f.faulted_at
       ORDER BY d.dispatched_at LIMIT 1) dep ON true),
y AS (
  SELECT x.*,
         CASE WHEN x.resumed_at IS NOT NULL AND (x.left_at IS NULL OR x.resumed_at < x.left_at) THEN
                CASE x.resumed_status WHEN 'completed' THEN 'resumed and finished' WHEN 'active' THEN 'resumed, still charging'
                                      WHEN 'cancelled' THEN 'resumed, still charging at the end'  -- the teardown closes a running session
                                      WHEN 'faulted' THEN 'resumed, faulted again' ELSE 'resumed, ' || x.resumed_status END
              WHEN x.left_at IS NOT NULL THEN 'left without resuming'
              ELSE 'not resumed by the end' END AS outcome,
         extract(epoch FROM (COALESCE(x.resumed_at, (SELECT t1 FROM r)) - x.faulted_at)) / 60 AS wait_min
    FROM x)
SELECT kind, outcome, count(*) AS faults, min(soc_at_fault) AS min_soc_at_fault, max(soc_at_fault) AS max_soc_at_fault,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY wait_min))::numeric, 1) AS p50_wait_min,
       round(max(wait_min)::numeric, 1) AS max_wait_min,
       min(soc_at_departure) AS min_soc_at_departure,
       count(*) FILTER (WHERE outcome = 'left without resuming' AND soc_at_fault < 99) AS left_short_without_resuming
  FROM y GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (end): 18 twin faults. Fast (7): 3 resumed and finished (81% to 97%, left at 100%), 3 not resumed by the end (63% to
--   80%, waited a median 139.2 minutes, the longest 173.0), 1 left at 99%. L2 (11): 7 resumed and finished (50% to 96%), 1
--   faulted again, 1 still charging at the end, 2 left at 99%. left_short_without_resuming is 0. The injected outage is not
--   here: it stopped no session (§17).

-- OPEN-ITEM: G279 — a car whose charger faults re-enters the charge line as if it had just arrived (§16b).

--   §16b, the same faults with the wait each car had behind it when the faulted session started. The charge cursor
--   measures a car's wait from its last state change (0545 (c), 0546 (a)), and a fault moves the car from charging back
--   to staging, so the fault erases that wait: the car re-enters the line as if it had just arrived (G279).

\echo '=== 0408 §16b — per fault: the wait before the faulted session, the charge it got, and the wait after ==='
WITH r AS (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
f AS (
  SELECT o.id, o.vehicle_id, st.stall_type::text AS kind, o.started_at, o.ended_at AS faulted_at, o.soc_start, o.soc_end AS soc_at_fault
    FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id, r
   WHERE o.sim_run_id = r.sim_run_id AND o.status::text = 'faulted'),
w AS (
  SELECT f.*,
         (SELECT max(e.sim_clock_at) FROM public.ottoq_events e, r
           WHERE e.sim_run_id = r.sim_run_id AND e.entity_id = f.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_state'
             AND e.payload->'diff'->'current_state'->>'to' NOT IN ('charging_l2', 'charging_dcfc')
             AND e.sim_clock_at < f.started_at) AS wait_began
    FROM f)
SELECT v.display_name AS car, w.kind, w.soc_start, w.soc_at_fault,
       to_char(w.wait_began AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS wait_began_ct,
       to_char(w.started_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS session_ct,
       to_char(w.faulted_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS fault_ct,
       round((extract(epoch FROM (w.started_at - w.wait_began)) / 60)::numeric, 1) AS waited_before_min,
       round((extract(epoch FROM (w.faulted_at - w.started_at)) / 60)::numeric, 1) AS charged_min,
       (SELECT round((extract(epoch FROM (min(o2.started_at) - w.faulted_at)) / 60)::numeric, 1) FROM public.ocpp_sessions o2, r
         WHERE o2.sim_run_id = r.sim_run_id AND o2.vehicle_id = w.vehicle_id AND o2.started_at >= w.faulted_at) AS waited_after_min
  FROM w JOIN public.vehicles v ON v.id = w.vehicle_id
 ORDER BY w.faulted_at;
-- READ (end): 15 of the 18 faults hit cars below 99%. The waits those cars had behind them add up to 993.8 minutes, about
--   16.6 hours, all erased (G279; 0405bf42: 1,686 minutes over 17). The largest:
--   - Zoox-AV-086 had waited 377.2 minutes (escalated at 8:37 AM), charged 24.5 minutes (32% to 63%) on DCFC-05 from 10:54 AM,
--     lost it to a fault at 11:18 AM, and was not charging again by the end.
--   - Waymo-AV-008 faulted twice: at 7:48 AM on an L2 (75%), then after waiting 175.2 minutes it got a fast charger at 10:43
--     AM, which faulted 1.6 minutes later (DCFC-02). Not resumed by the end.
--   - Tesla-AV-065 had waited 101.4 minutes, charged 154.4 (39% to 94%), faulted at 8:53 AM and waited 101.8 more.

-- ══ §17 THE OUTAGE: WHAT THE DOOR DID, AND WHAT THE WORLD DID (G281) ══════════════════════════════════════════════════
--
--   §17a reads job 777's receipt from the run's payload. §17b follows each injected charger:
--     - the car on it, and whether its session stopped;
--     - OTTO-Q's reroute (the `resource_fault` approval) and the pointer guard's answer (the `automated_reassignment` row);
--     - the 'stage' command the replan sent, and whether the car ever reached the stall it was sent to;
--     - when the next car plugged in. `out_of_service_min` is the outage the world saw, `declared_repair_min` the one asked.
--
--   The job fired once. Its first attempt, at 15:19 UTC, deadlocked against the tick (40P01). The door's report path
--   (`twin.ottoq_report_charger_fault` → the stall's reassignment guard → an INSERT into `ottoq_ops_approvals`) runs in
--   the job's own transaction, and the live tick takes no lock the door could share: the only world lock is the
--   recertification one (`ottoq_try_world_lock`). The retry at 15:20 UTC succeeded. The cockpit's button reaches the
--   same door through `otto-twin-control`, so an operator can meet the same deadlock; pressing again is the remedy today.

-- OPEN-ITEM: G281 — the cockpit's charger-fault door never stops the charge, and a normal completion un-faults the charger (§17b).

\echo '=== 0408 §17a — the injection''s receipt, from the run''s payload ==='
SELECT r->>'stall_code' AS charger,
       to_char((r->>'faulted_at_sim')::timestamptz AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS faulted_ct,
       to_char((r->>'recovers_at_sim')::timestamptz AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS recovers_ct,
       (r->>'repair_minutes')::numeric AS repair_min, v.display_name AS car_on_it, x->>'disposition' AS disposition,
       ps.stall_code AS sent_to, (sr.payload->'stress_injection_0408'->>'at_real')::timestamptz AS injected_at_real_utc
  FROM public.ottoq_sim_runs sr
  CROSS JOIN LATERAL jsonb_array_elements(sr.payload->'stress_injection_0408'->'results') r
  LEFT JOIN LATERAL jsonb_array_elements(r->'report'->'vehicles') x ON true
  LEFT JOIN public.vehicles v ON v.id = (x->>'vehicle_id')::uuid
  LEFT JOIN public.stalls ps ON ps.id = (x->>'new_stall')::uuid
 WHERE sr.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'
 ORDER BY 1;
-- READ (15:28 UTC): three rows, all injected at sim 7:12:44 AM CT with a 120-minute repair (back at 9:12:44 AM CT):
--   DCFC-STALL-01 Waymo-AV-004 → NASH-STG-B004; DCFC-STALL-02 Zoox-AV-077 → NASH-STG-I001; DCFC-STALL-03 Waymo-AV-016 →
--   NASH-STG-I002. Every disposition `temp_parked_awaiting_charger`: no healthy fast charger was free, so each car was
--   given a staging stall to wait on.
-- READ (end): unchanged.

\echo '=== 0408 §17b — per injected charger: did the charge stop, did the car move, and how long was the charger out ==='
WITH run AS MATERIALIZED (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1, r.payload->'stress_injection_0408' AS inj
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
inj AS (
  SELECT st.id AS stall_id, st.stall_code, (r->>'faulted_at_sim')::timestamptz AS fault_at, (r->>'recovers_at_sim')::timestamptz AS recovers_at,
         (r->'report'->'vehicles'->0->>'vehicle_id')::uuid AS car, (r->'report'->'vehicles'->0->>'new_stall')::uuid AS sent_to
    FROM run CROSS JOIN LATERAL jsonb_array_elements(run.inj->'results') r
    JOIN public.stalls st ON st.ocpp_charger_id = (r->>'charger_id')::uuid AND st.depot_id = '11111111-1111-1111-1111-111111111111'),
s AS (
  SELECT i.*, os.status::text AS sess_status, os.soc_start, os.soc_end, os.ended_at
    FROM inj i LEFT JOIN LATERAL (
      SELECT o.* FROM public.ocpp_sessions o WHERE o.sim_run_id = (SELECT id FROM run) AND o.stall_id = i.stall_id AND o.vehicle_id = i.car
         AND o.started_at <= i.fault_at AND (o.ended_at IS NULL OR o.ended_at > i.fault_at)
       ORDER BY o.started_at DESC LIMIT 1) os ON true),
nx AS (
  SELECT s.*, n.started_at AS next_start, nv.display_name AS next_car
    FROM s LEFT JOIN LATERAL (
      SELECT o.* FROM public.ocpp_sessions o WHERE o.sim_run_id = (SELECT id FROM run) AND o.stall_id = s.stall_id AND o.started_at > s.fault_at
       ORDER BY o.started_at LIMIT 1) n ON true
    LEFT JOIN public.vehicles nv ON nv.id = n.vehicle_id)
SELECT nx.stall_code AS charger, v.display_name AS car, nx.sess_status, nx.soc_start, nx.soc_end,
       round((extract(epoch FROM (COALESCE(nx.ended_at, (SELECT t1 FROM run)) - nx.fault_at)) / 60)::numeric, 1) AS charged_on_after_fault_min,
       (SELECT a.status FROM public.ottoq_ops_approvals a WHERE a.sim_run_id = (SELECT id FROM run) AND a.vehicle_id = nx.car
          AND a.payload->>'reason' = 'resource_fault' AND (a.payload->>'requested_at_sim')::timestamptz = nx.fault_at LIMIT 1) AS reroute,
       (SELECT a.status FROM public.ottoq_ops_approvals a WHERE a.sim_run_id = (SELECT id FROM run) AND a.vehicle_id = nx.car
          AND a.payload->>'reason' = 'automated_reassignment' AND (a.payload->>'from_stall')::uuid = nx.stall_id
          AND (a.payload->>'requested_at_sim')::timestamptz = nx.fault_at LIMIT 1) AS pointer_clear,
       (SELECT m.status FROM public.ottoq_comms_messages m
         WHERE m.sim_run_id = (SELECT id FROM run) AND m.vehicle_id = nx.car AND m.direction = 'downlink'
           AND m.payload->'params'->>'plan_update' = 'charger_fault_reroute' ORDER BY m.created_at LIMIT 1) AS stage_command,
       ps.stall_code AS sent_to,
       EXISTS (SELECT 1 FROM public.ottoq_events e
                WHERE e.sim_run_id = (SELECT id FROM run) AND e.event_type = 'vehicle.state_changed' AND e.entity_id = nx.car
                  AND e.sim_clock_at >= nx.fault_at AND e.payload->'diff'->'current_stall_id'->>'to' = nx.sent_to::text) AS went_there,
       nx.next_car, to_char(nx.next_start AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS next_car_in_ct,
       round((extract(epoch FROM (nx.next_start - nx.fault_at)) / 60)::numeric, 1) AS out_of_service_min,
       round((extract(epoch FROM (nx.recovers_at - nx.fault_at)) / 60)::numeric, 1) AS declared_repair_min
  FROM nx JOIN public.vehicles v ON v.id = nx.car LEFT JOIN public.stalls ps ON ps.id = nx.sent_to
 ORDER BY 1;
-- READ (15:36 UTC, sim 9:27 AM CT): the outage did not happen. Not one charge stopped.
--   - DCFC-STALL-02: Zoox-AV-077 charged on for 18.3 minutes and completed at 100% at 7:31:04 AM. Waymo-AV-018 plugged in
--     at 7:31:54 AM, so the charger was out 19.2 of its 120 minutes, and only for new cars.
--   - DCFC-STALL-03: Waymo-AV-016 charged on for 73.4 minutes and completed at 100% at 8:26:08 AM. Zoox-AV-076 plugged in
--     at 8:27:36 AM: 74.9 of 120.
--   - DCFC-STALL-01: Waymo-AV-004 (32% at 6:59 AM) was still charging 133.4 minutes after the fault, at 98%. Its repair
--     clock ran out underneath it: the charger read Available again from 9:14:09 AM, with the car still on it.
--   For all three: reroute `approved`, pointer_clear `declined`, stage_command `completed`, went_there false.
--
--   Why, from the source (G281). Four writers, each correct on its own terms:
--     1. The door does not stop the charge. `ottoq_twin_inject_charger_fault` (0451) reports the fault through
--        `twin.ottoq_report_charger_fault`, the depot tech's "confirm a fault" path. That path:
--          - marks the charger Faulted and the stall `maintenance`, and clears the stall's reservation;
--          - replans each car on or reserved to the stall (`ottoq_replan_after_charger_fault`), which reserves a stall
--            for an hour and sends a downlink.
--        Nothing in it closes the running `ocpp_sessions` row, so the twin's charge advance keeps adding energy. In
--        the world a faulted charger ends its session itself. The twin's own faults do exactly that: they stop the
--        session through `twin.ottoq_sim_stop_charge_session` with a `fault.*` reason, which re-queues the car (§16).
--        The door never takes that path.
--     2. The replan records a move that never happens. The stall's reassignment guard declines to clear the pointer,
--        because the car is on the stall. That is correct, and it is the only record that tells the truth.
--        `ottoq_comms_send_command` writes the 'stage' downlink and its ack as `completed` and does nothing to the car.
--        So the approvals say the car was rerouted, the comms ledger says the command completed, and the car never
--        left the charger.
--     3. A normal completion un-faults the charger. `twin.ottoq_sim_stop_charge_session` sets
--        `station_state = CASE WHEN p_reason LIKE 'fault%' THEN 'Faulted' ELSE 'Available' END` whatever the charger's
--        state was, and restarts `station_state_changed_at`, which is the repair clock. Zoox-AV-077's completion ended
--        DCFC-02's repair 18 minutes in, and Waymo-AV-016's ended DCFC-03's 73 minutes in.
--     4. The car's departure un-maintenances the stall. `sync_stall_occupancy`, the trigger on `vehicles`, sets the stall
--        a car leaves to `available` whatever its status was (DCFC-02 at 7:31:26 AM, DCFC-03 at 8:26:45 AM, in the stall
--        stream). The next car was reserved in the same tick and plugged in within 1.5 minutes. HW.002 at
--        `charge_session_start` passed, correctly, because the charger read Available.
--   Also found by reading, not seen here because every injected charger had a car:
--     - Recovery returns only the charger. `twin.ottoq_sim_recover_chargers` sets it Available, and nothing returns its
--       stall from `maintenance`.
--     - So a fault injected on an idle charger would hold its stall out of service until the next run's seed, long
--       after the repair.
--   What the run can therefore say:
--     - It cannot measure the outage it was built for. Rule 9 at a fault is exercised only by the twin's own faults
--       (§16), as on 0405bf42, and G279's cost when faults cluster is not measurable here.
--     - It remains a second day on 0405bf42's seed, perturbed by three phantom reroutes. It is a replication on the
--       same key, not an independent observation (G153).
--   The door is fixed in 0550, and the stress test is repeated on the same seed.
-- READ (end, 16:30 UTC): all three cars finished at 100% on their faulted charger, and each charger took its next car
--   within 1.5 minutes: Zoox-AV-077 at 7:31 AM (18.3 minutes after the fault; next car at 19.2), Waymo-AV-016 at 8:26 AM (73.4;
--   74.9) and Waymo-AV-004 at 9:40 AM (148.1; 149.5), 28 minutes after its repair clock had run out. The reroute approvals
--   expired unused, every stage command reads `completed`, and no car went to the stall it was sent to.

-- ══ §18 G282: A CAR AT THE GATE BELOW ITS TARGET IS NEVER ESCALATED, HOWEVER LONG IT WAITS FOR A CHARGER ═══════════════
--
--   0546 (d) escalates a car to a person when it has waited past 240 minutes for a charger or the service bay (G274).
--   Its loop reads only staged cars on need_charge or need_service. The charge cursor also reads cars at the gate (§15:
--   most of the fleet's wait for a charger is spent there), and nothing escalates those. Per stay at the gate, by whether
--   the car arrived below its target: how many stays reached 240 minutes, and how many of those were never escalated.

-- OPEN-ITEM: G282 — a car at the gate below its target is never escalated to a person, however long it waits (§18).

\echo '=== 0408 §18 — stays at the gate: how many reached 240 minutes, and how many of those a person was never told about ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
st AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'current_state'->>'to' AS s_to, (e.payload->'diff'->'current_soc'->>'to')::numeric AS soc_to,
         e.payload->'diff' ? 'current_state' AS has_state
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND (e.payload->'diff' ? 'current_state' OR e.payload->'diff' ? 'current_soc')),
seg AS (
  SELECT vehicle_id, at AS began, seq, s_to, lead(at) OVER (PARTITION BY vehicle_id ORDER BY seq) AS ended
    FROM st WHERE has_state),
gate AS (
  SELECT g.vehicle_id, g.began, COALESCE(g.ended, (SELECT t1 FROM run)) AS ended, g.ended IS NULL AS still_there,
         extract(epoch FROM (COALESCE(g.ended, (SELECT t1 FROM run)) - g.began)) / 60 AS wait_min,
         (SELECT s0.soc_to FROM st s0 WHERE s0.vehicle_id = g.vehicle_id AND s0.soc_to IS NOT NULL AND s0.seq <= g.seq
           ORDER BY s0.seq DESC LIMIT 1) AS soc_at_arrival
    FROM seg g WHERE g.s_to = 'arrived_at_gate' AND g.began > (SELECT t0 FROM run)),
esc AS (
  SELECT g.*, (SELECT count(*) FROM public.ottoq_events e, run
                WHERE e.sim_run_id = run.id AND e.event_type = 'twin.deploy_gate_escalated' AND e.entity_id = g.vehicle_id
                  AND e.sim_clock_at >= g.began AND e.sim_clock_at <= g.ended) AS escalations
    FROM gate g)
SELECT CASE WHEN soc_at_arrival < 99 THEN 'below target' ELSE 'at target' END AS at_the_gate,
       count(*) AS stays, count(*) FILTER (WHERE wait_min >= 240) AS stays_240_plus,
       count(*) FILTER (WHERE wait_min >= 240 AND escalations = 0) AS of_which_never_escalated,
       round(max(wait_min)::numeric, 1) AS longest_min, count(*) FILTER (WHERE still_there) AS still_there
  FROM esc GROUP BY 1 ORDER BY 1;
-- READ mid-run (15:55 UTC; through sim 11:40 AM CT): below target, 100 stays, 4 reached 240 minutes, all 4 never
--   escalated, the longest 262.0 minutes, 36 cars still at the gate. At target, 1 stay of 0 minutes.
-- READ (end, 16:30 UTC): below target, 124 stays; 16 reached 240 minutes and none of the 16 was escalated. The longest was
--   356.4 minutes, and the 16 hold 77.2 car-hours. At target, 1 stay of 0 minutes. Every staged wait that reached 240 was
--   escalated (§7b), so the gap is the gate alone (G282).


-- ══ §19 G283: TWO CARS AT 100% WAITED 250 AND 330 MINUTES FOR A DEEP CLEAN WHILE THE WASH BAYS WERE HALF IDLE ════════════
--
--   §4's two `must_do_work_open` escalations: Tesla-RT-002 and Waymo-AV-014, both at 100%, waited on need_deploy for an
--   interior deep clean. The twin depot has no detail bay: deep cleans (purpose `detail`) run in the three wash bays, with the
--   washes. The windows are each car's wait, from the state stream: Tesla-RT-002 from 4:54 AM to 10:24 AM CT, Waymo-AV-014
--   from 7:14 AM to 11:24 AM CT. Per window: the minutes cars spent in a wash bay (either purpose), against the three bays'
--   minutes.

-- OPEN-ITEM: G283 — two cars at 100% waited 250 and 330 minutes for a deep clean while the wash bays were 54-57% occupied (§19).

\echo '=== 0408 §19 — the wash bays while each deep-clean car waited ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3'),
st AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq, e.payload->'diff'->'current_state'->>'to' AS s_to
    FROM public.ottoq_events e, run WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'),
seg AS (SELECT vehicle_id, at AS began, s_to, lead(at) OVER (PARTITION BY vehicle_id ORDER BY seq) AS ended FROM st),
inbay AS (SELECT s.vehicle_id, s.s_to, s.began, COALESCE(s.ended, (SELECT t1 FROM run)) AS ended FROM seg s WHERE s.s_to IN ('in_wash_bay','in_detail_bay')),
w AS (SELECT * FROM (VALUES ('Tesla-RT-002', timestamptz '2026-09-28 09:54:00+00', timestamptz '2026-09-28 15:24:00+00'),
                            ('Waymo-AV-014', timestamptz '2026-09-28 12:14:00+00', timestamptz '2026-09-28 16:24:00+00')) x(car, w0, w1))
SELECT w.car, round((extract(epoch FROM (w.w1 - w.w0))/60)::numeric) AS wait_min,
       round((sum(extract(epoch FROM (LEAST(i.ended, w.w1) - GREATEST(i.began, w.w0)))) FILTER (WHERE i.ended > w.w0 AND i.began < w.w1) / 60)::numeric, 1) AS bay_car_minutes_in_window,
       round((3 * extract(epoch FROM (w.w1 - w.w0)) / 60)::numeric) AS bay_capacity_minutes,
       count(*) FILTER (WHERE i.ended > w.w0 AND i.began < w.w1) AS bay_visits_in_window,
       count(*) FILTER (WHERE i.ended > w.w0 AND i.began < w.w1 AND i.s_to = 'in_detail_bay') AS detail_visits_in_window
  FROM w CROSS JOIN inbay i GROUP BY w.car, w.w0, w.w1 ORDER BY 1;
-- READ (end, 16:30 UTC): Tesla-RT-002 waited 330 minutes, and in that window the three wash bays held a car for 565.3 of
--   990 bay-minutes (57%), 41 visits of which 15 deep cleans. Waymo-AV-014 waited 250 minutes: 407.3 of 750 (54%), 26 visits,
--   12 deep cleans. So the bays were idle 43-46% of the time these two cars sat at 100% waiting for one.
--   Not the capacity of the bays, then. The needs-card seat admits wash-bay work up to the lesser of the cleaning staff and
--   the wash supervisor, less a share held for reservations (`ottoq_decide_tick`, `v_wash_open`), and that is the next thing
--   to measure. The cause is not established here. 0405bf42, the same seed, held no car at the cap for a deep clean, so this
--   is sensitive to the day's timing rather than built into the seed. Rule 9 held: neither car left before its deep clean,
--   and each was escalated to a person at 240 minutes.

\echo '=== 0408 §19b — the wash bays'' calendar in the same windows: bookings used, released unused and superseded ==='
WITH bays AS (SELECT id FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type::text = 'wash_bay'),
w AS (SELECT * FROM (VALUES ('Tesla-RT-002', timestamptz '2026-09-28 09:54:00+00', timestamptz '2026-09-28 15:24:00+00'),
                            ('Waymo-AV-014', timestamptz '2026-09-28 12:14:00+00', timestamptz '2026-09-28 16:24:00+00')) x(car, w0, w1)),
b AS (
  SELECT b.booking_id, b.purpose, b.state, b.during
    FROM public.ottoq_stall_bookings b
   WHERE b.sim_run_id = 'ca448d95-6526-40b6-b36e-a5e02273fff3' AND b.stall_id IN (SELECT id FROM bays))
SELECT w.car, b.state, b.purpose, count(*) AS bookings,
       round((sum(extract(epoch FROM (LEAST(upper(b.during), w.w1) - GREATEST(lower(b.during), w.w0)))) / 60)::numeric, 1) AS booked_min_in_window
  FROM w JOIN b ON b.during && tstzrange(w.w0, w.w1)
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ (16:36 UTC, after the run): in Tesla-RT-002's window (990 bay-minutes) the wash bays' calendar carried 35 bookings
--   that were used (detail 12 and wash 23, 448.3 minutes), 15 released unused (detail 6 and wash 9, 224.0) and 9 superseded
--   (89.0). In Waymo-AV-014's window (750): 22 used (320.6), 16 released unused (211.9), 5 superseded (67.0). So about a third
--   of the bays' time was held on the calendar by reservations that never became a service. A car seated for a deep clean
--   needs 25 free minutes on the calendar, not only an empty bay, which is the likely mechanism: the hypothesis for G283,
--   not yet proven. The seat's own decisions would prove it, and they are purged with this run when the next one starts.
-- READ (16:38 UTC, the decision ledger, before the next run purges it): the needs-card seat asked for Tesla-RT-002's deep
--   clean 77 times from 5:24 AM to 10:10 AM CT, and for Waymo-AV-014's 69 times from 7:42 AM to 11:22 AM CT. Every one was
--   `noop_no_candidate`: no wash bay passed the seat's gates. The first that found one was enacted at 10:23 AM and 11:23 AM.
--   The frame at 7:06 AM for Tesla-RT-002: `fits_window` false, `minutes_to_deploy` −108 (already late), urgency `due`, and
--   6 cars waiting fresh in the detail lane. The frame does not say which gate refused each bay, so the cause stays open.
