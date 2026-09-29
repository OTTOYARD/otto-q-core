-- 0412  **The charger outage a fifth time, under 0558: a faulted car's repair goes first in its plan, and no charger is
--        held for it before the repair.** (G292; re-measured: G290, G291, G289, G279, G282, G283, G284, G286; G293 open)
--
--       Written on 2026-09-28 (CT). Read-only. The run is 4b0999db-a9ef-4b35-b3e2-c985d1a259f2: busy_day at 8x under 0558 (applied
--       6:55 PM CT, ledger 20260928235524), on 0405bf42's seed (1092115219118377967), sim day and start minute (Monday 2026-09-28, 4:26 AM
--       CT). I started it at 00:27 UTC (7:27 PM CT), with no certification in flight and the canon at 9 of 9 under
--       the 0558 floor (verdicts 612-620). It repeats 0409's, 0410's and 0411's stress test in the twin (rule 10).
--
--       **The designed difference, as in 0408-0411.** A one-shot pg_cron job (`ottoq_0412_inject_dcfc_outage_once`,
--       job 782) takes three DC fast chargers down for 120 sim-minutes through the cockpit's door,
--       `ottoq_twin_inject_charger_fault`, once the run passes sim 7:39 AM CT. It records what it did on the run's
--       payload (`stress_injection_0412`, §17a) and unschedules itself.
--
--       **A second designed difference: the vehicle-fault rate.** 0411's one vehicle fault came at 4:44 AM. By sim 5:29 AM
--       this run had none, and at the operating assumption (0.00088 per eligible vehicle-hour, ~1.5 faults a sim-day
--       fleet-wide) the rest of the day expected about 0.7, so G292 might not have been exercised at all. At sim 5:29:48 AM
--       (00:35 UTC, 7:35 PM CT) I set the run-scoped dial `vehicle_fault_rate_per_eligible_vehicle_hour` to 0.004 through
--       `ottoq_policy_set('run', ..., 'research_wing_stress_0412')` (its catalog row names a higher rate a legitimate stress
--       setting) and recorded it on the run's payload (`stress_vehicle_fault_rate_0412`). It is read at this run's scope
--       only: no other run, dial arm or canon column sees it. I expected about three faults over the remaining eight
--       sim-hours, counting every car at the depot; but the handler rolls only for a car charging, in a bay, holding after
--       its charge or staged (`twin.ottoq_sim_vehicle_exception_handler`), not for the ~30 waiting at the gate, and by sim
--       8:38 AM none had faulted (44 cars eligible at that moment). At sim 8:38:29 AM (00:59 UTC, 7:59 PM CT) I raised it
--       to 0.01 the same way, recorded under the same payload key (`raised`): about two faults expected over the rest of
--       the run. Each adds a repair to the two service bays, so §7, §15 and §26 read a heavier service-bay load than
--       0411's, and §1's scorecard differs from 0411's on that account too.
--
--       **What it tests.** The finding 0411 left open, against the fix written for it:
--         - G292 (0558): a faulted car's plan puts its repair before every charge and bay leg (§28a); no charger is booked
--           for it while its fault is open, and one booked before the fault is released at step (6)'s next pass (§28b);
--           its repair takes the first window a service bay has free, and it charges once repaired (§28c); step (6) says
--           what it released and re-planned (§28d);
--       and, as before, G290 (§2b, §27), G291 (§27b), G289 (§26), G279 (§16, §22), G282 (§18, §23), G283 (§19c, §24),
--       G284 (§25), G286 (§21), rule 9 (§2, §16) and the outage itself (§17). G293 (the in-kernel L2 optimizer seats gate
--       cars by lowest charge, outside the banked order the cursor serves) is open and unchanged here; §22 counts it again.
--
--       **Not a paired test.** 0408's caveat holds. The runs share the seed, but a charger's fault card is keyed on the
--       car, the stall and the minute its session starts (0058), and a live run's ticks follow the wall clock. The twin's
--       vehicle faults are drawn per car and minute too, so which cars fault, and when, is this run's own; a fault tests
--       G292 only if it falls on a car with a charge still to do. cdf87081 was purged when this run started; the figures §0
--       quotes from it are 0411's end reads. A difference from it is read against §11b first.

-- ══ §0 BEFORE: cdf87081 (0411), THE SAME DAY AND THE SAME OUTAGE UNDER 0555, 0556 AND 0557 ════════════════════════════
--
--     §1  stopped by the governor at sim 1:30 PM after 1,034 ticks. KPI 1 141.85 · KPI 2 4.03 · peak site kW 1,312.8 ·
--         KPI 4 1.218 · KPI 5 p50 49, p95 311.5 min · returns unserved 40. Charge wait (visits) p50 53.5, p95 283.3; 138 of
--         199 charged, 61 still waiting at the end. Supply gap 59.2% of 342.7 demand car-hours unmet.
--     §2  123 departures, 0 below 99%, 0 with an atom open.  §2b 0 with a vehicle fault open.
--     §3  0 door refusals, 0 tick failures, 0 floor rejections.
--     §4  45 escalations: 44 waiting for a charger, 1 waiting for the service bay (Zoox-AV-080, G292).
--     §11 fast chargers 69.0% of nameplate time, L2 88.8%; 18 twin charger faults and the 3 injected.
--     §15 at work 140.0 car-hours (13.3% of fleet time); waiting for a charger 46.3%; staged need_service 31.5 car-hours,
--         none of it for the gate's flag.
--     §16 21 charger faults, none left short.  §22 later arrivals charged first 129 times: 95 immediate dispatches, 19
--         reservations honoured, 11 seated by the in-kernel L2 optimizer (G293), 4 through the cursor.
--     §18 / §23 12 gate stays below target reached 240 minutes; all 12 told.
--     §19c 77 refused washes and 31 refused deep cleans; 39 and 16 had a bay free on the calendar (the G283 remainder).
--     §21 80 bay visits, all 80 in a bay.  §26a 24 service-bay visits, none that credited nothing.
--     §27 one vehicle fault: Zoox-AV-080, a `sensor_suite_fault` (critical, not immobilizing) at 4:44 AM while staged.
--         Step (6) routed it to the service bay at 5:09 AM with a plan that put an 8-hour L2 charge first and the repair
--         last (booked for 1:24 PM). 0557 refused the charge until the repair, so neither could start: open 526 minutes,
--         0 charges, 0 departures, never repaired; 12 `amend_plan` slid the plan, and an L2 stood idle, booked for it,
--         from 6:20 AM (G292).
--   Must read here:
--     - §28a: every plan a faulted car is given inside its fault spell puts the repair before every charge and bay leg;
--     - §28b: no charge booking made inside a fault spell, and none held into one past step (6)'s next pass;
--     - §28c: the repair booked at the first window a service bay had free, the car repaired, then charged;
--     - §2 0 and 0, §2b 0; §27b 0 departures and 0 charges started inside a spell, every spell closed by a repair or open
--       at the end with its car in the depot;
--     - §3 0, 0 and 0; §16 0 left short; §21 0 in no bay; §26a 0 visits that credited nothing.

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The scorecard, for the shape of the day rather than a comparison: what was demanded, what was deployed, and where
--   cars waited.

\echo '=== 0412 §1 — the run and its scorecard ==='
SELECT r.sim_run_id, r.run_by, r.status, r.random_seed, r.sim_clock_start, r.sim_clock_current, r.tick_count,
       r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2';
SELECT public.ottoq_kpi_five('4b0999db-a9ef-4b35-b3e2-c985d1a259f2');
SELECT public.ottoq_kpi_charge_wait('4b0999db-a9ef-4b35-b3e2-c985d1a259f2');
SELECT public.ottoq_kpi_supply_gap('4b0999db-a9ef-4b35-b3e2-c985d1a259f2') - 'by_hour_ct';
-- READ: pending.

-- ══ §2 RULE 9 STILL HOLDS: NO DEPARTURE WITH A SERVICE OPEN OR A CHARGE SHORT ═════════════════════════════════════════
--
--   0402 §2's query. Both must be 0.

\echo '=== 0412 §2 — departures, and any that left unfinished ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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

-- §2b G290 UNDER 0555: A DEPARTURE WITH A VEHICLE FAULT OPEN
--
--   §2 reads the card's atoms and the charge, and a vehicle fault is in neither: it lives in `config.exception`, which
--   0555 put in the departure test (`public.ottoq_vehicle_fault_open`). Per departure, the car's config as the signed
--   stream last wrote it at or before the moment it left. `left_with_fault_open` must be 0 (0410: 1, Waymo-AV-011).

\echo '=== 0412 §2b — departures with a vehicle fault open (G290) ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
dep AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS left_at, e.event_seq AS seq
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' IN ('en_route_to_deployment', 'deployed')
     AND e.payload->'diff'->'current_state'->>'from' NOT IN ('en_route_to_deployment', 'deployed')
     AND e.sim_clock_at > run.t0),
cfg AS (
  SELECT d.*,
         (SELECT e.payload->'diff'->'config'->'to' FROM public.ottoq_events e, run
           WHERE e.sim_run_id = run.id AND e.entity_id = d.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'config' AND e.event_seq <= d.seq
           ORDER BY e.event_seq DESC LIMIT 1) AS config_at
    FROM dep d)
SELECT count(*) AS departures,
       count(*) FILTER (WHERE public.ottoq_vehicle_fault_open(cfg.config_at)) AS left_with_fault_open,
       string_agg(v.display_name || ' at ' || to_char(cfg.left_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') || ' ('
                  || (cfg.config_at->'exception'->>'fault_class') || ', ' || (cfg.config_at->'exception'->>'status') || ')',
                  '; ' ORDER BY cfg.left_at) FILTER (WHERE public.ottoq_vehicle_fault_open(cfg.config_at)) AS which
  FROM cfg JOIN public.vehicles v ON v.id = cfg.vehicle_id;
-- READ: pending.

-- ══ §3 THE DOOR AND THE FLOOR (0544): NEITHER SHOULD EVER FIRE ════════════════════════════════════════════════════════

\echo '=== 0412 §3 — door refusals and floor rejections ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.dispatch_refused_unfinished') AS door_refusals,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed') AS tick_failures,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed' AND e.payload::text LIKE '%0544 (CLAUDE.md rule 9)%') AS floor_rejections
  FROM public.ottoq_events e WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2';
-- READ: pending.

-- ══ §4 ESCALATIONS: THE GATE'S (G269) AND THE WAITS FOR A CHARGER OR THE SERVICE BAY (0546 (d), G274) ══════════════════
--
--   Every escalation, with its reason. A gate escalation (`must_do_work_open`) is a car held for bay work or its
--   check; 0545 (a) times it from the car's last state change, so no state change should fall inside its counted
--   hold. A remedy-wait escalation (0546 (d), `waiting_for_a_charger` or `waiting_for_the_service_bay`) is a car on
--   need_charge or need_service whose last state change is 240 minutes old; (a) makes that the start of its wait, so
--   again no state change should fall inside it. The `remedy_wait` stamp holds the run and the start of the wait, so a
--   car is escalated once per wait: `per_car_and_start` must be 1 everywhere.

\echo '=== 0412 §4 — escalations, by reason, and whether the car changed state inside the counted wait ==='
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
 WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.event_type = 'twin.deploy_gate_escalated'
 ORDER BY e.sim_clock_at;
-- READ: pending.

-- ══ §5 G270: WHO GOT THE BAY SEATS ═══════════════════════════════════════════════════════════════════════════════════

\echo '=== 0412 §5 — needs-card seats by the seated car''s deploy time, and the gate''s holds ==='
SELECT d.enacted_action->>'purpose' AS purpose,
       CASE WHEN d.context_frame->>'minutes_to_deploy' IS NULL THEN 'no deploy time'
            WHEN (d.context_frame->>'minutes_to_deploy')::int < 0 THEN 'late'
            ELSE 'due later' END AS seated_car,
       count(*) AS seats,
       min((d.context_frame->>'minutes_to_deploy')::int) AS min_mtd, max((d.context_frame->>'minutes_to_deploy')::int) AS max_mtd
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND d.enacted_action->>'source' = 'needs_card' AND d.outcome_status = 'enacted'
 GROUP BY 1, 2 ORDER BY 1, 2;
