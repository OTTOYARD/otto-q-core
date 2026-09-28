-- 0406  **A car seated in a bay early is served now: the first operator run under 0549, beside 921e349c and dbdffd5c.**
--
--       Written on 2026-09-28 (CT) for the validation run after 0549 (applied 20260928111517, 6:15 AM CT). When a car
--       takes a wash, detail or service bay before its own reservation there, `ottoq.ottoq_record_enacted_booking` now
--       moves the reservation to start when the car goes in, with its own length (or the caller's window if longer),
--       instead of stretching it back to cover both now and its old end. The needs-card seat asks for a planned leg's
--       length from now, not the leg's planned end. The door still pins the car's time in the bay to the booking's end,
--       which is now the end of the work (G278). Read-only.
--       The run is ae0597b7-439c-46db-9e8e-8b5fa241629c. Cron 776 started it at 11:44:38 UTC (6:44 AM CT), once all
--       nine canon columns had passed under 0549 (verdicts 567-575, 6:16-6:35 AM CT, every one equal on all fourteen
--       atoms).
--       It is busy_day at 8x on 921e349c's seed (and dbdffd5c's), on the same sim day, Monday 2026-09-28, from the same
--       sim minute, 4:41 AM CT. The tariff, the building load, the grid and the weather read the same. It is not a
--       paired test: a live run's ticks follow the wall clock, so from the first bay 0549 frees early the runs differ,
--       and so do the faults a charger can draw (§11b). A difference is read against §11b before it is read as 0549's.
--
--       **921e349c's and dbdffd5c's sides are §0, from 0405's and 0404's end READs.**

-- ══ §0 BEFORE: 921e349c (0405's end READs) and dbdffd5c (0404's) ══════════════════════════════════════════════════════
--
--   921e349c first, then dbdffd5c. 921e349c ran under 0547 and not 0549; dbdffd5c under neither.
--     §1  sim minutes 554.1 / 552.5; ticks 1,083 / 1,067. KPI 1 asset hours 122.3 / 129.5 · KPI 2 turns per point 3.20 /
--         3.22 · KPI 3 peak site kW 961.5 / 1,045.9 · KPI 4 touches per turn 1.198 / 1.204 · KPI 5 p95 time to service
--         291.4 / 293.3 min (p50 16.8 / 49.4) · returns unserved 26 / 30. Charge wait (visits) p50 83.8 / 82.6, p95
--         434.5 / 442.1. Supply gap: 241.7 of 362 demand car-hours unmet (66.8%) / 231.5 of 360.4 (64.2%); deployed 120.3
--         / 128.9; peak shortfall 43 / 47.
--     §2  departures 113 / 114 (no visit 18 / 17), 0 below 99%, 0 with a service open, on both.
--     §3  0 door refusals, 0 tick failures, 0 floor rejections, on both.
--     §4  escalations 24 / 13: `waiting_for_a_charger` 15 / 13; **`must_do_work_open` 9 / 0**, every one on 921e349c a
--         car at 100% waiting for a wash or deep clean.
--     §5  needs-card seats 27 / 33.
--     §6  cars held at the gate 90 / 78, mean longest hold 63 / 28 minutes, **9 / 0 at the cap**. Bay entries: **wash 25
--         / 36, detail 11 / 15**, service 21 / 21.
--     §7  about 149 / 150 car-hours waited on need_charge.
--     §11 fast chargers 79 sessions, 76.7 stall-hours (83.0%) / 69, 74.3 (80.7%); about 11.6 fast-charger fault hours on
--         each, on different chargers.
--     §12 (G276 under 0547, 921e349c only) 0 stuck episodes; 0 refusals with the car on no stall. §11e: a fast charger
--         whose car left for a bay took its next car a median 1.3 minutes later, mean 2.1, max 14.4.
--     §13 (G278, 921e349c only; dbdffd5c's commands went with its purge) 29 bay commands with a booking: wash 16 (2
--         entered more than 5 minutes early, the earliest 222.8, 252.5 bay-minutes held before the window), detail 9 (2
--         early, 157.2, 212.4), service 4 (none). 4 early entries held the wash bays 465 minutes; each car left its bay
--         at its booking's end to the minute; 12 cars had a booking elapse under an early car, 3 of them among §4's 9
--         gate escalations. One stretch succeeded: Tesla-AV-060, seated at 6:07 AM for a deep-clean reservation of
--         6:41-6:59 AM on WSH-02, had it stretched to 6:07-6:59 and held the bay 52.3 minutes. §13c on 921e349c (10:58
--         UTC): wash 16 entries, booked 9 minutes each, in the bay p50 9.3 and max 232.0, 2 stayed past the booking;
--         detail 9, booked p50 25.0 and max 52.3, in the bay p50 25.3 and max 182.2, 2 stayed past; service 4, booked
--         p50 42.5 and max 45.0, in the bay max 45.1, none stayed past.
--   Under 0549 the expectation is §13a 0 entries more than 5 minutes early and no bay-minutes held before a window,
--   §13c no booking longer than its service, and §4 and §6 read against both columns above.

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0406 §1 — the run and its scorecard ==='
SELECT r.sim_run_id, r.run_by, r.status, r.random_seed, r.sim_clock_start, r.sim_clock_current, r.tick_count,
       r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c';
