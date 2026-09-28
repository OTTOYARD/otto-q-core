-- 0405  **A charger is free once its car has left it for a bay: the first operator run under 0547, beside dbdffd5c.**
--
--       Written on 2026-09-28 (CT) for the validation run after 0547 (applied 20260928074913, 2:49 AM CT): when an
--       update empties a stall's pointer, `public.ottoq_trg_reassignment_guard` now also reads where the car is. A
--       charger (dcfc, l2) whose car is in a wash, detail or service bay, and which neither the car's `current_stall_id`
--       nor its tether names, is emptied without asking the in-depot gate. A car charging keeps its charger and a car in a
--       bay keeps its bay, as before (G276, the writer behind G121). Read-only.
--       The run is 921e349c-ded0-4907-9e0b-6b288b61831f. Cron 775 started it at 08:18:37 UTC (3:18 AM CT), once all
--       nine canon columns had passed under 0547 (verdicts 558-566, 2:50-3:08 AM CT, every one equal on all fourteen
--       atoms). It is busy_day at 8x on dbdffd5c's seed (and 4acf0b1d's and 9eab647f's), and it opens at the same sim
--       minute, 4:41 AM CT.
--       **The pairing is closer than 0404's.** dbdffd5c's sim day was Monday 2026-09-28, and so is this run's: the same
--       seed, the same start minute, the same day of the week and of the year, so the tariff, the building load, the
--       grid, the weather and a charger's heat stress read the same. The random draws key on the seed, the entity and
--       the minutes since the run's start. It is still not a paired test: a live run's ticks follow the wall clock
--       (dbdffd5c ran 1,067 ticks over 552.5 sim-minutes; 4acf0b1d 1,090 over 550), so a decision can land a tick
--       earlier or later anywhere, and from the first charger 0547 frees the two runs' sessions differ, and with them the
--       faults a session can draw (§11b). A difference is read against §11b before it is read as 0547's.
--
--       **dbdffd5c's side is §0, from 0404's end READs and one query measured before this run purged it.**