WITH holds AS (
  SELECT e.entity_id, max((e.payload->'diff'->'config'->'to'->'deploy_gate'->>'held_min')::numeric) AS held
    FROM public.ottoq_events e
   WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate' ? 'held_min'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate'->>'run' = e.sim_run_id::text   -- not a prior run's stamp
   GROUP BY 1)
SELECT count(*) AS cars_held, round(avg(held)) AS mean_max_hold_min, max(held) AS longest_hold_min,
       count(*) FILTER (WHERE held >= 240) AS reached_the_cap
  FROM holds;
-- READ: pending.

-- ══ §6 WHAT HOLDING COSTS ═════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0412 §6 — the gate, staging and the bays ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS recheck_events,
       count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_escalated') AS escalated_to_a_person,
       max((e.payload->>'held')::int) FILTER (WHERE e.event_type = 'twin.deploy_gate_summary') AS gate_held_max,
       max((e.payload->>'overflow')::int) FILTER (WHERE e.event_type = 'twin.staging_overflow') AS staging_overflow_max
  FROM public.ottoq_events e WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2';
SELECT (SELECT jsonb_object_agg(to_state, k) FROM (
          SELECT e.payload->'diff'->'current_state'->>'to' AS to_state, count(*) AS k
            FROM public.ottoq_events e WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
           GROUP BY 1) q) AS bay_entries;
-- READ: pending.

-- ══ §7 G271: NO CAR STARVES WAITING FOR A CHARGER OR THE SERVICE BAY ═════════════════════════════════════════════════
--
--   0403 §7's waits, widened to need_service, with the car-hours and the waits that reached 240 minutes. A wait starts
--   where a staged car's step becomes need_charge (or need_service) and ends at its next change of state or step. The
--   teardown's `offline` at the run's last sim minute is not an end. The SoC at the start is the stream's last SoC for
--   the car at or before it. `visit` is the urgency of the car's latest visit at the wait's start, or 'no visit'.
--   Under 0546 (a) and (c) no group should be passed over all day: a boot car with no visit now competes on its ratio,
--   and a waiting car's ratio rises with its wait.

\echo '=== 0412 §7 — waits on need_charge and need_service, by SoC at the start and by how each ended ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

--   The same waits still open at the teardown, by whether the car had a visit (0546 (c)), and whether each wait that
--   reached 240 minutes was escalated once in its stay (0546 (d)). A stay is the car's time in staged_awaiting_service
--   since its last state change, which is what (d) times; one stay can hold more than one wait.

\echo '=== 0412 §7b — the waits still open at the end by visit, and the 240-minute waits against their escalations ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

-- ══ §8 G273: NO RELEASE KEEPS A FLAG THE GATE RAISED ═══════════════════════════════════════════════════════════════════
--
--   0403 §8's query. Under 0546 (b) a release drops `deploy_gate_stuck` and `deploy_gate_hard_cap` with its stamp, so
--   those two rows must read 0. A flag raised by anything else is kept, as before, and may appear.

\echo '=== 0412 §8 — gate releases that kept a flag ==='
WITH rel AS (
  SELECT e.entity_id, e.event_seq, e.payload->'diff'->'config'->'to'->>'flagged_issue_type' AS flag_type
    FROM public.ottoq_events e
   WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'from' ? 'deploy_gate'
     AND NOT (e.payload->'diff'->'config'->'to' ? 'deploy_gate')
     AND (e.payload->'diff'->'config'->'to'->>'flagged_issue')::boolean)
SELECT flag_type, count(*) AS releases_keeping_the_flag, count(DISTINCT entity_id) AS cars,
       count(DISTINCT entity_id) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_events e3
          WHERE e3.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e3.entity_id = rel.entity_id
            AND e3.event_type = 'vehicle.state_changed' AND e3.event_seq > rel.event_seq
            AND e3.payload->'diff'->'current_state'->>'to' = 'in_service_bay')) AS later_in_service_bay
  FROM rel GROUP BY flag_type ORDER BY flag_type;
-- READ: pending.

-- ══ §9 LIVE PROBE: NO STAGED CAR IS RE-STAMPED WITHOUT A STATE CHANGE (G272) ═══════════════════════════════════════════
--
--   0403 §9's probe. Under 0546 (a), STEP 0 stamps only a car it moves into staging, which is a state change, so no
--   staged car should appear. The deployed telemetry still stamps deployed cars with each SoC drain (0546 §4: measured,
--   not changed), so deployed rows are expected. Run while the run is live.

\echo '=== 0412 §9 — cars stamped this tick with no state change ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND status = 'running')
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
-- READ: pending.

--   §9b, the same moment from the queue's side: every car on need_charge with the wait the charge cursor reads (sim now
--   minus `last_state_change`), by whether it has a visit and by its charge.

\echo '=== 0412 §9b — the charge queue and the wait each car reads ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2')
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
-- READ: pending.

-- ══ §10 G271: WHO THE CHARGERS WENT TO, BY WHETHER THE CAR HAD A VISIT ══════════════════════════════════════════════════
--
--   0403 §10's query. On 4acf0b1d no car without a visit got a charger after 5:00 AM. Under 0546 (c) they compete on
--   their ratio, and a top-off's ratio is high, so they should appear from 5:00 AM on.

\echo '=== 0412 §10 — charge sessions by start time and by whether the car had a visit ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
s AS (
  SELECT o.vehicle_id, o.started_at, o.soc_start,
         (SELECT vn.urgency FROM public.ottoq_visit_needs vn
           WHERE vn.vehicle_id = o.vehicle_id AND vn.sim_run_id = r.sim_run_id AND vn.arrived_at <= o.started_at
           ORDER BY vn.created_at DESC LIMIT 1) AS urgency
    FROM public.ocpp_sessions o, r WHERE o.sim_run_id = r.sim_run_id)
SELECT CASE WHEN started_at < timestamptz '2026-09-28 10:00:00+00' THEN 'before 5:00 AM CT' ELSE 'from 5:00 AM CT' END AS started,
       COALESCE(urgency, 'no visit') AS car, count(*) AS sessions, min(soc_start) AS min_soc, max(soc_start) AS max_soc
  FROM s GROUP BY 1, 2 ORDER BY 1, 2;
-- READ: pending.

-- ══ §11 THE CHARGERS: HOW BUSY, HOW MANY FAULTED, AND WHAT WAS FREE WHILE CARS WAITED ═══════════════════════════════════
--
--   Session hours against nameplate time by charger kind; every fault with its repair time and how long its charger
--   stood before its next car; and, per hour, the cars waiting on need_charge beside the chargers free by the stall
--   pointer. A charger free while cars wait is either faulted (capacity lost to faults), between two cars (turnover),
--   or a gap in the schedule, which is the only one of the three that orchestration alone can close.