SELECT public.ottoq_kpi_five('ae0597b7-439c-46db-9e8e-8b5fa241629c');
SELECT public.ottoq_kpi_charge_wait('ae0597b7-439c-46db-9e8e-8b5fa241629c');
SELECT public.ottoq_kpi_supply_gap('ae0597b7-439c-46db-9e8e-8b5fa241629c') - 'by_hour_ct';
-- READ (end, 2026-09-28 13:01-13:10 UTC, 8:01-8:10 AM CT): the governor stopped the run at 12:54:00 UTC (7:54 AM CT),
--   sim 1:55 PM CT, 554.1 sim-minutes and 1,075 ticks (921e349c 554.1 and 1,083; dbdffd5c 552.5 and 1,067). This run
--   first, then 921e349c, then dbdffd5c (§0):
--     KPI 1 asset hours **143.3** against 122.3 and 129.5 · KPI 2 turns per point 3.23 against 3.20 and 3.22
--     KPI 3 peak site kW 989.1 (demand 954.2) against 961.5 (872.3) and 1,045.9 (1,162.1)
--     KPI 4 touches per turn 1.269 against 1.198 and 1.204 · KPI 5 p95 time to service 299.3 min (p50 12.1) against
--       291.4 (16.8) and 293.3 (49.4) · returns unserved 35 against 26 and 30
--     charge wait (visits): p50 59.3, p95 394.1, max 554.1 min; 146 of 194 charged, 48 still waiting at the end.
--       921e349c: p50 83.8, p95 434.5; 149 of 181; 32. dbdffd5c: p50 82.6, p95 442.1; 141 of 182; 41.
--     supply gap: **220 of 362 demand car-hours unmet (60.8%), 141.9 deployed**, peak shortfall 39. 921e349c: 241.7 of 362
--       (66.8%), 120.3, 43. dbdffd5c: 231.5 of 360.4 (64.2%), 128.9, 47.
--   **Deployed car-hours rose 21.6 over 921e349c and 13.0 over dbdffd5c.** The charger side read the same as on both:
--   about 11.8 fast-charger fault hours (§11b), about 153 car-hours on need_charge (§7), the fast chargers 83.4% busy
--   (§11). What changed is the bays (§4, §6, §13): no car held a bay before its booking, 34 wash and 22 detail entries
--   against 25 and 11, and no car at 100% held at the gate for a wash. 136 dispatches against 117 sent more cars out
--   and so brought more back into the same charger bank: returns unserved rose from 26 to 35 and visits still owed a
--   charge at the horizon from 32 to 48. That is the charger bank's capacity, with rule 9 holding (§2). One run each
--   on the same seed and sim day, so a comparison, not a paired test.

-- ══ §2 RULE 9 STILL HOLDS: NO DEPARTURE WITH A SERVICE OPEN OR A CHARGE SHORT ═════════════════════════════════════════
--
--   0402 §2's query. Both must be 0.