-- ══ §0 BEFORE: dbdffd5c (0404's end READs, and §11e measured before the purge) ══════════════════════════════════════
--
--   §1-§12 are 0404's end READs (2026-09-28 07:18-07:27 UTC). §11e was measured on dbdffd5c's rows with this file's
--   query at 07:52 UTC (2:52 AM CT), before this run purged them.
--     §1  the governor stopped the run at sim 1:53 PM CT: 552.5 sim-minutes, 1,067 ticks. KPI 1 asset hours 129.5 · KPI 2
--         turns per point 3.22 · KPI 3 peak site kW 1,045.9 (demand 1,162.1) · KPI 4 touches per turn 1.204 · KPI 5 p95
--         time to service 293.3 min (p50 49.4), 30 returns unserved. Charge wait (visits) p50 82.6, p95 442.1, max 510.4
--         min; 141 of 182 visits owing a charge charged, 41 still waiting. Supply gap 231.5 of 360.4 demand car-hours
--         unmet (64.2%), 128.9 deployed, peak shortfall 47.
--     §2  114 departures (17 with no visit), 0 below 99% (the lowest was 99), 0 with a service open.
--     §3  0 door refusals, 0 tick failures, 0 floor rejections.
--     §4  13 escalations, every one `waiting_for_a_charger`, 13 cars, each once, held 240.0-240.3 minutes, from 8:54 AM
--         to 12:54 PM, all standard visits at 12-48%. No gate escalation (`must_do_work_open`).
--     §5  33 needs-card seats: 14 to cars due out later, 12 to late cars, 7 with no deploy time.
--     §6  78 cars held at the gate, mean longest hold 28 minutes, longest 220.1, 0 at the cap. 24 recheck events, 13
--         escalated. The gate held at most 32 cars at once; staging overflow peaked at 54. Bay entries: 36 wash, 15
--         detail, 21 service.
--     §7  need_charge: 12 waits still open at the teardown, all below 90% (12-66%), 48.0 car-hours, 4 past 240 minutes.
--         To a charger: 50 waits below 90% (48 cars; p50 18.8, p95 451.0, max 469.0 min; 9 past 240) and 33 top-offs
--         (p50 1.7, max 73.7). Back to the gate at 100%: 20. About 150 car-hours waited on need_charge in all.
--         need_service: 11 still waiting at the end, all at 100%, up to 91.1 minutes; none past 240.
--         §7b: every need_charge wait that reached 240 minutes was escalated exactly once in its stay (9 later reached a
--         charger, 4 were still waiting at the end). No car without a visit and no top-off was still waiting.
--     §8  0 releases kept a flag, of 75 gate releases; 29 transitions dropped a gate-raised flag.
--     §9  no staged car was stamped without a state change (early and mid-run probes).
--     §10 183 sessions. Before 5:00 AM, 32 to cars with no visit (78-98%) and 8 to immediate dispatches; from 5:00 AM, 59
--         immediate dispatches (16-97%), 80 standard visits (19-98%), 3 cars with no visit (89-96%), 1 technician hold.
--     §11 fast chargers 69 sessions, 74.3 of their 92.1 stall-hours (80.7%); L2 114 sessions, 261.2 hours (94.6%).
--         §11d: below 50%, 48 fast-charger sessions averaging 83.7 minutes and 70 L2 sessions averaging 263.7 (25 of them
--         immediate dispatches). §11b: 14 faults; fast chargers DCFC-08 437 min from 4:54 AM, DCFC-03 four times (81,
--         12, 26, 46 min), DCFC-05 138 from 12:43 PM, DCFC-07 51 from 1:31 PM, about 11.6 fast-charger hours; L2 seven
--         faults of 25-151 min. §11c: cars waiting on need_charge on average in each hour from 4 AM to 1 PM: 16.3, 35.8,
--         17.6, 12.4, 12.3, 13.9, 15.9, 15.8, 11.6, 11.5. Fast chargers free by the pointer while cars waited: 26, 130,
--         156, 88, 104, 136, 78, 66, 80, 84 stall-minutes per hour.
--         §11e (07:52 UTC): completed sessions by where the car went next, and the minutes from the session's end to the
--         charger's next session start:
--           dcfc, to a bay: 27 sessions, p50 2.1, mean 7.6, max 46.9   · dcfc, to staged_for_departure: 24, p50 0.9, mean 1.1, max 2.6
--           dcfc, offline (the teardown): 3, mean 1.7                    · l2, to a bay: 31, p50 0.9, mean 1.4, max 8.6
--           l2, to staged_for_departure: 42, p50 0.9, mean 1.2, max 3.9  · l2, offline: 5, mean 0.6
--         The fast chargers whose car left for a bay are the only group with a tail: that is G276.
--     §12 §12a: 8 episodes on 7 of the 10 fast chargers, 150.9 fast-charger minutes, the longest 45.7. §12b: 19 refusals
--         with the car on no stall, all from fast chargers (the car in a service, wash or detail bay); 91 with the car on
--         the stall, all charging there (85 L2, 6 DCFC).
--   Under 0547 the expectation is §12a 0, §12b 0 refusals with the car on no stall (the refusals with the car on the
--   stall remain, as the guard doing its job), and §11e's dcfc-to-a-bay row reading like the others.

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0405 §1 — the run and its scorecard ==='
SELECT r.sim_run_id, r.run_by, r.status, r.random_seed, r.sim_clock_start, r.sim_clock_current, r.tick_count,
       r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f';
SELECT public.ottoq_kpi_five('921e349c-ded0-4907-9e0b-6b288b61831f');
SELECT public.ottoq_kpi_charge_wait('921e349c-ded0-4907-9e0b-6b288b61831f');
SELECT public.ottoq_kpi_supply_gap('921e349c-ded0-4907-9e0b-6b288b61831f') - 'by_hour_ct';

-- ══ §2 RULE 9 STILL HOLDS: NO DEPARTURE WITH A SERVICE OPEN OR A CHARGE SHORT ═════════════════════════════════════════
--
--   0402 §2's query. Both must be 0.

\echo '=== 0405 §2 — departures, and any that left unfinished ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f'),
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

-- ══ §3 THE DOOR AND THE FLOOR (0544): NEITHER SHOULD EVER FIRE ════════════════════════════════════════════════════════

\echo '=== 0405 §3 — door refusals and floor rejections ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.dispatch_refused_unfinished') AS door_refusals,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed') AS tick_failures,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed' AND e.payload::text LIKE '%0544 (CLAUDE.md rule 9)%') AS floor_rejections
  FROM public.ottoq_events e WHERE e.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f';

-- ══ §4 ESCALATIONS: THE GATE'S (G269) AND THE WAITS FOR A CHARGER OR THE SERVICE BAY (0546 (d), G274) ══════════════════
--
--   Every escalation, with its reason. A gate escalation (`must_do_work_open`) is a car held for bay work or its
--   check; 0545 (a) times it from the car's last state change, so no state change should fall inside its counted
--   hold. A remedy-wait escalation (0546 (d), `waiting_for_a_charger` or `waiting_for_the_service_bay`) is a car on
--   need_charge or need_service whose last state change is 240 minutes old; (a) makes that the start of its wait, so
--   again no state change should fall inside it. The `remedy_wait` stamp holds the run and the start of the wait, so a
--   car is escalated once per wait: `per_car_and_start` must be 1 everywhere.

\echo '=== 0405 §4 — escalations, by reason, and whether the car changed state inside the counted wait ==='
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
 WHERE e.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND e.event_type = 'twin.deploy_gate_escalated'
 ORDER BY e.sim_clock_at;