\echo '=== 0412 §11 — charger use by kind ==='
WITH r AS (SELECT sim_run_id, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

\echo '=== 0412 §11d — sessions by charger kind and by charge at the start ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

\echo '=== 0412 §11b — every charger fault, its repair time, and how long its charger stood before its next car ==='
WITH f AS (
  SELECT e.sim_clock_at AS at, o.stall_id, e.payload->>'reason' AS reason, (e.payload->>'repair_minutes')::numeric AS repair_min
    FROM public.ottoq_events e JOIN public.ocpp_sessions o ON o.id::text = e.entity_id::text
   WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.event_type = 'charge.session_faulted')
SELECT s.stall_code, f.at AT TIME ZONE 'America/Chicago' AS fault_ct, f.reason, f.repair_min,
       round(extract(epoch FROM ((SELECT min(o2.started_at) FROM public.ocpp_sessions o2
                                   WHERE o2.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND o2.stall_id = f.stall_id AND o2.started_at > f.at)
                                 - f.at))::numeric / 60, 1) AS stood_until_next_car_min
  FROM f JOIN public.stalls s ON s.id = f.stall_id ORDER BY f.at;
-- READ: pending.

--   §11c counts cars at the gate too (`avg_at_gate`): the charge cursor reads them as well as staged cars on need_charge
--   (§15). A charger that reads free by the pointer may be faulted: §11b lists the faults.
\echo '=== 0412 §11c — per hour: cars waiting on need_charge or at the gate, and chargers free by the stall pointer ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

\echo '=== 0412 §11e — charger turnover: from a session''s end to the charger''s next car, by where the car went ==='
--   Completed sessions only (a faulted session's gap is its repair, §11b). `car_went` is the car's first state after
--   the session other than holding, waiting or charging. Since 0547 a fast charger whose car left for a bay takes its
--   next car as soon as one whose car left for departure does (921e349c: p50 1.3, mean 2.1, max 14.4).
WITH r AS MATERIALIZED (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

-- ══ §12 G276 STAYS FIXED: A CHARGER IS FREE ONCE ITS CAR HAS LEFT IT FOR A BAY ══════════════════════════════════════
--
--   0405 §12's queries, kept as a regression check. On 921e349c, ae0597b7 and 0405bf42, §12a read no episode and §12b read
--   no refusal with the car on no stall. Both must read 0 on a new day too. Refusals with the car on this stall are
--   the guard doing its job, and they remain. §12c is the live census G121 was found with, for probes while the run is live.

\echo '=== 0412 §12a — charger time stuck with a pointer to a car that left, from the stall stream ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

\echo '=== 0412 §12b — the guard''s refusals, by where the car was when it asked ==='
WITH a AS (
  SELECT a.vehicle_id, (a.payload->>'from_stall')::uuid AS from_stall, (a.payload->>'requested_at_sim')::timestamptz AS at_sim,
         a.payload->>'state' AS state, s.stall_type::text AS from_kind, a.status
    FROM public.ottoq_ops_approvals a JOIN public.stalls s ON s.id = (a.payload->>'from_stall')::uuid
   WHERE a.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND a.payload->>'reason' = 'automated_reassignment'),
pos AS (
  SELECT a.*,
         (SELECT e.payload->'diff'->'current_stall_id'->>'to' FROM public.ottoq_events e
           WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.entity_id = a.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_stall_id' AND e.sim_clock_at <= a.at_sim
           ORDER BY e.event_seq DESC LIMIT 1) AS car_stall_at_request
    FROM a)
SELECT from_kind, state, status,
       CASE WHEN car_stall_at_request IS NULL THEN 'car on no stall' WHEN car_stall_at_request = from_stall::text THEN 'car on this stall'
            ELSE 'car on another stall' END AS car_position,
       count(*) AS n
  FROM pos GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
-- READ: pending.

\echo '=== 0412 §12c — live: a stall that reads available with a pointer set, and where its car is ==='
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
-- READ: pending.

-- ══ §13 G278 STAYS FIXED: NO CAR HOLDS A BAY BEFORE ITS BOOKING ═══════════════════════════════════════════════════
--
--   0406 §13's queries. On 921e349c, before 0549, 4 early entries held the wash bays for 465 minutes. On ae0597b7, under
--   0549:
--     - §13a read no entry more than 5 minutes before its booking;
--     - §13b had nothing to list (the one early reservation, Waymo-AV-020's, had been moved to start when the car went in);
--     - §13c read no booking longer than its service and no car past its booking.
--   The same must hold here. §13c shows a stretched booking as a long one; a car that stays past its booking shows in the
--   last column.

\echo '=== 0412 §13a — bay entries against their bookings: how early the car went in, and the bay-minutes held before the window ==='
WITH c AS (
  SELECT c.vehicle_id, c.command_type, c.payload->>'purpose' AS purpose, c.issued_at,
         b.during, s.stall_type::text AS bay
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
    JOIN public.stalls s ON s.id = b.stall_id
   WHERE c.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed')
SELECT purpose, count(*) AS entries,
       count(*) FILTER (WHERE lower(during) > issued_at + interval '5 minutes') AS entered_over_5_min_early,
       round(max(extract(epoch FROM lower(during) - issued_at) / 60)::numeric, 1) AS max_early_min,
       round(sum(GREATEST(extract(epoch FROM lower(during) - issued_at), 0) / 60) FILTER (WHERE lower(during) > issued_at + interval '5 minutes')::numeric, 1) AS bay_minutes_held_before_the_window
  FROM c GROUP BY 1 ORDER BY 1;
-- READ: pending.

\echo '=== 0412 §13b — the early entries, and the other cars'' bookings on the same bay while the early car sat there ==='
WITH c AS (
  SELECT c.vehicle_id, c.payload->>'purpose' AS purpose, c.issued_at, b.stall_id, b.during, s.stall_code
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
    JOIN public.stalls s ON s.id = b.stall_id
   WHERE c.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed' AND lower(b.during) > c.issued_at + interval '5 minutes'),
x AS (
  SELECT c.*,
         (SELECT min(e.sim_clock_at) FROM public.ottoq_events e
           WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.entity_id = c.vehicle_id
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
         WHERE b2.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND b2.stall_id = x.stall_id
           AND b2.vehicle_id IS DISTINCT FROM x.vehicle_id
           AND b2.during && tstzrange(x.issued_at, COALESCE(x.left_bay_at, upper(x.during)))) AS other_bookings_while_it_sat
  FROM x JOIN public.vehicles v ON v.id = x.vehicle_id
 ORDER BY x.issued_at;
-- READ: pending.

\echo '=== 0412 §13c — every bay command''s booking and time in the bay, by purpose (a stretched booking shows as a long one) ==='
WITH c AS (
  SELECT c.vehicle_id, c.payload->>'purpose' AS purpose, c.issued_at, b.during
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
   WHERE c.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed'),
x AS (
  SELECT c.*,
         extract(epoch FROM upper(c.during) - lower(c.during)) / 60 AS booked_min,
         extract(epoch FROM (SELECT min(e.sim_clock_at) FROM public.ottoq_events e
                              WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.entity_id = c.vehicle_id
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
-- READ: pending.

-- ══ §14 G195 RE-MEASURED: PARKING HOLDS THAT OUTLIVE THEIR CAR, AND WHETHER STAGING EVER BINDS ═══════════════════════
--
--   G195's open half is the parking holds (`temp_hold`, `perimeter_hold`) that stay on the calendar after their car has
--   left the stall; its remedy, the departure sweep (`space_departure_release_enabled`), is off. It costs nothing while
--   staging has room, so §14a counts the leak (0372 §2(c)'s query) and §14b whether staging ever came near full, every
--   ten sim-minutes, from the calendar: stalls with a live booking, and among them stalls whose booked car had left.

\echo '=== 0412 §14a — parking holds that outlived their car, over the whole run (0372 §2(c)) ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

\echo '=== 0412 §14b — staging stalls on the calendar every ten sim-minutes, and how many of them held a car that had left ==='
WITH r AS MATERIALIZED (SELECT sim_run_id AS run, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
stg AS MATERIALIZED (SELECT id FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type::text = 'staging'),
lv AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, (e.payload->'diff'->'current_stall_id'->>'from')::uuid AS stall_id, e.sim_clock_at AS at
    FROM public.ottoq_events e, r
   WHERE e.sim_run_id = r.run AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_stall_id'
     AND e.payload->'diff'->'current_stall_id'->>'from' IS NOT NULL),
b AS MATERIALIZED (
  SELECT b.booking_id, b.stall_id, b.vehicle_id, lower(b.during) AS lo,
         LEAST(upper(b.during), COALESCE(b.released_at, 'infinity'::timestamptz)) AS hi
    FROM public.ottoq_stall_bookings b JOIN r ON b.sim_run_id = r.run
   WHERE b.stall_id IN (SELECT id FROM stg) AND b.state IN ('held', 'active', 'done', 'interrupted')),
bl AS MATERIALIZED (
  SELECT b.*, (SELECT min(lv.at) FROM lv WHERE lv.vehicle_id = b.vehicle_id AND lv.stall_id = b.stall_id AND lv.at > b.lo) AS left_at
    FROM b),
t AS (SELECT generate_series((SELECT t0 FROM r), (SELECT t1 FROM r), interval '10 minutes') AS at),
c AS (
  SELECT t.at,
         count(DISTINCT bl.stall_id) AS stalls_on_calendar,
         count(DISTINCT bl.stall_id) FILTER (WHERE bl.left_at IS NOT NULL AND bl.left_at <= t.at) AS leaked
    FROM t JOIN bl ON bl.lo <= t.at AND bl.hi > t.at GROUP BY t.at)
SELECT (SELECT count(*) FROM stg) AS staging_stalls, max(stalls_on_calendar) AS peak_on_calendar,
       round(avg(stalls_on_calendar), 1) AS mean_on_calendar, max(leaked) AS peak_leaked, round(avg(leaked), 1) AS mean_leaked
  FROM c;
-- READ: pending.

-- ══ §15 WHERE THE FLEET'S HOURS WENT ═══════════════════════════════════════════════════════════════════════════════════
--
--   0407 §15's query. Each car's time from the run's first minute to its last tick, split by what it was doing, taken
--   from the state and step each `vehicle.state_changed` event leaves it in. A staged car is split by its step. A car at
--   the gate has its own row. The decide tick's charge cursor reads cars at the gate as well as staged cars on need_charge,
--   so a car below its target at the gate is waiting for a charger too. §7 counts only the staged waits, so the
--   time spent waiting for a charger is roughly rows c and d together. The boot puts every car into a state at the first
--   minute, so the first half hour carries the boot's backlog.

\echo '=== 0412 §15 — car-hours by what the car was doing, over the run ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

-- ══ §16 RULE 9 AT A CHARGER FAULT: EVERY INTERRUPTED CAR IS RE-QUEUED TO FINISH ═════════════════════════════════════
--
--   0407 §16's query. A charger fault is one of the two reasons rule 9 lets a charge end short, and only if the car is
--   re-queued to finish. For every faulted session this query takes the car's charge at the fault, its next session
--   (when, on what kind of charger, and how it ended) and its next dispatch. `left without resuming` is allowed only for
--   a car already at 99% or more at the fault (the charge rule treats the target minus 1 as charged, 0493). The last
--   column must be 0. On 0405bf42, the same day without the outage, it read 0 over 19 faults (§0).

\echo '=== 0412 §16 — every charger fault: what the car did next, and at what charge it left ==='
WITH r AS (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.


--   §16b, the same faults with the wait each car had behind it when the faulted session started. Before 0551 the charge
--   cursor measured a car's wait from its last state change, and a fault moves the car from charging back to staging, so
--   the fault erased that wait (G279). Under 0551 the wait is banked (`config.charge_wait`) and the cursor reads it, so
--   `waited_after_min` should be short for a car that had waited long before its fault. §22 counts who went ahead.

\echo '=== 0412 §16b — per fault: the wait before the faulted session, the charge it got, and the wait after ==='
WITH r AS (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.

-- ══ §17 THE OUTAGE: A FAULT FROM THE COCKPIT STOPS THE CHARGE NOW (0550, G281) ═══════════════════════════════════════
--
--   §17a reads the injection job's receipt from the run's payload: per charger, the sessions the door stopped and the cars its report
--   replanned. §17b follows each injected charger:
--     - its session's end, and where its car went;
--     - when the car charged again, and how that ended;
--     - the charger and its stall now;
--     - when the next car plugged in (`out_of_service_min`).
--   Under 0550 every row must read:
--     - the session `faulted` with `fault.operator_injected`;
--     - the car re-queued (to staging), or held on the robot at 95% and above;
--     - the charger `Faulted` and its stall `maintenance` until the repair;
--     - `out_of_service_min` at least the declared repair.

\echo '=== 0412 §17a — the injection''s receipt, from the run''s payload ==='
SELECT r->>'stall_code' AS charger, (r->>'ok')::boolean AS ok, (r->>'sessions_stopped')::int AS sessions_stopped,
       jsonb_array_length(COALESCE(r->'report'->'vehicles', '[]'::jsonb)) AS cars_replanned,
       to_char((r->>'faulted_at_sim')::timestamptz AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS faulted_ct,
       to_char((r->>'recovers_at_sim')::timestamptz AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS recovers_ct,
       (r->>'repair_minutes')::numeric AS repair_min,
       (sr.payload->'stress_injection_0412'->>'at_real')::timestamptz AS injected_at_real_utc
  FROM public.ottoq_sim_runs sr
  CROSS JOIN LATERAL jsonb_array_elements(sr.payload->'stress_injection_0412'->'results') r
 WHERE sr.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'
 ORDER BY 1;
-- READ: pending.

\echo '=== 0412 §17b — per injected charger: the stopped session, where its car went, and the charger''s outage ==='
WITH run AS MATERIALIZED (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1, r.payload->'stress_injection_0412' AS inj
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
inj AS (
  SELECT st.id AS stall_id, st.stall_code, (r->>'charger_id')::uuid AS charger_id,
         (r->>'faulted_at_sim')::timestamptz AS fault_at, (r->>'recovers_at_sim')::timestamptz AS recovers_at,
         (r->>'sessions_stopped')::int AS sessions_stopped,
         jsonb_array_length(COALESCE(r->'report'->'vehicles', '[]'::jsonb)) AS replanned
    FROM run CROSS JOIN LATERAL jsonb_array_elements(run.inj->'results') r
    JOIN public.stalls st ON st.ocpp_charger_id = (r->>'charger_id')::uuid AND st.depot_id = '11111111-1111-1111-1111-111111111111'),
s AS (
  SELECT i.*, o.vehicle_id AS car, o.status::text AS sess_status, o.stopped_reason, o.soc_start, o.soc_end, o.ended_at
    FROM inj i LEFT JOIN LATERAL (
      SELECT o.* FROM public.ocpp_sessions o
       WHERE o.sim_run_id = (SELECT id FROM run) AND o.stall_id = i.stall_id AND o.stopped_reason = 'fault.operator_injected'
       ORDER BY o.ended_at DESC LIMIT 1) o ON true),
x AS (
  SELECT s.*,
         (SELECT e.payload->'diff'->'current_state'->>'to' FROM public.ottoq_events e
           WHERE e.sim_run_id = (SELECT id FROM run) AND e.entity_id = s.car AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_state' AND e.sim_clock_at >= s.fault_at
           ORDER BY e.event_seq LIMIT 1) AS car_went_to,
         (SELECT min(o2.started_at) FROM public.ocpp_sessions o2
           WHERE o2.sim_run_id = (SELECT id FROM run) AND o2.vehicle_id = s.car AND o2.started_at > s.fault_at) AS car_next_charge,
         (SELECT o2.soc_end FROM public.ocpp_sessions o2
           WHERE o2.sim_run_id = (SELECT id FROM run) AND o2.vehicle_id = s.car AND o2.started_at > s.fault_at
           ORDER BY o2.started_at DESC LIMIT 1) AS car_last_soc_end,
         (SELECT min(o3.started_at) FROM public.ocpp_sessions o3
           WHERE o3.sim_run_id = (SELECT id FROM run) AND o3.stall_id = s.stall_id AND o3.started_at > s.fault_at) AS charger_next_session
    FROM s)
SELECT x.stall_code AS charger, v.display_name AS car, x.sessions_stopped, x.replanned, x.sess_status, x.stopped_reason,
       x.soc_start, x.soc_end AS soc_at_fault, x.car_went_to,
       to_char(x.car_next_charge AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS car_next_charge_ct,
       round((extract(epoch FROM (COALESCE(x.car_next_charge, (SELECT t1 FROM run)) - x.fault_at)) / 60)::numeric, 1) AS car_waited_min,
       x.car_last_soc_end,
       c.station_state AS charger_now, st.status::text AS stall_now,
       to_char(x.fault_at AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS fault_ct,
       to_char(x.recovers_at AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS recovers_ct,
       round((extract(epoch FROM (x.charger_next_session - x.fault_at)) / 60)::numeric, 1) AS out_of_service_min,
       round((extract(epoch FROM (x.recovers_at - x.fault_at)) / 60)::numeric, 1) AS declared_repair_min,
       (SELECT to_char(run.t1 AT TIME ZONE 'America/Chicago', 'HH12:MI AM') FROM run) AS sim_now_ct
  FROM x LEFT JOIN public.vehicles v ON v.id = x.car
  JOIN public.ottoq_ocpp_chargers c ON c.charger_id = x.charger_id
  JOIN public.stalls st ON st.id = x.stall_id
 ORDER BY 1;
-- READ: pending.

--   §17c, the injected stalls' own stream through the outage: every change of status, so the repair is seen returning the
--   stall (0550 (d)) and nothing else is seen returning it earlier.
\echo '=== 0412 §17c — the injected stalls'' status changes from the fault on ==='
WITH run AS MATERIALIZED (
  SELECT r.sim_run_id AS id, r.payload->'stress_injection_0412' AS inj FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
inj AS (
  SELECT st.id AS stall_id, st.stall_code, (r->>'faulted_at_sim')::timestamptz AS fault_at
    FROM run CROSS JOIN LATERAL jsonb_array_elements(run.inj->'results') r
    JOIN public.stalls st ON st.ocpp_charger_id = (r->>'charger_id')::uuid AND st.depot_id = '11111111-1111-1111-1111-111111111111')
SELECT i.stall_code, to_char(e.sim_clock_at AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS at_ct,
       round((extract(epoch FROM (e.sim_clock_at - i.fault_at)) / 60)::numeric, 1) AS min_after_fault,
       e.payload->'diff'->'status'->>'from' AS status_from, e.payload->'diff'->'status'->>'to' AS status_to
  FROM inj i JOIN public.ottoq_events e
    ON e.sim_run_id = (SELECT id FROM run) AND e.entity_id = i.stall_id AND e.event_type = 'stall.state_changed'
   AND e.payload->'diff' ? 'status' AND e.sim_clock_at >= i.fault_at
 ORDER BY i.stall_code, e.event_seq
 LIMIT 30;
-- READ: pending.

-- ══ §18 G282 RE-MEASURED: GATE STAYS BELOW TARGET THAT REACHED 240 MINUTES, AND AN ESCALATION INSIDE THE STAY ═════════
--
--   0546 (d) escalates a car to a person when it has waited past 240 minutes for a charger or the service bay (G274).
--   Before 0551 its loop read only staged cars on need_charge or need_service, so a car waiting at the gate was never
--   escalated (0409: 32 of 32 stays that reached 240 minutes). 0551 (d) adds the gate below the cursor's threshold and
--   reads the wait on the cursor's episode clock. This is 0409's query unchanged: it credits an escalation only inside
--   the stay, so a car told earlier in the same episode (while staged) reads as not told here; §23b credits the episode.


\echo '=== 0412 §18 — stays at the gate: how many reached 240 minutes, and how many of those a person was never told about ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
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
-- READ: pending.


-- ══ §19 G283 ON A THIRD DAY, UNDER 0553: CARS HELD FOR BAY WORK, AND THE WASH BAYS WHILE THEY WAITED ═══════════════════
--
--   0408 §19 found two cars at 100% held 250 and 330 minutes for a deep clean while the three wash bays were 54-57%
--   occupied. Deep cleans run in the wash bays, because the twin depot has no detail bay. Here each window comes from the
--   run itself: a car with a `must_do_work_open` escalation, from the start of its hold (the escalation's time less
--   `held_min`) to its next entry into a wash or detail bay, or the end of the run. For each window, the minutes cars
--   spent in the wash bays (either purpose) against the bays' minutes, and the bays' calendar.


\echo '=== 0412 §19 — each car escalated for bay work: its wait, and the wash bays in that window ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
bays AS MATERIALIZED (SELECT count(*) AS n FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type::text = 'wash_bay'),
st AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq, e.payload->'diff'->'current_state'->>'to' AS s_to
    FROM public.ottoq_events e, run WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'),
seg AS (SELECT vehicle_id, at AS began, s_to, lead(at) OVER (PARTITION BY vehicle_id ORDER BY seq) AS ended FROM st),
inbay AS MATERIALIZED (SELECT s.vehicle_id, s.s_to, s.began, COALESCE(s.ended, (SELECT t1 FROM run)) AS ended FROM seg s WHERE s.s_to IN ('in_wash_bay','in_detail_bay')),
w AS (
  SELECT e.entity_id AS vehicle_id, e.payload->'missing' AS missing,
         e.sim_clock_at - make_interval(secs => (e.payload->>'held_min')::numeric * 60) AS w0,
         COALESCE((SELECT min(i.began) FROM inbay i WHERE i.vehicle_id = e.entity_id AND i.began > e.sim_clock_at), (SELECT t1 FROM run)) AS w1
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'twin.deploy_gate_escalated' AND e.payload->>'reason' = 'must_do_work_open')
SELECT v.display_name AS car, w.missing,
       to_char(w.w0 AT TIME ZONE 'America/Chicago', 'HH12:MI AM') || '-' || to_char(w.w1 AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS window_ct,
       round((extract(epoch FROM (w.w1 - w.w0)) / 60)::numeric) AS wait_min,
       round((sum(extract(epoch FROM (LEAST(i.ended, w.w1) - GREATEST(i.began, w.w0)))) FILTER (WHERE i.ended > w.w0 AND i.began < w.w1) / 60)::numeric, 1) AS bay_car_minutes_in_window,
       round(((SELECT n FROM bays) * extract(epoch FROM (w.w1 - w.w0)) / 60)::numeric) AS bay_capacity_minutes,
       count(*) FILTER (WHERE i.ended > w.w0 AND i.began < w.w1) AS bay_visits_in_window
  FROM w JOIN public.vehicles v ON v.id = w.vehicle_id LEFT JOIN inbay i ON true
 GROUP BY v.display_name, w.missing, w.w0, w.w1 ORDER BY w.w0;
-- READ: pending.

\echo '=== 0412 §19b — the wash bays'' calendar in the same windows: bookings used, released unused and superseded ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
bays AS (SELECT id FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type::text = 'wash_bay'),
inbay AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS began FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay','in_detail_bay')),
w AS (
  SELECT v.display_name AS car, e.sim_clock_at - make_interval(secs => (e.payload->>'held_min')::numeric * 60) AS w0,
         COALESCE((SELECT min(i.began) FROM inbay i WHERE i.vehicle_id = e.entity_id AND i.began > e.sim_clock_at), (SELECT t1 FROM run)) AS w1
    FROM public.ottoq_events e JOIN public.vehicles v ON v.id = e.entity_id, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'twin.deploy_gate_escalated' AND e.payload->>'reason' = 'must_do_work_open'),
b AS (
  SELECT b.booking_id, b.purpose, b.state, b.during
    FROM public.ottoq_stall_bookings b, run
   WHERE b.sim_run_id = run.id AND b.stall_id IN (SELECT id FROM bays))
SELECT w.car, b.state, b.purpose, count(*) AS bookings,
       round((sum(extract(epoch FROM (LEAST(upper(b.during), w.w1) - GREATEST(lower(b.during), w.w0)))) / 60)::numeric, 1) AS booked_min_in_window
  FROM w JOIN b ON b.during && tstzrange(w.w0, w.w1)
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ: pending.

--   §19c, why the seat refused: every needs-card attempt at a wash bay that was refused, against the three bays at that
--   moment. `cars_in_bays` comes from the state stream; `calendar_free_bays` is the number of bays with no booking, known
--   at that moment and not yet released, overlapping the attempt's window (25 minutes for a deep clean, 9 for a wash). A
--   held booking re-timed later by the bay reconciler is read at its CURRENT window, so this undercounts the calendar's
--   share. §19d reads the reconciler's own log for one refused stretch.
\echo '=== 0412 §19c — each refused wash-bay seat: bays physically empty, and bays free on the calendar ==='
WITH run AS MATERIALIZED (SELECT sim_run_id AS id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
bays AS MATERIALIZED (SELECT id FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type::text = 'wash_bay'),
att AS MATERIALIZED (
  SELECT DISTINCT d.sim_clock AS at, d.entity_id AS vehicle_id, d.proposed_action->>'purpose' AS purpose,
         CASE d.proposed_action->>'purpose' WHEN 'detail' THEN interval '25 minutes' ELSE interval '9 minutes' END AS need
    FROM public.ottoq_decisions d, run
   WHERE d.sim_run_id = run.id AND d.proposed_action->>'source' = 'needs_card'
     AND d.proposed_action->>'stall_type' = 'wash_bay' AND d.outcome_status = 'noop_no_candidate'),
st AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq, e.payload->'diff'->'current_state'->>'to' AS s_to
    FROM public.ottoq_events e, run WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'),
seg AS MATERIALIZED (
  SELECT vehicle_id, at AS began, COALESCE(lead(at) OVER (PARTITION BY vehicle_id ORDER BY seq), (SELECT t1 FROM run)) AS ended, s_to FROM st),
inbay AS MATERIALIZED (SELECT * FROM seg WHERE s_to IN ('in_wash_bay','in_detail_bay')),
bk AS MATERIALIZED (SELECT b.* FROM public.ottoq_stall_bookings b, run WHERE b.sim_run_id = run.id AND b.stall_id IN (SELECT id FROM bays)),
per AS (
  SELECT a.*,
         (SELECT count(*) FROM inbay i WHERE i.began <= a.at AND i.ended > a.at) AS cars_in_bays,
         (SELECT count(*) FROM bays y WHERE NOT EXISTS (
             SELECT 1 FROM bk WHERE bk.stall_id = y.id AND COALESCE(bk.booked_at_sim, lower(bk.during)) <= a.at
                AND (bk.released_at IS NULL OR bk.released_at > a.at)
                AND bk.during && tstzrange(a.at, a.at + a.need))) AS calendar_free_bays
    FROM att a)
SELECT purpose, count(*) AS refused_attempts,
       count(*) FILTER (WHERE cars_in_bays >= 3) AS all_3_bays_physically_full,
       count(*) FILTER (WHERE cars_in_bays < 3 AND calendar_free_bays = 0) AS empty_bay_but_none_free_on_the_calendar,
       count(*) FILTER (WHERE calendar_free_bays > 0) AS free_on_todays_calendar_yet_refused,
       round(avg(3 - cars_in_bays), 2) AS avg_empty_bays
  FROM per GROUP BY 1 ORDER BY 1;
-- READ: pending.

-- ══ §20 THE INJECTION JOB ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Every attempt of job 782 that got past its clock gate, with its outcome. Since 0552 the fault doors take the run's row
--   first, as the tick does, so no attempt should deadlock (0409 §20: two did, before 0552).

\echo '=== 0412 §20 — the injection job''s attempts ==='
SELECT d.jobid, d.start_time, d.status, round(extract(epoch FROM (d.end_time - d.start_time))::numeric, 2) AS secs,
       CASE WHEN d.return_message LIKE '%deadlock detected%' THEN 'deadlock' ELSE d.return_message END AS outcome
  FROM cron.job_run_details d
 WHERE d.jobid = 782 AND (d.status <> 'succeeded' OR d.end_time - d.start_time > interval '0.5 seconds')
 ORDER BY d.start_time;
-- READ: pending.

-- ══ §21 G286 UNDER 0554: EVERY BAY VISIT IN A BAY ════════════════════════════════════════════════════════════════════════
--
--   Found reading 0553's probe: three cars that had left the depot still held wash-bay bookings, each for a bay leg the
--   itinerary had already closed as done. Two of them had done their deep clean with no bay. The twin's service flow
--   (`twin.ottoq_sim_advance_service_flow`) admits cars to its wash lane (STEP 2, from `charge_complete_holding`) and
--   its service lane (from `staged_awaiting_service` / need_service) by staff count alone: LEAST(cleaning_staff,
--   wash_supervisor) and service_staff, less the cars already in a bay STATE. It seats a car in a bay only when the car
--   holds a booking whose window contains the clock and the bay is free. Otherwise it still sets the car to
--   `in_wash_bay`, `in_detail_bay` or `in_service_bay`, with `service_ends_at`, and STEP 1 credits the bay's work when
--   the timer ends. The car stands on its staging stall, or on no stall once the charge arm has let go of it.
--   Each bay visit (a vehicle state segment in a bay state) is classed by both pointers: the car's own
--   `current_stall_id` while in that state, and any bay's `current_vehicle_id` naming it in that interval.
--   Under 0554 both lanes take only a car whose bay is booked for now and set the bay state only once it stands in that
--   bay, so `in_no_bay` must read 0 on every row (0409: 34 of 93).


\echo '=== 0412 §21 — each bay visit: in a bay, or in no bay, by where the car came from ==='
WITH run AS MATERIALIZED (SELECT sim_run_id AS id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
bays AS MATERIALIZED (SELECT id, stall_type::text AS stype FROM public.stalls
                       WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type::text IN ('wash_bay','service_bay','detail_bay')),
st AS MATERIALIZED (
  SELECT e.entity_id AS vid, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'current_state'->>'from' AS s_from, e.payload->'diff'->'current_state'->>'to' AS s_to
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'),
seg AS MATERIALIZED (
  SELECT vid, s_from, s_to, at AS began, seq AS seq0,
         COALESCE(lead(at) OVER w, (SELECT t1 FROM run)) AS ended, lead(seq) OVER w AS seq1
    FROM st WINDOW w AS (PARTITION BY vid ORDER BY seq)),
-- the car's own pointer: its value when the segment began, and every value it took inside it
vptr AS MATERIALIZED (
  SELECT e.entity_id AS vid, e.event_seq AS seq, NULLIF(e.payload->'diff'->'current_stall_id'->>'to', '')::uuid AS stall_to
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_stall_id'),
-- each bay's pointer, as intervals
sptr AS MATERIALIZED (
  SELECT e.entity_id AS stall_id, e.sim_clock_at AS at, NULLIF(e.payload->'diff'->'current_vehicle_id'->>'to', '')::uuid AS vid,
         lead(e.sim_clock_at) OVER (PARTITION BY e.entity_id ORDER BY e.event_seq) AS until
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'stall.state_changed' AND e.payload->'diff' ? 'current_vehicle_id'
     AND e.entity_id IN (SELECT id FROM bays)),
cls AS (
  SELECT g.*,
         EXISTS (SELECT 1 FROM (
                   SELECT p.stall_to FROM vptr p WHERE p.vid = g.vid AND p.seq > g.seq0 AND p.seq < COALESCE(g.seq1, 9e18)
                   UNION ALL
                   SELECT (SELECT p2.stall_to FROM vptr p2 WHERE p2.vid = g.vid AND p2.seq <= g.seq0 ORDER BY p2.seq DESC LIMIT 1)) x
                  WHERE x.stall_to IN (SELECT id FROM bays))
         OR EXISTS (SELECT 1 FROM sptr s WHERE s.vid = g.vid AND s.at < g.ended AND COALESCE(s.until, (SELECT t1 FROM run)) > g.began) AS in_a_bay
    FROM seg g WHERE g.s_to IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay'))
SELECT s_to AS bay_state, s_from AS came_from, count(*) AS visits,
       count(*) FILTER (WHERE in_a_bay) AS in_a_bay, count(*) FILTER (WHERE NOT in_a_bay) AS in_no_bay,
       round((sum(extract(epoch FROM (ended - began))) FILTER (WHERE in_a_bay) / 60)::numeric) AS bay_minutes,
       round((sum(extract(epoch FROM (ended - began))) FILTER (WHERE NOT in_a_bay) / 60)::numeric) AS no_bay_minutes
  FROM cls GROUP BY ROLLUP (1, 2) ORDER BY 1 NULLS LAST, 2 NULLS LAST;
-- READ: pending.

-- ══ §22 G279 UNDER 0551: WHO WENT AHEAD OF A CAR RE-QUEUED BY A FAULT ══════════════════════════════════════════════════
--
--   For every fault on a car below 99%: how long until the car charged again (or the end), and how many cars that arrived
--   at the gate AFTER the fault started a charge before it did. Before 0551 a fault reset the car's wait to zero, so every
--   later arrival competed with it as an equal (eff13379: 179 such overtakings over 16 faults, §0). Under 0551 the car
--   keeps its banked wait (0551 (b)), and the cursor ranks it by the whole episode (0551 (c)), so a later arrival goes
--   ahead only when its ratio is higher: a short top-off, or an immediate dispatch. `overtaken_by_later_arrivals` should
--   be small, and `waited_after_min` short for a car that had waited long before its fault.

\echo '=== 0412 §22 — per fault below 99%: the wait after it, and the later arrivals that charged first ==='
WITH run AS MATERIALIZED (SELECT sim_run_id AS id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
f AS MATERIALIZED (
  SELECT o.id, o.vehicle_id, st.stall_type::text AS kind, o.ended_at AS faulted_at, o.soc_end AS soc_at_fault, o.stopped_reason
    FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id, run
   WHERE o.sim_run_id = run.id AND o.status::text = 'faulted' AND o.soc_end < 99),
starts AS MATERIALIZED (
  SELECT o.vehicle_id, o.started_at FROM public.ocpp_sessions o, run WHERE o.sim_run_id = run.id),
arrivals AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' = 'arrived_at_gate'),
x AS (
  SELECT f.*, COALESCE((SELECT min(s.started_at) FROM starts s WHERE s.vehicle_id = f.vehicle_id AND s.started_at > f.faulted_at),
                       (SELECT t1 FROM run)) AS resumed_or_end,
         EXISTS (SELECT 1 FROM starts s WHERE s.vehicle_id = f.vehicle_id AND s.started_at > f.faulted_at) AS resumed
    FROM f)
SELECT v.display_name AS car, x.kind, x.soc_at_fault, x.stopped_reason,
       to_char(x.faulted_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS fault_ct, x.resumed,
       round((extract(epoch FROM (x.resumed_or_end - x.faulted_at)) / 60)::numeric, 1) AS waited_after_min,
       (SELECT count(DISTINCT s.vehicle_id) FROM starts s
         WHERE s.vehicle_id <> x.vehicle_id AND s.started_at > x.faulted_at AND s.started_at < x.resumed_or_end
           AND EXISTS (SELECT 1 FROM arrivals a WHERE a.vehicle_id = s.vehicle_id AND a.at > x.faulted_at AND a.at < s.started_at)
       ) AS overtaken_by_later_arrivals
  FROM x JOIN public.vehicles v ON v.id = x.vehicle_id
 ORDER BY x.faulted_at;
-- READ: pending.

--   §22b, live only (the teardown ends every episode): the banks the cursor reads, `config.charge_wait`, on this run's cars.
\echo '=== 0412 §22b — live: cars carrying a charge-wait bank for this run ==='
SELECT v.display_name AS car, v.current_state::text AS state, v.config->>'svc_step' AS step, v.current_soc,
       (v.config->'charge_wait'->>'banked_min')::numeric AS banked_min,
       to_char((v.config->'charge_wait'->>'since')::timestamptz AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS episode_since_ct,
       round(public.ottoq_charge_wait_min(v.config, v.last_state_change, r.sim_clock_current, r.sim_run_id), 1) AS cursor_wait_min
  FROM public.vehicles v, public.ottoq_sim_runs r
 WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND v.home_depot_id = '11111111-1111-1111-1111-111111111111'
   AND v.config->'charge_wait'->>'run' = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'
 ORDER BY banked_min DESC NULLS LAST LIMIT 15;
-- READ: pending.

-- ══ §23 G282 UNDER 0551: A CAR WAITING AT THE GATE IS ESCALATED ═══════════════════════════════════════════════════════
--
--   §23a, every escalation by reason and where the car waited (0551 (d) records `at`). None may read under 240 minutes.
--   §23b, every stay at the gate that began below target and reached 240 minutes, and whether a person was told in its
--   episode: an escalation for the car, at or before the stay's end, whose `waiting_since` is at or before the stay's
--   start, with no completed charge between. A car escalated while staged and then moved to the gate is told once, not
--   twice (0551 (d): once per episode), which is why §18's per-stay count can read lower than §23b.

\echo '=== 0412 §23a — escalations by reason and where the car waited ==='
SELECT e.payload->>'reason' AS reason, e.payload->>'at' AS waited_at, count(*) AS escalations, count(DISTINCT e.entity_id) AS cars,
       round(min((e.payload->>'held_min')::numeric), 1) AS min_held_min, round(max((e.payload->>'held_min')::numeric), 1) AS max_held_min
  FROM public.ottoq_events e
 WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.event_type = 'twin.deploy_gate_escalated'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ: pending.

\echo '=== 0412 §23b — gate stays below target that reached 240 minutes: told in their episode, or not ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
st AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'current_state'->>'to' AS s_to, (e.payload->'diff'->'current_soc'->>'to')::numeric AS soc_to,
         e.payload->'diff' ? 'current_state' AS has_state
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND (e.payload->'diff' ? 'current_state' OR e.payload->'diff' ? 'current_soc')),
seg AS (SELECT vehicle_id, at AS began, seq, s_to, lead(at) OVER (PARTITION BY vehicle_id ORDER BY seq) AS ended FROM st WHERE has_state),
gate AS MATERIALIZED (
  SELECT g.vehicle_id, g.began, COALESCE(g.ended, (SELECT t1 FROM run)) AS ended,
         extract(epoch FROM (COALESCE(g.ended, (SELECT t1 FROM run)) - g.began)) / 60 AS wait_min,
         (SELECT s0.soc_to FROM st s0 WHERE s0.vehicle_id = g.vehicle_id AND s0.soc_to IS NOT NULL AND s0.seq <= g.seq
           ORDER BY s0.seq DESC LIMIT 1) AS soc_at_arrival
    FROM seg g WHERE g.s_to = 'arrived_at_gate' AND g.began > (SELECT t0 FROM run)),
esc AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at,
         COALESCE((e.payload->>'waiting_since')::timestamptz,
                  e.sim_clock_at - make_interval(secs => (e.payload->>'held_min')::numeric * 60)) AS since
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'twin.deploy_gate_escalated' AND e.payload->>'reason' = 'waiting_for_a_charger'),
done AS MATERIALIZED (
  SELECT o.vehicle_id, o.ended_at FROM public.ocpp_sessions o, run WHERE o.sim_run_id = run.id AND o.status::text = 'completed'),
cov AS (
  SELECT g.*, EXISTS (
           SELECT 1 FROM esc x
            WHERE x.vehicle_id = g.vehicle_id AND x.at <= g.ended AND x.since <= g.began + interval '1 minute'
              AND NOT EXISTS (SELECT 1 FROM done d WHERE d.vehicle_id = g.vehicle_id AND d.ended_at > x.since AND d.ended_at < g.began)
         ) AS told
    FROM gate g WHERE g.soc_at_arrival < 99 AND g.wait_min >= 240)
SELECT count(*) AS stays_240_plus_below_target, count(*) FILTER (WHERE told) AS told_in_their_episode,
       count(*) FILTER (WHERE NOT told) AS never_told, round(max(wait_min)::numeric, 1) AS longest_min
  FROM cov;
-- READ: pending.

-- ══ §24 G283 UNDER 0553: A HOLD FOR A CAR THAT CANNOT COME GIVES WAY ═══════════════════════════════════════════════════
--
--   §24a, every needs-card seat at a bay, by outcome and whether it came after a yield (`yielded_holds`, 0553 (c)).
--   §24b, the yields themselves, from the bay reconciler's log (`blocked_by` starts `yield:`): holds moved to their car's
--   ETA (`yielded_to_a_car_waiting_now`), released because their leg was closed (`replanned_leg_closed`) or their car had
--   gone (`replanned_vehicle_absent`), or released for want of room (`replanned_no_window`).
--   §24c, what became of each moved hold: used, released, and why. A moved hold is a forward reservation; the car's work
--   stays open until a bay does it, and rule 9 (§2) must still read 0.

\echo '=== 0412 §24a — needs-card bay seats: outcome, and whether a yield came first ==='
SELECT d.proposed_action->>'stall_type' AS bay, d.proposed_action->>'purpose' AS purpose, d.outcome_status,
       -- the seat folds `yielded_holds` into the action it enacts or holds (enacted_action), not the proposal
       COALESCE((d.enacted_action->>'yielded_holds')::boolean, false) AS after_a_yield, count(*) AS decisions
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND d.proposed_action->>'source' = 'needs_card'
   AND d.proposed_action->>'stall_type' IN ('wash_bay', 'service_bay')
 GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
-- READ: pending.

\echo '=== 0412 §24b — the yields, from the bay reconciler''s log ==='
SELECT s.stall_type::text AS bay, r.action, r.reason, r.blocked_by, count(*) AS holds, count(DISTINCT r.vehicle_id) AS cars,
       round(avg(extract(epoch FROM (r.new_from - r.old_from)) / 60)::numeric, 1) AS avg_moved_min,
       round(max(extract(epoch FROM (r.new_from - r.old_from)) / 60)::numeric, 1) AS max_moved_min
  FROM public.bay_reservation_reconcile_2026_08_02 r JOIN public.stalls s ON s.id = r.stall_id
 WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND r.blocked_by LIKE 'yield:%'
 GROUP BY 1, 2, 3, 4 ORDER BY 1, 5 DESC;
-- READ: pending.

\echo '=== 0412 §24c — what became of each hold a yield moved ==='
SELECT b.purpose, b.state, b.release_reason, count(*) AS holds
  FROM public.ottoq_stall_bookings b
 WHERE b.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'
   AND b.booking_id IN (SELECT r.booking_id FROM public.bay_reservation_reconcile_2026_08_02 r
                         WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND r.reason = 'yielded_to_a_car_waiting_now')
 GROUP BY 1, 2, 3 ORDER BY 1, 4 DESC;
-- READ: pending.

-- ══ §25 G284 UNDER 0551: THE COCKPIT'S QUEUE IS THE LINE THE ENGINE SERVES (LIVE) ═══════════════════════════════════════
--
--   `public.ottoq_depot_queue` feeds the field-ops cockpit's queue positions. Under 0551 (e) it mirrors the charge cursor:
--   its filter, its keys and the run's clock. Read live: the head of the charge queue at one moment, then which cars the
--   chargers took over the next few minutes, and at what position each had stood.

\echo '=== 0412 §25 — live: the head of the cockpit''s charge queue ==='
SELECT q.queue_position, q.queue_depth, q.vehicle_ref, q.current_soc, q.is_immediate,
       to_char(q.waiting_since AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS waiting_since_ct
  FROM public.ottoq_depot_queue('11111111-1111-1111-1111-111111111111', '4b0999db-a9ef-4b35-b3e2-c985d1a259f2') q
 WHERE q.queue_kind = 'charge' ORDER BY q.queue_position LIMIT 10;
-- READ: pending.

-- ══ §26 G289 UNDER 0556: NO SERVICE-BAY VISIT FOR THE GATE'S FLAG ALONE ══════════════════════════════════════════════
--
--   0410 §26's queries, with §26b counting both of the gate's flags. Under 0556 the wash and detail exit reads
--   `public.ottoq_flag_needs_service`, which says no for the gate's own patience flags (`deploy_gate_stuck`,
--   `deploy_gate_hard_cap`), and drops that flag as the release does (0546 (b)); the service lane's need gate and the
--   charge disposition read the same answer. So §26a's "credited nothing, cleared deploy_gate_stuck" must be 0 (0410: 6
--   of 25 visits, 268.1 bay-minutes), and §26b's gate-flag episodes must not end in the service bay (0410: 36.7
--   car-hours). A technician flag the gate did not raise still sends a car to the service bay, and §26a shows those
--   visits in their own rows.

\echo '=== 0412 §26a — service-bay visits by what they credited, and the bay-minutes each kind took ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
st AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq, e.payload->'diff'->'current_state'->>'to' AS s_to
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'),
seg AS (SELECT st.*, COALESCE(lead(at) OVER (PARTITION BY vehicle_id ORDER BY seq), (SELECT t1 FROM run)) AS b FROM st),
sb AS (SELECT * FROM seg WHERE s_to = 'in_service_bay' AND b > at),
j AS (
  SELECT sb.*, (SELECT sc.payload FROM public.ottoq_events sc, run
                 WHERE sc.sim_run_id = run.id AND sc.entity_id = sb.vehicle_id AND sc.event_type = 'twin.service_completed'
                   AND sc.payload->>'from' = 'in_service_bay' AND sc.sim_clock_at >= sb.at ORDER BY sc.sim_clock_at LIMIT 1) AS svc
    FROM sb)
SELECT CASE WHEN svc IS NULL THEN 'no completion (in the bay at the end)'
            WHEN jsonb_array_length(svc->'credited') = 0 THEN 'credited nothing, cleared ' || COALESCE(svc->>'flag_cleared', 'no flag')
            ELSE 'credited work' || CASE WHEN svc->>'flag_cleared' IS NOT NULL THEN ', cleared ' || (svc->>'flag_cleared') ELSE '' END END AS visit,
       count(*) AS visits, round((sum(extract(epoch FROM (b - at))) / 60)::numeric, 1) AS bay_minutes,
       round((avg(extract(epoch FROM (b - at))) / 60)::numeric, 1) AS mean_min
  FROM j GROUP BY 1 ORDER BY 1;
-- READ: pending.

\echo '=== 0412 §26b — episodes staged on need_service, by the gate''s flag and how each ended ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
ev AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'current_state'->>'to' AS s_to,
         CASE WHEN e.payload->'diff' ? 'config' THEN COALESCE(e.payload->'diff'->'config'->'to'->>'svc_step', '-') END AS step_to,
         CASE WHEN e.payload->'diff' ? 'config' THEN COALESCE(e.payload->'diff'->'config'->'to'->>'flagged_issue_type', '-') END AS flag_to
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND (e.payload->'diff' ? 'current_state' OR e.payload->'diff' ? 'config')),
g AS (SELECT ev.*, count(s_to) OVER w AS gs, count(step_to) OVER w AS gc FROM ev WINDOW w AS (PARTITION BY vehicle_id ORDER BY seq)),
f AS (SELECT vehicle_id, at, seq,
             first_value(s_to) OVER (PARTITION BY vehicle_id, gs ORDER BY seq) AS state,
             first_value(step_to) OVER (PARTITION BY vehicle_id, gc ORDER BY seq) AS step,
             first_value(flag_to) OVER (PARTITION BY vehicle_id, gc ORDER BY seq) AS flag
        FROM g),
seg AS (SELECT f.*, COALESCE(lead(at) OVER (PARTITION BY vehicle_id ORDER BY seq), (SELECT t1 FROM run)) AS b FROM f),
ns AS (SELECT * FROM seg WHERE state = 'staged_awaiting_service' AND step = 'need_service' AND b > at),
ep AS (SELECT vehicle_id, min(at) AS s, max(b) AS e, sum(extract(epoch FROM (b - at))) AS secs,
              bool_or(flag IN ('deploy_gate_stuck', 'deploy_gate_hard_cap')) AS gate_flag
         FROM (SELECT ns.*, sum(CASE WHEN prev_b = at THEN 0 ELSE 1 END) OVER (PARTITION BY vehicle_id ORDER BY seq) AS grp
                 FROM (SELECT ns.*, lag(b) OVER (PARTITION BY vehicle_id ORDER BY seq) AS prev_b FROM ns) ns) x
        GROUP BY vehicle_id, grp),
cls AS (
  SELECT ep.*,
         (SELECT sc.payload FROM public.ottoq_events sc, run
           WHERE sc.sim_run_id = run.id AND sc.entity_id = ep.vehicle_id AND sc.event_type = 'twin.service_completed'
             AND sc.payload->>'from' = 'in_service_bay' AND sc.sim_clock_at >= ep.e ORDER BY sc.sim_clock_at LIMIT 1) AS svc
    FROM ep)
SELECT CASE WHEN e >= (SELECT t1 FROM run) THEN 'still waiting at the end'
            WHEN svc IS NULL THEN 'left need_service with no service-bay completion'
            WHEN jsonb_array_length(svc->'credited') = 0 THEN 'service bay credited nothing (flag only)'
            ELSE 'service bay credited work' END AS how_it_ended,
       gate_flag, count(*) AS episodes, count(DISTINCT vehicle_id) AS cars,
       round((sum(secs) / 3600)::numeric, 1) AS car_hours, round((max(secs) / 60)::numeric, 1) AS longest_min
  FROM cls GROUP BY 1, 2 ORDER BY 1, 2;
-- READ: pending.

-- ══ §27 G290 UNDER 0555: EVERY FAULTED CAR IS REPAIRED BEFORE IT LEAVES ═══════════════════════════════════════════════
--
--   §27a is 0410's query: every car with a vehicle exception, its state changes, and the exception's status at each.
--   Under 0555 a car the readmit takes back carries a must-do `fault_repair` and is staged for the service bay; a towed car
--   with no cut-short visit is routed there by the fault handler's step (6) (exception status `awaiting_repair`); the
--   service bay's credit of `fault_repair` removes the exception and names it on `twin.service_completed`
--   (`fault_repaired`), and nothing else removes it. Under 0557 no charge starts while the fault is open (a car whose
--   fault let its current charge finish keeps that session; §27b counts only charges started inside the spell). §27b
--   follows each fault spell from raised to closed, with any charge started and any departure inside it (both must be 0).
--   §27c reads step (6)'s events and the `fault_repair` atoms by status.

\echo '=== 0412 §27a — every car with a vehicle exception: its state changes and the exception''s status at each ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
ex AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'current_state'->>'from' AS s_from, e.payload->'diff'->'current_state'->>'to' AS s_to,
         e.payload->'diff'->'config'->'to'->'exception' AS exc
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.sim_clock_at > run.t0
     AND e.payload->'diff'->'config'->'to' ? 'exception'
     AND (e.payload->'diff' ? 'current_state'
          OR (e.payload->'diff'->'config'->'to'->'exception') IS DISTINCT FROM (e.payload->'diff'->'config'->'from'->'exception')))
SELECT v.display_name AS car, to_char(ex.at AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS at_ct,
       COALESCE(ex.s_from || ' -> ' || ex.s_to, '(no state change)') AS transition,
       ex.exc->>'fault_class' AS fault, ex.exc->>'severity' AS severity, ex.exc->>'immobilizing' AS immobilizing,
       ex.exc->>'status' AS exception_status
  FROM ex JOIN public.vehicles v ON v.id = ex.vehicle_id
 ORDER BY v.display_name, ex.seq;
-- READ: pending.

\echo '=== 0412 §27b — every vehicle fault spell: raised, closed, repaired, and any departure while it was open ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
cfg AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'config'->'to'->'exception' AS exc,
         public.ottoq_vehicle_fault_open(e.payload->'diff'->'config'->'to') AS open_after
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.sim_clock_at > run.t0
     AND e.payload->'diff' ? 'config'),
chg AS (SELECT cfg.*, COALESCE(lag(open_after) OVER (PARTITION BY vehicle_id ORDER BY seq), false) AS open_before FROM cfg),
spell AS (
  SELECT o.vehicle_id, o.at AS opened_at, o.seq AS opened_seq, o.exc,
         (SELECT min(c.at) FROM chg c WHERE c.vehicle_id = o.vehicle_id AND c.seq > o.seq AND NOT c.open_after) AS closed_at
    FROM chg o WHERE o.open_after AND NOT o.open_before),
dep AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS left_at
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' IN ('en_route_to_deployment', 'deployed')
     AND e.payload->'diff'->'current_state'->>'from' NOT IN ('en_route_to_deployment', 'deployed')
     AND e.sim_clock_at > run.t0),
cst AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' IN ('charging_dcfc', 'charging_l2')
     AND e.sim_clock_at > run.t0),
rep AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.payload->'fault_repaired' AS fr
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'twin.service_completed'
     AND jsonb_typeof(e.payload->'fault_repaired') = 'object')
SELECT v.display_name AS car, s.exc->>'fault_class' AS fault, s.exc->>'severity' AS severity,
       s.exc->>'immobilizing' AS immobilizing,
       to_char(s.opened_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS raised_ct,
       to_char(s.closed_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS closed_ct,
       (SELECT to_char(min(r.at) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') FROM rep r
         WHERE r.vehicle_id = s.vehicle_id AND r.at >= s.opened_at
           AND (s.closed_at IS NULL OR r.at <= s.closed_at)) AS repaired_ct,
       round((extract(epoch FROM (COALESCE(s.closed_at, (SELECT t1 FROM run)) - s.opened_at)) / 60)::numeric, 1) AS open_min,
       (SELECT count(*) FROM dep d WHERE d.vehicle_id = s.vehicle_id AND d.left_at >= s.opened_at
           AND (s.closed_at IS NULL OR d.left_at < s.closed_at)) AS departures_while_open,
       (SELECT count(*) FROM cst WHERE cst.vehicle_id = s.vehicle_id AND cst.at > s.opened_at
           AND (s.closed_at IS NULL OR cst.at < s.closed_at)) AS charges_started_while_open,
       (SELECT to_char(min(d.left_at) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') FROM dep d
         WHERE d.vehicle_id = s.vehicle_id AND s.closed_at IS NOT NULL AND d.left_at >= s.closed_at) AS first_departure_after_ct,
       (SELECT v2.current_state::text FROM public.vehicles v2 WHERE v2.id = s.vehicle_id) AS state_now
  FROM spell s JOIN public.vehicles v ON v.id = s.vehicle_id
 ORDER BY s.opened_at;
-- READ: pending.

\echo '=== 0412 §27c — the fault handler''s step (6), and the fault_repair atoms by status ==='
SELECT to_char(e.sim_clock_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS at_ct, (e.payload->>'routed')::int AS routed,
       (SELECT string_agg(v.display_name || ' (' || COALESCE(c->>'fault_class', '?') || ', ' || COALESCE(c->>'severity', '?') || ')', '; ')
          FROM jsonb_array_elements(e.payload->'cars') c JOIN public.vehicles v ON v.id = (c->>'vehicle_id')::uuid) AS cars
  FROM public.ottoq_events e
 WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.event_type = 'ottoq.faulted_car_routed_to_repair'
 ORDER BY e.sim_clock_at;
SELECT COALESCE(a->>'status', 'pending') AS atom_status, COALESCE(vn.source, '-') AS visit_source,
       count(*) AS fault_repair_atoms, count(DISTINCT vn.vehicle_id) AS cars
  FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
 WHERE vn.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND a->>'svc' = 'fault_repair'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ: pending.

-- ══ §28 G292 UNDER 0558: A FAULTED CAR'S REPAIR GOES FIRST IN ITS PLAN, AND NO CHARGER IS HELD FOR IT ═════════════════
--
--   On 0411's run Zoox-AV-080's plan put an 8-hour L2 charge first and the repair last. 0557 refused the charge until the
--   repair was done, so neither could start: the car sat 526 minutes unrepaired and uncharged, and an L2 stood idle,
--   booked for it, from 6:20 AM (G292). 0558 (a) plans an open fault's repair first, (b) books no charger for a car with
--   an open fault, and (c) at step (6) releases a faulted car's held charge bookings (`vehicle_fault_open`) and re-plans a
--   staged car awaiting its repair whose plan does not put the repair first (`replanned_repair_first`). The spells are
--   §27b's: from the event that opened a car's vehicle exception to the event that closed it.
--
--   §28a  every plan the car was given inside the spell, and the last one before it: its legs in order, and whether the
--         repair's service leg (atom `fault_repair`) comes before every charge and bay leg (`repair_first`).
--   §28b  every charge booking of the car live inside the spell: made inside it (none may be), made before it and held
--         into it (released at step (6)'s next pass), or a charge already running when the fault opened (0557 lets that
--         session finish).
--   §28c  the repair's service-bay booking against the first minute a service bay had no booking over the repair's
--         length, reading the calendar as it stood when the repair was booked (a booking released later counts until its
--         release). The booker walks forward in 10-minute steps from the plan's start and also reads a bay's status and
--         the occupancy guard, so it may book up to 10 minutes after this minute; more than that is a finding. Then the
--         bay entry, the repair, and the first charge after it.
--   §28d  step (6)'s passes with their counts, and the flow contract's `amend_plan` on each faulted car inside its spell
--         (0558 §4: it still slides a waiting plan, which changes no seat).

\echo '=== 0412 §28a — every plan a faulted car was given inside its fault spell, and whether the repair came first ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
cfg AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'config'->'to'->'exception' AS exc,
         public.ottoq_vehicle_fault_open(e.payload->'diff'->'config'->'to') AS open_after
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.sim_clock_at > run.t0
     AND e.payload->'diff' ? 'config'),
chg AS (SELECT cfg.*, COALESCE(lag(open_after) OVER (PARTITION BY vehicle_id ORDER BY seq), false) AS open_before FROM cfg),
spell AS MATERIALIZED (
  SELECT o.vehicle_id, o.at AS opened_at, o.seq AS opened_seq, o.exc,
         (SELECT min(c.at) FROM chg c WHERE c.vehicle_id = o.vehicle_id AND c.seq > o.seq AND NOT c.open_after) AS closed_at
    FROM chg o WHERE o.open_after AND NOT o.open_before),
itin AS (
  SELECT s.vehicle_id, s.opened_at, s.closed_at, i.itinerary_id, i.sim_created_at, i.created_by, i.status,
         CASE WHEN i.sim_created_at < s.opened_at THEN 'before the spell' ELSE 'inside it' END AS made
    FROM spell s JOIN public.ottoq_vehicle_itineraries i ON i.vehicle_id = s.vehicle_id AND i.sim_run_id = (SELECT id FROM run)
   WHERE (i.sim_created_at >= s.opened_at AND (s.closed_at IS NULL OR i.sim_created_at < s.closed_at))
      OR i.itinerary_id = (SELECT i2.itinerary_id FROM public.ottoq_vehicle_itineraries i2
                            WHERE i2.vehicle_id = s.vehicle_id AND i2.sim_run_id = (SELECT id FROM run)
                              AND i2.sim_created_at < s.opened_at
                            ORDER BY i2.sim_created_at DESC, i2.created_at DESC LIMIT 1)),
legs AS (
  SELECT it.itinerary_id,
         min(l.seq) FILTER (WHERE l.leg_type = 'service' AND l.duration_basis->>'atom' = 'fault_repair') AS repair_seq,
         min(l.seq) FILTER (WHERE l.leg_type IN ('charge_dcfc', 'charge_l2', 'wash', 'detail', 'service')
                              AND NOT (l.leg_type = 'service' AND l.duration_basis->>'atom' = 'fault_repair')) AS other_seq,
         bool_or(l.duration_basis->>'first_because' = 'vehicle_fault_open') AS first_because_fault,
         string_agg(l.seq || ' ' || l.leg_type || COALESCE('(' || (l.duration_basis->>'atom') || ')', '') || ' '
                    || to_char(l.planned_start_sim AT TIME ZONE 'America/Chicago', 'HH12:MI AM') || ' ' || l.status,
                    '; ' ORDER BY l.seq) AS legs
    FROM itin it JOIN public.ottoq_itinerary_legs l ON l.itinerary_id = it.itinerary_id
   GROUP BY it.itinerary_id)
SELECT v.display_name AS car, it.made,
       to_char(it.sim_created_at AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS planned_ct, it.created_by,
       it.status AS plan_status,
       lg.repair_seq IS NOT NULL AND (lg.other_seq IS NULL OR lg.repair_seq < lg.other_seq) AS repair_first,
       lg.first_because_fault, lg.legs
  FROM itin it JOIN public.vehicles v ON v.id = it.vehicle_id LEFT JOIN legs lg ON lg.itinerary_id = it.itinerary_id
 ORDER BY it.opened_at, it.sim_created_at;
-- READ: pending.

\echo '=== 0412 §28b — charge bookings of a faulted car live inside its fault spell ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
cfg AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'config'->'to'->'exception' AS exc,
         public.ottoq_vehicle_fault_open(e.payload->'diff'->'config'->'to') AS open_after
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.sim_clock_at > run.t0
     AND e.payload->'diff' ? 'config'),
chg AS (SELECT cfg.*, COALESCE(lag(open_after) OVER (PARTITION BY vehicle_id ORDER BY seq), false) AS open_before FROM cfg),
spell AS MATERIALIZED (
  SELECT o.vehicle_id, o.at AS opened_at, o.seq AS opened_seq, o.exc,
         (SELECT min(c.at) FROM chg c WHERE c.vehicle_id = o.vehicle_id AND c.seq > o.seq AND NOT c.open_after) AS closed_at
    FROM chg o WHERE o.open_after AND NOT o.open_before),
bk AS (
  SELECT s.opened_at, s.closed_at, b.*,
         CASE WHEN b.state IN ('released', 'superseded') THEN COALESCE(b.released_at, b.booked_at_sim)
              WHEN b.state IN ('done', 'interrupted') THEN upper(b.during)
              ELSE (SELECT t1 FROM run) END AS live_until
    FROM spell s JOIN public.ottoq_stall_bookings b ON b.vehicle_id = s.vehicle_id AND b.sim_run_id = (SELECT id FROM run)
   WHERE b.purpose IN ('charge_dcfc', 'charge_l2'))
SELECT v.display_name AS car, bk.purpose, st.stall_code,
       CASE WHEN bk.booked_at_sim >= bk.opened_at THEN 'made inside the spell'
            WHEN lower(bk.during) <= bk.opened_at AND bk.state IN ('active', 'done', 'interrupted') THEN 'charging when it opened'
            ELSE 'made before, held into it' END AS kind,
       to_char(bk.booked_at_sim AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS booked_ct,
       to_char(lower(bk.during) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS window_ct,
       bk.state, bk.release_reason,
       to_char(bk.released_at AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS released_ct,
       round((extract(epoch FROM (LEAST(bk.live_until, COALESCE(bk.closed_at, (SELECT t1 FROM run)))
                                  - GREATEST(bk.booked_at_sim, bk.opened_at))) / 60)::numeric, 1) AS min_live_inside_spell
  FROM bk JOIN public.stalls st ON st.id = bk.stall_id JOIN public.vehicles v ON v.id = bk.vehicle_id
 WHERE bk.booked_at_sim < COALESCE(bk.closed_at, (SELECT t1 FROM run)) AND bk.live_until > bk.opened_at
 ORDER BY bk.opened_at, bk.booked_at_sim;
-- READ: pending.

\echo '=== 0412 §28c — the repair: its service-bay booking against the first window free when it was made, the bay, and the charge after ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
cfg AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'config'->'to'->'exception' AS exc,
         public.ottoq_vehicle_fault_open(e.payload->'diff'->'config'->'to') AS open_after
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.sim_clock_at > run.t0
     AND e.payload->'diff' ? 'config'),
chg AS (SELECT cfg.*, COALESCE(lag(open_after) OVER (PARTITION BY vehicle_id ORDER BY seq), false) AS open_before FROM cfg),
spell AS MATERIALIZED (
  SELECT o.vehicle_id, o.at AS opened_at, o.seq AS opened_seq, o.exc,
         (SELECT min(c.at) FROM chg c WHERE c.vehicle_id = o.vehicle_id AND c.seq > o.seq AND NOT c.open_after) AS closed_at
    FROM chg o WHERE o.open_after AND NOT o.open_before),
rb AS MATERIALIZED (
  SELECT s.vehicle_id, s.opened_at, s.closed_at, b.booking_id, b.stall_id, b.booked_at_sim, b.during, b.state,
         b.release_reason, b.need_atom
    FROM spell s JOIN public.ottoq_stall_bookings b ON b.vehicle_id = s.vehicle_id AND b.sim_run_id = (SELECT id FROM run)
   WHERE b.purpose = 'service' AND b.booked_at_sim >= s.opened_at AND (s.closed_at IS NULL OR b.booked_at_sim <= s.closed_at)),
ff AS (
  SELECT rb.booking_id,
         (SELECT min(m) FROM generate_series(date_trunc('minute', rb.booked_at_sim), lower(rb.during), interval '1 minute') m
           WHERE EXISTS (
             SELECT 1 FROM public.stalls sb
              WHERE sb.depot_id = '11111111-1111-1111-1111-111111111111' AND sb.stall_type::text = 'service_bay'
                AND NOT EXISTS (
                  SELECT 1 FROM public.ottoq_stall_bookings o
                   WHERE o.stall_id = sb.id AND o.sim_run_id = (SELECT id FROM run) AND o.booking_id <> rb.booking_id
                     AND o.booked_at_sim <= rb.booked_at_sim
                     AND NOT (o.state IN ('released', 'superseded')
                              AND COALESCE(o.released_at, o.booked_at_sim) <= rb.booked_at_sim)
                     AND o.during && tstzrange(m, m + (upper(rb.during) - lower(rb.during)), '[)')))) AS first_free
    FROM rb)
SELECT v.display_name AS car, rb.need_atom, st.stall_code AS bay,
       to_char(rb.booked_at_sim AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS booked_ct,
       round((extract(epoch FROM (rb.booked_at_sim - rb.opened_at)) / 60)::numeric, 1) AS min_after_fault,
       to_char(lower(rb.during) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS window_ct,
       round((extract(epoch FROM (upper(rb.during) - lower(rb.during))) / 60)::numeric, 1) AS window_min,
       to_char(ff.first_free AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS first_free_when_booked_ct,
       round((extract(epoch FROM (lower(rb.during) - ff.first_free)) / 60)::numeric, 1) AS min_after_first_free,
       rb.state, rb.release_reason,
       (SELECT to_char(min(e.sim_clock_at) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') FROM public.ottoq_events e
         WHERE e.sim_run_id = (SELECT id FROM run) AND e.entity_id = rb.vehicle_id AND e.event_type = 'vehicle.state_changed'
           AND e.payload->'diff'->'current_state'->>'to' = 'in_service_bay' AND e.sim_clock_at >= rb.booked_at_sim) AS entered_bay_ct,
       (SELECT to_char(min(e.sim_clock_at) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') FROM public.ottoq_events e
         WHERE e.sim_run_id = (SELECT id FROM run) AND e.entity_id = rb.vehicle_id AND e.event_type = 'twin.service_completed'
           AND jsonb_typeof(e.payload->'fault_repaired') = 'object' AND e.sim_clock_at >= rb.booked_at_sim) AS repaired_ct,
       (SELECT to_char(min(e.sim_clock_at) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') FROM public.ottoq_events e
         WHERE e.sim_run_id = (SELECT id FROM run) AND e.entity_id = rb.vehicle_id AND e.event_type = 'vehicle.state_changed'
           AND e.payload->'diff'->'current_state'->>'to' IN ('charging_dcfc', 'charging_l2')
           AND rb.closed_at IS NOT NULL AND e.sim_clock_at >= rb.closed_at) AS first_charge_after_ct
  FROM rb JOIN ff USING (booking_id) JOIN public.stalls st ON st.id = rb.stall_id JOIN public.vehicles v ON v.id = rb.vehicle_id
 ORDER BY rb.opened_at, rb.booked_at_sim;
-- READ: pending.

\echo '=== 0412 §28d — step (6)''s passes, and amend_plan on each faulted car inside its spell ==='
SELECT to_char(e.sim_clock_at AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS at_ct,
       (e.payload->>'routed')::int AS routed,
       (e.payload->>'charge_bookings_released')::int AS charge_bookings_released,
       (e.payload->>'charger_reservations_cleared')::int AS chargers_unreserved,
       (e.payload->>'replanned_repair_first')::int AS replanned_repair_first,
       (e.payload->>'bay_bookings_released')::int AS bay_bookings_released,
       (SELECT string_agg(DISTINCT v.display_name, '; ')
          FROM jsonb_array_elements(COALESCE(e.payload->'cars', '[]'::jsonb) || COALESCE(e.payload->'replanned_cars', '[]'::jsonb)) c
          JOIN public.vehicles v ON v.id = (c->>'vehicle_id')::uuid) AS cars
  FROM public.ottoq_events e
 WHERE e.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2' AND e.event_type = 'ottoq.faulted_car_routed_to_repair'
 ORDER BY e.sim_clock_at;
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
cfg AS MATERIALIZED (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS at, e.event_seq AS seq,
         e.payload->'diff'->'config'->'to'->'exception' AS exc,
         public.ottoq_vehicle_fault_open(e.payload->'diff'->'config'->'to') AS open_after
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'vehicle.state_changed' AND e.sim_clock_at > run.t0
     AND e.payload->'diff' ? 'config'),
chg AS (SELECT cfg.*, COALESCE(lag(open_after) OVER (PARTITION BY vehicle_id ORDER BY seq), false) AS open_before FROM cfg),
spell AS MATERIALIZED (
  SELECT o.vehicle_id, o.at AS opened_at, o.seq AS opened_seq, o.exc,
         (SELECT min(c.at) FROM chg c WHERE c.vehicle_id = o.vehicle_id AND c.seq > o.seq AND NOT c.open_after) AS closed_at
    FROM chg o WHERE o.open_after AND NOT o.open_before)
SELECT v.display_name AS car, to_char(s.opened_at AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS spell_from_ct,
       count(d.decision_id) AS amend_plan_inside_spell,
       round((sum((d.enacted_action->>'shift_s')::numeric) / 60)::numeric, 1) AS shifted_min,
       to_char(min(d.sim_clock) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS first_ct,
       to_char(max(d.sim_clock) AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS last_ct
  FROM spell s JOIN public.vehicles v ON v.id = s.vehicle_id
  LEFT JOIN public.ottoq_decisions d ON d.sim_run_id = (SELECT id FROM run) AND d.entity_id = s.vehicle_id
        AND d.resolved_action_context = 'itinerary_amended' AND d.sim_clock >= s.opened_at
        AND (s.closed_at IS NULL OR d.sim_clock < s.closed_at)
 GROUP BY v.display_name, s.opened_at
 ORDER BY s.opened_at;
-- READ: pending.

-- ══ §29 G293 RE-DIAGNOSED: WHO TAKES A CHARGER A CAR AHEAD IN THE LINE WAS REFUSED ════════════════════════════════════
--
--   0411 §22 counted 11 overtakings seated by the in-kernel L2 optimizer (`greedy_constrained`) and G293 blamed its order
--   (lowest charge first, gate cars only). Measured live on this run at sim 6:24 and 6:33 AM, that is not the mechanism.
--   The decide path's cursor walks the line in order (immediate dispatch, then the banked response ratio) and asks, per
--   car, for a reservation, then the optimizer's proposal for that car, then the heuristic; the optimizer only chooses
--   which charger a gate car is offered. In both cases the charger went to a car whose plan had booked it on the calendar
--   20 minutes earlier (`charge_l2`, booked 6:02 and 6:09 AM), and the 28 and 25 cars ahead of it in the same tick were
--   refused `no_compatible_available_stall`: the gate refuses a charger another car's live booking covers. The calendar is
--   claimed by the booker, which the placer (`ottoq.ottoq_place_unplaced_vehicles`) runs every tick for cars with an
--   unbooked leg `ORDER BY vehicle_id` with `LIMIT 60`: when the chargers are saturated, the next free window goes to the
--   unbooked car with the lowest id, not to the head of the line.
--
--   Per charge seating over the run: by what seated the car (`source`), how many had a car ahead of them in the same
--   tick's cursor refused for want of a charger, and how many of those sat on a charge booking of their own made before
--   that tick. A seating on its own earlier booking with refused cars ahead is the calendar serving a different order from
--   the line; the immediate dispatches are served first by design, and a later car on a charger no car ahead could take
--   (inlet, stall type) is no overtaking at all.

\echo '=== 0412 §29 — charge seatings with a car ahead in the line refused in the same tick, by what seated the later car ==='
WITH run AS (SELECT '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'::uuid AS id),
seat AS (
  SELECT d.tick_seq, d.decision_seq, d.entity_id AS vehicle_id, d.sim_clock,
         (d.enacted_action->>'stall_id')::uuid AS stall_id, COALESCE(d.enacted_action->>'source', 'kernel') AS source
    FROM public.ottoq_decisions d JOIN public.stalls st ON st.id = (d.enacted_action->>'stall_id')::uuid, run
   WHERE d.sim_run_id = run.id AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
     AND st.stall_type::text IN ('dcfc', 'l2')),
ahead AS (
  SELECT s.tick_seq, s.decision_seq, count(a.decision_id) AS refused_ahead
    FROM seat s JOIN public.ottoq_decisions a
      ON a.sim_run_id = (SELECT id FROM run) AND a.tick_seq = s.tick_seq AND a.action_context = 'stall_assignment'
     AND a.decision_seq < s.decision_seq AND a.outcome_status = 'noop_no_candidate'
   GROUP BY 1, 2),
own AS (
  SELECT s.tick_seq, s.decision_seq,
         EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                  WHERE b.sim_run_id = (SELECT id FROM run) AND b.stall_id = s.stall_id AND b.vehicle_id = s.vehicle_id
                    AND b.purpose IN ('charge_dcfc', 'charge_l2') AND b.booked_at_sim < s.sim_clock
                    AND b.during @> s.sim_clock) AS on_own_booking
    FROM seat s)
SELECT s.source, count(*) AS seatings,
       count(*) FILTER (WHERE COALESCE(ah.refused_ahead, 0) > 0) AS with_a_refused_car_ahead,
       count(*) FILTER (WHERE COALESCE(ah.refused_ahead, 0) > 0 AND o.on_own_booking) AS of_which_on_own_earlier_booking,
       sum(COALESCE(ah.refused_ahead, 0)) AS refused_cars_ahead
  FROM seat s LEFT JOIN ahead ah USING (tick_seq, decision_seq) JOIN own o USING (tick_seq, decision_seq)
 GROUP BY 1 ORDER BY 2 DESC;
-- READ: pending.

--   §29b: the `reservation_honoured` seatings above with refused cars ahead were, at sim 6:58 AM, all three standard cars
--   recalled and still on their way back when the engine reserved them a free fast charger (at 4:32, 4:32 and 6:33 AM;
--   they arrived 1 to 21 minutes later). Two functions reserve a charger for a returning car:
--   `ottoq.ottoq_sim_prearrival_contracts` (backstop 2: any free charger for an en-route car with a charge to do, TTL the
--   ETA plus 40 minutes, refreshed while it approaches; its dial `prearrival_charge_yields_to_solver`, 0339, is 0, which
--   keeps that behaviour) and `ottoq.ottoq_reoptimize_reservation_book` (moves a returning car below 45% from its reserved
--   L2 to a free fast charger). Per charger reserved while its car was deployed or driving back: how long it stood
--   reserved and empty until a car took it or the reservation was cleared, and the charge seatings refused meanwhile.

\echo '=== 0412 §29b — chargers reserved for a car still on its way back: how long each stood empty, and the refusals meanwhile ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '4b0999db-a9ef-4b35-b3e2-c985d1a259f2'),
res AS MATERIALIZED (
  SELECT e.entity_id AS stall_id, (e.payload->'diff'->'reserved_by'->>'to')::uuid AS vehicle_id, e.sim_clock_at AS at,
         e.event_seq AS seq
    FROM public.ottoq_events e, run
   WHERE e.sim_run_id = run.id AND e.event_type = 'stall.state_changed'
     AND jsonb_typeof(e.payload->'diff'->'reserved_by'->'to') = 'string'),
enr AS MATERIALIZED (
  SELECT r.*, st.stall_type::text AS stype,
         (SELECT e2.payload->'diff'->'current_state'->>'to' FROM public.ottoq_events e2, run
           WHERE e2.sim_run_id = run.id AND e2.entity_id = r.vehicle_id AND e2.event_type = 'vehicle.state_changed'
             AND e2.payload->'diff' ? 'current_state' AND e2.event_seq <= r.seq
           ORDER BY e2.event_seq DESC LIMIT 1) AS veh_state_then,
         (SELECT min(e3.sim_clock_at) FROM public.ottoq_events e3, run
           WHERE e3.sim_run_id = run.id AND e3.entity_id = r.stall_id AND e3.event_type = 'stall.state_changed'
             AND e3.event_seq > r.seq
             AND (e3.payload->'diff' ? 'current_vehicle_id' OR e3.payload->'diff' ? 'reserved_by')) AS ended_at
    FROM res r JOIN public.stalls st ON st.id = r.stall_id
   WHERE st.stall_type::text IN ('dcfc', 'l2')),
held AS (
  SELECT n.*, COALESCE(n.ended_at, (SELECT t1 FROM run)) AS until_at FROM enr n WHERE n.veh_state_then IN ('deployed', 'en_route_to_depot')),
refused AS (
  SELECT d.sim_clock FROM public.ottoq_decisions d, run
   WHERE d.sim_run_id = run.id AND d.action_context = 'stall_assignment' AND d.outcome_status = 'noop_no_candidate')
SELECT h.stype, count(*) AS reservations, count(DISTINCT h.vehicle_id) AS cars,
       round((sum(extract(epoch FROM (h.until_at - h.at))) / 60)::numeric, 1) AS charger_min_held_empty,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (h.until_at - h.at))) / 60)::numeric, 1) AS p50_min,
       round((max(extract(epoch FROM (h.until_at - h.at))) / 60)::numeric, 1) AS max_min,
       sum((SELECT count(*) FROM refused f WHERE f.sim_clock >= h.at AND f.sim_clock < h.until_at)) AS refusals_while_held
  FROM held h
 GROUP BY h.stype ORDER BY h.stype;
-- READ: pending.