\echo '=== 0406 §2 — departures, and any that left unfinished ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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
-- READ early (2026-09-28 11:48 UTC, 6:48 AM CT; tick 43, sim 5:11 AM CT): 4 departures, 0 below 99% (the lowest was
--   100), 0 with a service open.
-- READ mid-run (12:27 UTC, 7:27 AM CT; tick 655, sim 10:16 AM CT): **89 departures, 0 below 99% (the lowest was 99),
--   0 with a service open** (921e349c: 73 by sim 10:00 AM).
-- READ (end, 13:03 UTC): **132 departures (17 with no visit), 0 below 99% (the lowest was 99), 0 with a service
--   open.** Rule 9 held for a fifth full day (921e349c 113, dbdffd5c 114).

-- ══ §3 THE DOOR AND THE FLOOR (0544): NEITHER SHOULD EVER FIRE ════════════════════════════════════════════════════════

\echo '=== 0406 §3 — door refusals and floor rejections ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.dispatch_refused_unfinished') AS door_refusals,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed') AS tick_failures,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed' AND e.payload::text LIKE '%0544 (CLAUDE.md rule 9)%') AS floor_rejections
  FROM public.ottoq_events e WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c';
-- READ early (11:48 UTC): 0 door refusals, 0 tick failures, 0 floor rejections.
-- READ mid-run (12:27 UTC): 0 door refusals, 0 tick failures, 0 floor rejections.
-- READ (end, 13:03 UTC): 0 door refusals, 0 tick failures, 0 floor rejections.

-- ══ §4 ESCALATIONS: THE GATE'S (G269) AND THE WAITS FOR A CHARGER OR THE SERVICE BAY (0546 (d), G274) ══════════════════
--
--   Every escalation, with its reason. A gate escalation (`must_do_work_open`) is a car held for bay work or its
--   check; 0545 (a) times it from the car's last state change, so no state change should fall inside its counted
--   hold. A remedy-wait escalation (0546 (d), `waiting_for_a_charger` or `waiting_for_the_service_bay`) is a car on
--   need_charge or need_service whose last state change is 240 minutes old; (a) makes that the start of its wait, so
--   again no state change should fall inside it. The `remedy_wait` stamp holds the run and the start of the wait, so a
--   car is escalated once per wait: `per_car_and_start` must be 1 everywhere.

\echo '=== 0406 §4 — escalations, by reason, and whether the car changed state inside the counted wait ==='
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
 WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND e.event_type = 'twin.deploy_gate_escalated'
 ORDER BY e.sim_clock_at;
-- READ mid-run (12:27 UTC; through sim 10:16 AM CT): 14 escalations, every one `waiting_for_a_charger`. **No
--   `must_do_work_open`**: no car at 100% held 240 minutes for a wash or deep clean (921e349c: 1 by sim 10:00 AM,
--   9 by the end).
-- READ (end, 13:03 UTC): **14 escalations, each car once, every one `waiting_for_a_charger`** (12-38%, 240.0-240.1
--   minutes, 8:53 AM to 10:21 AM). **0 `must_do_work_open`** (921e349c 9, every one a car at 100% waiting for a wash
--   or deep clean; dbdffd5c 0).

-- ══ §5 G270: WHO GOT THE BAY SEATS ═══════════════════════════════════════════════════════════════════════════════════

\echo '=== 0406 §5 — needs-card seats by the seated car''s deploy time, and the gate''s holds ==='
SELECT d.enacted_action->>'purpose' AS purpose,
       CASE WHEN d.context_frame->>'minutes_to_deploy' IS NULL THEN 'no deploy time'
            WHEN (d.context_frame->>'minutes_to_deploy')::int < 0 THEN 'late'
            ELSE 'due later' END AS seated_car,
       count(*) AS seats,
       min((d.context_frame->>'minutes_to_deploy')::int) AS min_mtd, max((d.context_frame->>'minutes_to_deploy')::int) AS max_mtd
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND d.enacted_action->>'source' = 'needs_card' AND d.outcome_status = 'enacted'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (end, 13:04 UTC): 22 needs-card seats: 12 to cars due out later, 8 to late cars, 2 with no deploy time
--   (921e349c 27; dbdffd5c 33).
WITH holds AS (
  SELECT e.entity_id, max((e.payload->'diff'->'config'->'to'->'deploy_gate'->>'held_min')::numeric) AS held
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate' ? 'held_min'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate'->>'run' = e.sim_run_id::text   -- not a prior run's stamp
   GROUP BY 1)