-- ══ §5 G270: WHO GOT THE BAY SEATS ═══════════════════════════════════════════════════════════════════════════════════

\echo '=== 0405 §5 — needs-card seats by the seated car''s deploy time, and the gate''s holds ==='
SELECT d.enacted_action->>'purpose' AS purpose,
       CASE WHEN d.context_frame->>'minutes_to_deploy' IS NULL THEN 'no deploy time'
            WHEN (d.context_frame->>'minutes_to_deploy')::int < 0 THEN 'late'
            ELSE 'due later' END AS seated_car,
       count(*) AS seats,
       min((d.context_frame->>'minutes_to_deploy')::int) AS min_mtd, max((d.context_frame->>'minutes_to_deploy')::int) AS max_mtd
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND d.enacted_action->>'source' = 'needs_card' AND d.outcome_status = 'enacted'
 GROUP BY 1, 2 ORDER BY 1, 2;
WITH holds AS (
  SELECT e.entity_id, max((e.payload->'diff'->'config'->'to'->'deploy_gate'->>'held_min')::numeric) AS held
    FROM public.ottoq_events e
   WHERE e.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate' ? 'held_min'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate'->>'run' = e.sim_run_id::text   -- not a prior run's stamp
   GROUP BY 1)
SELECT count(*) AS cars_held, round(avg(held)) AS mean_max_hold_min, max(held) AS longest_hold_min,
       count(*) FILTER (WHERE held >= 240) AS reached_the_cap
  FROM holds;

-- ══ §6 WHAT HOLDING COSTS ═════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0405 §6 — the gate, staging and the bays ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS recheck_events,
       count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_escalated') AS escalated_to_a_person,
       max((e.payload->>'held')::int) FILTER (WHERE e.event_type = 'twin.deploy_gate_summary') AS gate_held_max,
       max((e.payload->>'overflow')::int) FILTER (WHERE e.event_type = 'twin.staging_overflow') AS staging_overflow_max
  FROM public.ottoq_events e WHERE e.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f';
SELECT (SELECT jsonb_object_agg(to_state, k) FROM (
          SELECT e.payload->'diff'->'current_state'->>'to' AS to_state, count(*) AS k
            FROM public.ottoq_events e WHERE e.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND e.event_type = 'vehicle.state_changed'
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

\echo '=== 0405 §7 — waits on need_charge and need_service, by SoC at the start and by how each ended ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f'),
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

\echo '=== 0405 §7b — the waits still open at the end by visit, and the 240-minute waits against their escalations ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f'),
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

\echo '=== 0405 §8 — gate releases that kept a flag ==='
WITH rel AS (
  SELECT e.entity_id, e.event_seq, e.payload->'diff'->'config'->'to'->>'flagged_issue_type' AS flag_type
    FROM public.ottoq_events e
   WHERE e.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'from' ? 'deploy_gate'
     AND NOT (e.payload->'diff'->'config'->'to' ? 'deploy_gate')
     AND (e.payload->'diff'->'config'->'to'->>'flagged_issue')::boolean)
SELECT flag_type, count(*) AS releases_keeping_the_flag, count(DISTINCT entity_id) AS cars,
       count(DISTINCT entity_id) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_events e3
          WHERE e3.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND e3.entity_id = rel.entity_id
            AND e3.event_type = 'vehicle.state_changed' AND e3.event_seq > rel.event_seq
            AND e3.payload->'diff'->'current_state'->>'to' = 'in_service_bay')) AS later_in_service_bay
  FROM rel GROUP BY flag_type ORDER BY flag_type;

-- ══ §9 LIVE PROBE: NO STAGED CAR IS RE-STAMPED WITHOUT A STATE CHANGE (G272) ═══════════════════════════════════════════
--
--   0403 §9's probe. Under 0546 (a), STEP 0 stamps only a car it moves into staging, which is a state change, so no
--   staged car should appear. The deployed telemetry still stamps deployed cars with each SoC drain (0546 §4: measured,
--   not changed), so deployed rows are expected. Run while the run is live.

\echo '=== 0405 §9 — cars stamped this tick with no state change ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND status = 'running')
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
-- READ (2026-09-28 08:30 UTC, 3:30 AM CT; tick 122, sim 5:51 AM CT): **no staged car was stamped that tick without a
--   state change.** 14 deployed cars were (the deployed telemetry, 0546 §4), as on dbdffd5c.

--   §9b, the same moment from the queue's side: every car on need_charge with the wait the charge cursor reads (sim now
--   minus `last_state_change`), by whether it has a visit and by its charge.

\echo '=== 0405 §9b — the charge queue and the wait each car reads ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f')
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
-- READ (08:30 UTC; tick 125, sim 5:53 AM CT): 29 cars on need_charge, **none reading a wait of 0**: 17 visit cars below
--   80% (12-46%) waiting 12.5-59.0 minutes, 9 visit cars at 88-96% at 60.2, and 3 cars with no visit at 89-96% at
--   35.4-57.6.