SELECT count(*) AS cars_held, round(avg(held)) AS mean_max_hold_min, max(held) AS longest_hold_min,
       count(*) FILTER (WHERE held >= 240) AS reached_the_cap
  FROM holds;
-- READ (end, 13:04 UTC): 82 cars held at the gate, **mean longest hold 20 minutes** (921e349c 63, dbdffd5c 28), longest
--   220.2, **0 at the cap** (921e349c 9, dbdffd5c 0).

-- ══ §6 WHAT HOLDING COSTS ═════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0406 §6 — the gate, staging and the bays ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS recheck_events,
       count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_escalated') AS escalated_to_a_person,
       max((e.payload->>'held')::int) FILTER (WHERE e.event_type = 'twin.deploy_gate_summary') AS gate_held_max,
       max((e.payload->>'overflow')::int) FILTER (WHERE e.event_type = 'twin.staging_overflow') AS staging_overflow_max
  FROM public.ottoq_events e WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c';
SELECT (SELECT jsonb_object_agg(to_state, k) FROM (
          SELECT e.payload->'diff'->'current_state'->>'to' AS to_state, count(*) AS k
            FROM public.ottoq_events e WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
           GROUP BY 1) q) AS bay_entries;
-- READ mid-run (12:27 UTC): bay entries so far **27 wash, 13 detail**, 17 service: already more wash and detail
--   entries than 921e349c's whole day (25, 11). The gate held at most 32 cars at once and staging overflow peaked at
--   54, as on both runs before.
-- READ (end, 13:03 UTC): bay entries **34 wash, 22 detail**, 25 service (921e349c 25, 11, 21; dbdffd5c 36, 15, 21).
--   37 recheck events. The gate held at most 32 cars at once and staging overflow peaked at 54, as on both.

-- ══ §7 G271: NO CAR STARVES WAITING FOR A CHARGER OR THE SERVICE BAY ═════════════════════════════════════════════════
--
--   0403 §7's waits, widened to need_service, with the car-hours and the waits that reached 240 minutes. A wait starts
--   where a staged car's step becomes need_charge (or need_service) and ends at its next change of state or step. The
--   teardown's `offline` at the run's last sim minute is not an end. The SoC at the start is the stream's last SoC for
--   the car at or before it. `visit` is the urgency of the car's latest visit at the wait's start, or 'no visit'.
--   Under 0546 (a) and (c) no group should be passed over all day: a boot car with no visit now competes on its ratio,
--   and a waiting car's ratio rises with its wait.

\echo '=== 0406 §7 — waits on need_charge and need_service, by SoC at the start and by how each ended ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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
-- READ (end, 13:06 UTC): need_charge: 10 waits still open at the teardown, all below 90% (12-76%), 42.8 car-hours, 4
--   past 240 minutes (921e349c 11, 28.2, 2; dbdffd5c 12, 48.0, 4). To a charger: 50 waits below 90% (47 cars; p50 35.1,
--   p95 487.5, max 541.4; 10 past 240) and 35 top-offs (p50 1.7, max 104.2). Back to the gate at 100%: 32. About 153
--   car-hours waited on need_charge in all (921e349c about 149, dbdffd5c about 150). need_service: 2 still waiting at
--   the end, both at 100%, up to 47.6 minutes.

--   The same waits still open at the teardown, by whether the car had a visit (0546 (c)), and whether each wait that
--   reached 240 minutes was escalated once in its stay (0546 (d)). A stay is the car's time in staged_awaiting_service
--   since its last state change, which is what (d) times; one stay can hold more than one wait.

\echo '=== 0406 §7b — the waits still open at the end by visit, and the 240-minute waits against their escalations ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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

\echo '=== 0406 §8 — gate releases that kept a flag ==='
WITH rel AS (
  SELECT e.entity_id, e.event_seq, e.payload->'diff'->'config'->'to'->>'flagged_issue_type' AS flag_type
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'from' ? 'deploy_gate'
     AND NOT (e.payload->'diff'->'config'->'to' ? 'deploy_gate')
     AND (e.payload->'diff'->'config'->'to'->>'flagged_issue')::boolean)
SELECT flag_type, count(*) AS releases_keeping_the_flag, count(DISTINCT entity_id) AS cars,
       count(DISTINCT entity_id) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_events e3
          WHERE e3.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND e3.entity_id = rel.entity_id
            AND e3.event_type = 'vehicle.state_changed' AND e3.event_seq > rel.event_seq
            AND e3.payload->'diff'->'current_state'->>'to' = 'in_service_bay')) AS later_in_service_bay
  FROM rel GROUP BY flag_type ORDER BY flag_type;

-- ══ §9 LIVE PROBE: NO STAGED CAR IS RE-STAMPED WITHOUT A STATE CHANGE (G272) ═══════════════════════════════════════════
--
--   0403 §9's probe. Under 0546 (a), STEP 0 stamps only a car it moves into staging, which is a state change, so no
--   staged car should appear. The deployed telemetry still stamps deployed cars with each SoC drain (0546 §4: measured,
--   not changed), so deployed rows are expected. Run while the run is live.

\echo '=== 0406 §9 — cars stamped this tick with no state change ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND status = 'running')
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

--   §9b, the same moment from the queue's side: every car on need_charge with the wait the charge cursor reads (sim now
--   minus `last_state_change`), by whether it has a visit and by its charge.

\echo '=== 0406 §9b — the charge queue and the wait each car reads ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c')
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

-- ══ §10 G271: WHO THE CHARGERS WENT TO, BY WHETHER THE CAR HAD A VISIT ══════════════════════════════════════════════════
--
--   0403 §10's query. On 4acf0b1d no car without a visit got a charger after 5:00 AM. Under 0546 (c) they compete on
--   their ratio, and a top-off's ratio is high, so they should appear from 5:00 AM on.

\echo '=== 0406 §10 — charge sessions by start time and by whether the car had a visit ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
s AS (
  SELECT o.vehicle_id, o.started_at, o.soc_start,
         (SELECT vn.urgency FROM public.ottoq_visit_needs vn
           WHERE vn.vehicle_id = o.vehicle_id AND vn.sim_run_id = r.sim_run_id AND vn.arrived_at <= o.started_at
           ORDER BY vn.created_at DESC LIMIT 1) AS urgency
    FROM public.ocpp_sessions o, r WHERE o.sim_run_id = r.sim_run_id)
SELECT CASE WHEN started_at < timestamptz '2026-09-28 10:00:00+00' THEN 'before 5:00 AM CT' ELSE 'from 5:00 AM CT' END AS started,
       COALESCE(urgency, 'no visit') AS car, count(*) AS sessions, min(soc_start) AS min_soc, max(soc_start) AS max_soc
  FROM s GROUP BY 1, 2 ORDER BY 1, 2;

-- ══ §11 THE CHARGERS: HOW BUSY, HOW MANY FAULTED, AND WHAT WAS FREE WHILE CARS WAITED ═══════════════════════════════════
--
--   Session hours against nameplate time by charger kind; every fault with its repair time and how long its charger
--   stood before its next car; and, per hour, the cars waiting on need_charge beside the chargers free by the stall
--   pointer. A charger free while cars wait is either faulted (capacity lost to faults), between two cars (turnover),
--   or a gap in the schedule, which is the only one of the three that orchestration alone can close.