-- ══ §10 G271: WHO THE CHARGERS WENT TO, BY WHETHER THE CAR HAD A VISIT ══════════════════════════════════════════════════
--
--   0403 §10's query. On 4acf0b1d no car without a visit got a charger after 5:00 AM. Under 0546 (c) they compete on
--   their ratio, and a top-off's ratio is high, so they should appear from 5:00 AM on.

\echo '=== 0405 §10 — charge sessions by start time and by whether the car had a visit ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f'),
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

\echo '=== 0405 §11 — charger use by kind ==='
WITH r AS (SELECT sim_run_id, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f'),
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

\echo '=== 0405 §11d — sessions by charger kind and by charge at the start ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f'),
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

\echo '=== 0405 §11b — every charger fault, its repair time, and how long its charger stood before its next car ==='
WITH f AS (
  SELECT e.sim_clock_at AS at, o.stall_id, e.payload->>'reason' AS reason, (e.payload->>'repair_minutes')::numeric AS repair_min
    FROM public.ottoq_events e JOIN public.ocpp_sessions o ON o.id::text = e.entity_id::text
   WHERE e.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND e.event_type = 'charge.session_faulted')
SELECT s.stall_code, f.at AT TIME ZONE 'America/Chicago' AS fault_ct, f.reason, f.repair_min,
       round(extract(epoch FROM ((SELECT min(o2.started_at) FROM public.ocpp_sessions o2
                                   WHERE o2.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND o2.stall_id = f.stall_id AND o2.started_at > f.at)
                                 - f.at))::numeric / 60, 1) AS stood_until_next_car_min
  FROM f JOIN public.stalls s ON s.id = f.stall_id ORDER BY f.at;

\echo '=== 0405 §11c — per hour: cars waiting on need_charge, and chargers free by the stall pointer ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f'),
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

\echo '=== 0405 §11e — charger turnover: from a session''s end to the charger''s next car, by where the car went ==='
--   Completed sessions only (a faulted session's gap is its repair, §11b). `car_went` is the car's first state after
--   the session other than holding, waiting or charging. Under 0547 a fast charger whose car left for a bay should take
--   its next car as soon as one whose car left for departure does.
WITH r AS MATERIALIZED (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f'),
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

-- ══ §12 G276 UNDER 0547: A CHARGER IS FREE ONCE ITS CAR HAS LEFT IT FOR A BAY ═══════════════════════════════════════
--
--   0404 §12's queries. On dbdffd5c a fast charger kept its car's pointer after the car went on to a bay, because the
--   guard read the car's state and not where it was (§0 §12). Under 0547 §12a must read no episode on any charger, and
--   §12b no refusal with the car on no stall or on another stall. The refusals with the car on this stall are the guard
--   doing its job and remain. §12c is the live census G121 was found with, for the probes while the run is live.

\echo '=== 0405 §12a — charger time stuck with a pointer to a car that left, from the stall stream ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f'),
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

\echo '=== 0405 §12b — the guard''s refusals, by where the car was when it asked ==='
WITH a AS (
  SELECT a.vehicle_id, (a.payload->>'from_stall')::uuid AS from_stall, (a.payload->>'requested_at_sim')::timestamptz AS at_sim,
         a.payload->>'state' AS state, s.stall_type::text AS from_kind, a.status
    FROM public.ottoq_ops_approvals a JOIN public.stalls s ON s.id = (a.payload->>'from_stall')::uuid
   WHERE a.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND a.payload->>'reason' = 'automated_reassignment'),
pos AS (
  SELECT a.*,
         (SELECT e.payload->'diff'->'current_stall_id'->>'to' FROM public.ottoq_events e
           WHERE e.sim_run_id = '921e349c-ded0-4907-9e0b-6b288b61831f' AND e.entity_id = a.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_stall_id' AND e.sim_clock_at <= a.at_sim
           ORDER BY e.event_seq DESC LIMIT 1) AS car_stall_at_request
    FROM a)
SELECT from_kind, state, status,
       CASE WHEN car_stall_at_request IS NULL THEN 'car on no stall' WHEN car_stall_at_request = from_stall::text THEN 'car on this stall'
            ELSE 'car on another stall' END AS car_position,
       count(*) AS n
  FROM pos GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
-- READ early (08:31 UTC; through sim ~5:55 AM CT): 20 refusals, **every one with the car charging on the stall** (19 L2,
--   1 DCFC); none with the car on no stall or on another stall.

\echo '=== 0405 §12c — live: a stall that reads available with a pointer set, and where its car is ==='
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
-- READ (08:30 UTC; sim 5:51 AM CT): **no stall read available with a pointer set.**