\echo '=== 0406 §11 — charger use by kind ==='
WITH r AS (SELECT sim_run_id, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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
-- READ (end, 13:05 UTC): fast chargers 71 sessions, 77.0 hours, 83.4% of nameplate time (921e349c 79, 76.7, 83.0%;
--   dbdffd5c 69, 74.3, 80.7%); L2 118 sessions, 263.3 hours, 95.1% (dbdffd5c 114, 261.2, 94.6%).

\echo '=== 0406 §11d — sessions by charger kind and by charge at the start ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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

\echo '=== 0406 §11b — every charger fault, its repair time, and how long its charger stood before its next car ==='
WITH f AS (
  SELECT e.sim_clock_at AS at, o.stall_id, e.payload->>'reason' AS reason, (e.payload->>'repair_minutes')::numeric AS repair_min
    FROM public.ottoq_events e JOIN public.ocpp_sessions o ON o.id::text = e.entity_id::text
   WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND e.event_type = 'charge.session_faulted')
SELECT s.stall_code, f.at AT TIME ZONE 'America/Chicago' AS fault_ct, f.reason, f.repair_min,
       round(extract(epoch FROM ((SELECT min(o2.started_at) FROM public.ocpp_sessions o2
                                   WHERE o2.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND o2.stall_id = f.stall_id AND o2.started_at > f.at)
                                 - f.at))::numeric / 60, 1) AS stood_until_next_car_min
  FROM f JOIN public.stalls s ON s.id = f.stall_id ORDER BY f.at;
-- READ (end, 13:05 UTC; the whole run): 12 faults. Fast chargers: DCFC-08 437 min from 4:54 AM (as on both runs
--   before), DCFC-05 twice (10 min at 6:39 AM, 108 at 10:20 AM), DCFC-03 51 at 11:07 AM, DCFC-04 98 from 12:30 PM to
--   the end: about 11.8 fast-charger hours (921e349c and dbdffd5c about 11.6 each). L2: 7 faults of 10-137 minutes.

\echo '=== 0406 §11c — per hour: cars waiting on need_charge, and chargers free by the stall pointer ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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

\echo '=== 0406 §11e — charger turnover: from a session''s end to the charger''s next car, by where the car went ==='
--   Completed sessions only (a faulted session's gap is its repair, §11b). `car_went` is the car's first state after
--   the session other than holding, waiting or charging. Since 0547 a fast charger whose car left for a bay takes its
--   next car as soon as one whose car left for departure does (921e349c: p50 1.3, mean 2.1, max 14.4).
WITH r AS MATERIALIZED (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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

-- ══ §12 G276 STAYS FIXED: A CHARGER IS FREE ONCE ITS CAR HAS LEFT IT FOR A BAY ══════════════════════════════════════
--
--   0405 §12's queries, kept as a regression check: on 921e349c, under 0547, §12a read no episode and §12b no refusal
--   with the car on no stall (§0 §12). 0549 moves bay bookings, not charger pointers, so both must read 0 again. The
--   refusals with the car on this stall are the guard doing its job and remain. §12c is the live census G121 was found
--   with, for the probes while the run is live.

\echo '=== 0406 §12a — charger time stuck with a pointer to a car that left, from the stall stream ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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
-- READ mid-run (12:28 UTC; through sim 10:16 AM CT): 0 episodes on any stall. G276 stays fixed.
-- READ (end, 13:07 UTC; the whole run): 0 episodes, 0 stall-minutes. G276 stays fixed.

\echo '=== 0406 §12b — the guard''s refusals, by where the car was when it asked ==='
WITH a AS (
  SELECT a.vehicle_id, (a.payload->>'from_stall')::uuid AS from_stall, (a.payload->>'requested_at_sim')::timestamptz AS at_sim,
         a.payload->>'state' AS state, s.stall_type::text AS from_kind, a.status
    FROM public.ottoq_ops_approvals a JOIN public.stalls s ON s.id = (a.payload->>'from_stall')::uuid
   WHERE a.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND a.payload->>'reason' = 'automated_reassignment'),
pos AS (
  SELECT a.*,
         (SELECT e.payload->'diff'->'current_stall_id'->>'to' FROM public.ottoq_events e
           WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND e.entity_id = a.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_stall_id' AND e.sim_clock_at <= a.at_sim
           ORDER BY e.event_seq DESC LIMIT 1) AS car_stall_at_request
    FROM a)
SELECT from_kind, state, status,
       CASE WHEN car_stall_at_request IS NULL THEN 'car on no stall' WHEN car_stall_at_request = from_stall::text THEN 'car on this stall'
            ELSE 'car on another stall' END AS car_position,
       count(*) AS n
  FROM pos GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
-- READ mid-run (12:28 UTC): 64 guard asks, every one with the car on the stall being emptied (62 declined, 1
--   approved, 1 pending); 0 with the car on no stall or another stall.
-- READ (end, 13:07 UTC): 93 guard asks, every one with the car on the stall being emptied (88 L2 and 4 DCFC
--   declined, 1 L2 expired); 0 with the car on no stall or another stall.

\echo '=== 0406 §12c — live: a stall that reads available with a pointer set, and where its car is ==='
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
-- READ early (11:48 UTC; sim 5:12 AM CT): no stall read available with a pointer set.
-- READ mid-run (12:28 UTC; sim 10:16 AM CT): no stall read available with a pointer set.
-- READ (end, 13:07 UTC): the run had ended, so the live census has nothing to read. §12a is its whole-run form.

-- ══ §13 G278 UNDER 0549: A CAR SEATED IN A BAY EARLY IS SERVED NOW ════════════════════════════════════════════════
--
--   0405 §13's queries, and §13c. On 921e349c a car seated in a bay before its own reservation there held the bay
--   until the reservation's end, because the booking code left the reservation in the future and the door pins the
--   car's time in the bay to the booking's end (§0 §13). Under 0549 the reservation moves to start when the car goes
--   in, so §13a must read no entry more than 5 minutes before its booking and no bay-minutes held before a window, and
--   §13b must list nothing. §13c reads every bay command's booking length and time in the bay by purpose: a stretched
--   booking shows as a long one, and a car that stays past its booking shows in the last column.

\echo '=== 0406 §13a — bay entries against their bookings: how early the car went in, and the bay-minutes held before the window ==='
WITH c AS (
  SELECT c.vehicle_id, c.command_type, c.payload->>'purpose' AS purpose, c.issued_at,
         b.during, s.stall_type::text AS bay
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
    JOIN public.stalls s ON s.id = b.stall_id
   WHERE c.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed')
SELECT purpose, count(*) AS entries,
       count(*) FILTER (WHERE lower(during) > issued_at + interval '5 minutes') AS entered_over_5_min_early,
       round(max(extract(epoch FROM lower(during) - issued_at) / 60)::numeric, 1) AS max_early_min,
       round(sum(GREATEST(extract(epoch FROM lower(during) - issued_at), 0) / 60) FILTER (WHERE lower(during) > issued_at + interval '5 minutes')::numeric, 1) AS bay_minutes_held_before_the_window
  FROM c GROUP BY 1 ORDER BY 1;
-- READ mid-run (12:26 UTC; through sim 10:16 AM CT): 18 bay commands with a booking: wash 11, detail 4, service 3.
--   **0 entered more than 5 minutes before its booking; 0 bay-minutes held before a window** (921e349c by sim 10:00
--   AM: Tesla-RT-003 in WSH-02 since 7:02 AM for a 10:45 booking).
-- READ (end, 13:04 UTC; the whole run): 26 bay commands with a booking: wash 14, detail 8, service 4. **0 entered more
--   than 5 minutes before its booking; 0 bay-minutes held before a window** (921e349c: 4 entries, 465 bay-minutes).

\echo '=== 0406 §13b — the early entries, and the other cars'' bookings on the same bay while the early car sat there ==='
WITH c AS (
  SELECT c.vehicle_id, c.payload->>'purpose' AS purpose, c.issued_at, b.stall_id, b.during, s.stall_code
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
    JOIN public.stalls s ON s.id = b.stall_id
   WHERE c.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed' AND lower(b.during) > c.issued_at + interval '5 minutes'),
x AS (
  SELECT c.*,
         (SELECT min(e.sim_clock_at) FROM public.ottoq_events e
           WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND e.entity_id = c.vehicle_id
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
         WHERE b2.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND b2.stall_id = x.stall_id
           AND b2.vehicle_id IS DISTINCT FROM x.vehicle_id
           AND b2.during && tstzrange(x.issued_at, COALESCE(x.left_bay_at, upper(x.during)))) AS other_bookings_while_it_sat
  FROM x JOIN public.vehicles v ON v.id = x.vehicle_id
 ORDER BY x.issued_at;
-- READ mid-run (12:26 UTC): nothing to list. **0549 (a) seen live:** Waymo-AV-020 held a wash reservation on WSH-03
--   made at 4:51 AM for its planned leg at 7:33-7:41 AM. Seated at 6:24 AM, the reservation moved to 6:24-6:33 AM
--   with its 9 minutes and the car left after 10.3. WSH-03 then washed Tesla-AV-048 at 6:40 and Waymo-AV-011 at 7:31,
--   the bookings the old stretch would have collided with and left to elapse.
-- READ (end, 13:04 UTC): nothing to list. The one adopted early reservation of the day is Waymo-AV-020's (mid-run
--   READ above): moved from 7:33-7:41 AM to 6:24-6:33 AM, in the bay 10.3 minutes.

\echo '=== 0406 §13c — every bay command''s booking and time in the bay, by purpose (a stretched booking shows as a long one) ==='
WITH c AS (
  SELECT c.vehicle_id, c.payload->>'purpose' AS purpose, c.issued_at, b.during
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
   WHERE c.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed'),
x AS (
  SELECT c.*,
         extract(epoch FROM upper(c.during) - lower(c.during)) / 60 AS booked_min,
         extract(epoch FROM (SELECT min(e.sim_clock_at) FROM public.ottoq_events e
                              WHERE e.sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c' AND e.entity_id = c.vehicle_id
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
-- READ early (11:48 UTC; sim 5:12 AM CT): 1 bay command so far, a service entry, booked 45 minutes from the minute
--   the car went in; no wash or detail entry yet.
-- READ mid-run (12:26 UTC; through sim 10:16 AM CT): wash 11 entries, booked 9 minutes each, in the bay p50 9.3 and
--   max 10.3; detail 4, booked 25, in the bay max 25.3; service 3, booked 45, in the bay max 45.3. **No booking
--   longer than its service and nobody stayed past a booking** (921e349c: wash max 232.0 in the bay, detail max 182.2,
--   a stretched detail booking of 52.3).
-- READ (end, 13:04 UTC; the whole run): wash 14 entries, booked 9 minutes each, in the bay p50 9.3 and max 10.3;
--   detail 8, booked 25, in the bay p50 25.3 and max 26.2; service 4, booked p50 42.5 and max 45, in the bay max 45.3.
--   **No booking longer than its service and nobody stayed past a booking.** G278 is fixed (921e349c: wash max 232.0 in
--   the bay, detail max 182.2, a stretched detail booking of 52.3).

-- ══ §14 G195 RE-MEASURED: PARKING HOLDS THAT OUTLIVE THEIR CAR, AND WHETHER STAGING EVER BINDS ═══════════════════════
--
--   G195's open half is the parking holds (`temp_hold`, `perimeter_hold`) that stay on the calendar after their car has
--   left the stall; its remedy, the departure sweep (`space_departure_release_enabled`), is off. It costs nothing while
--   staging has room, so §14a counts the leak (0372 §2(c)'s query) and §14b whether staging ever came near full, every
--   ten sim-minutes, from the calendar: stalls with a live booking, and among them stalls whose booked car had left.

\echo '=== 0406 §14a — parking holds that outlived their car, over the whole run (0372 §2(c)) ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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
-- READ (end, 13:26 UTC, 8:26 AM CT): perimeter_hold as booked 11 holds, 10 outlived their car, 843 stall-minutes, p50
--   96.8, max 119.5; perimeter_hold renewed 6, 3, 23; temp_hold as booked 125, 112, 1,759, p50 14.1, max 69.4; temp_hold
--   renewed 187, 114, 887, p50 7.2, max 14.5. About 3,512 stall-minutes in all (b0fdc92b under 0500: 2,876).

\echo '=== 0406 §14b — staging stalls on the calendar every ten sim-minutes, and how many of them held a car that had left ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ae0597b7-439c-46db-9e8e-8b5fa241629c'),
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
-- READ (end, 13:27 UTC): of 113 staging stalls, the calendar held at most 62 at once (5:21 AM sim), 33.6 on average;
--   stalls held by a car that had left, at most 12 at once (6:01 AM), 3.8 on average. **Staging never came near full,
--   so G195's open half stays latent: calendar hygiene, not a capacity cost.** The binding constraint on this run is the
--   charger bank (§1, §7). The departure sweep stays off until a paired test shows it frees a stall someone was waiting for.
