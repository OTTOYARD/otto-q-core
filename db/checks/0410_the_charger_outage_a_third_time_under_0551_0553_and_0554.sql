-- 0410  **The charger outage a third time, under 0551, 0553 and 0554: a fault keeps a car's place in the charge line, a
--        car waiting at the gate is escalated, an empty bay is not held for a car that cannot come, and bay work is done
--        in a bay.** (G279, G282, G283, G284, G286; found here: G288, G289, G290)
--
--       Written on 2026-09-28 (CT). Read-only. The run is ab8075a3-4001-45b5-b9e2-747033ad2273: busy_day at 8x under 0551 (applied 1:08 PM CT)
--       and 0553 + 0554 (applied together at 1:44 PM CT), on 0405bf42's seed (1092115219118377967), sim day and start
--       minute (Monday 2026-09-28, 4:26 AM CT). I started it at 19:16 UTC (2:16 PM CT), with no certification in
--       flight and the canon at 9 of 9 under the 0553/0554 floor. It repeats 0409's stress test in the twin (rule 10).
--
--       **The designed difference, as in 0408 and 0409.** A one-shot pg_cron job (`ottoq_0410_inject_dcfc_outage_once`,
--       job 780) takes three DC fast chargers down for 120 sim-minutes through the cockpit's door,
--       `ottoq_twin_inject_charger_fault`, once the run passes sim 7:39 AM CT (0409's outage began at 7:40:35). It records
--       what it did on the run's payload (`stress_injection_0410`, §17a) and unschedules itself.
--
--       **What it tests.** Each finding 0409 left open, against the fix written for it:
--         - G279 (0551 (a)-(c)): a car re-queued by a fault keeps the wait it had, so a car that arrives after the fault
--           does not charge before it (§16b, §22);
--         - G282 (0551 (d)): a car at the gate below its target that has waited 240 minutes is escalated to a person
--           (§18, §23);
--         - G284 (0551 (e)): the cockpit's queue is the line the engine serves (§25, live);
--         - G283 (0553): a refused wash-bay or service-bay seat frees a bay held for cars that cannot come (§19c, §24);
--         - G286 (0554): every bay visit is in a bay (§21).
--       And, as before, rule 9 (§2, §16) and the outage itself (§17).
--
--       **Not a paired test.** 0408's caveat holds. The runs share the seed, but a charger's fault card is keyed on the
--       car, the stall and the minute its session starts (0058), and a live run's ticks follow the wall clock. eff13379 was
--       purged when this run started; the figures §0 and §22 quote from it were read before the start. A difference from
--       it is read against §11b first.
--
--       **What the end reads found (read 3:30-3:50 PM CT, after the run completed at 3:28 PM CT).** Every fix held for the
--       whole day. G279: all 11 cars a fault interrupted below 99% charged again, 1.0 to 98.5 minutes later, and a later
--       arrival went first 13 times, against 179 times and six cars never recharged on eff13379 (§16, §22). G282: 52
--       escalations, 41 of them cars at the gate, and every wait that reached 240 minutes was escalated once (§4, §7b, §18,
--       §23). G283: the needs card seated 12 cars straight after a yield and was refused no wash-bay seat after 8:40 AM
--       (§19c, §24). G286: 90 bay visits, all 90 in a bay (§21). Rule 9 held as §2 measures it: 121 departures, none below
--       99%, none with an atom open, and no charge left short at a fault (§16). But the fleet worked less: KPI 1 134.1
--       against 153.36, and 63.2% of demand unmet against 57.2% (§1). The reads found why, and a more serious defect:
--         - G289 (§26): the gate's own 45-minute patience flag (`deploy_gate_stuck`) sends a finished car to the service
--           bay through the wash or detail bay's exit. 6 of 25 service-bay visits did nothing but take the flag off, and
--           36.7 of the 70.2 car-hours staged for a bay (16.3 on eff13379) were cars at 100% with every atom done,
--           waiting for that seat. Before 0554 those visits happened in no bay and cost staff time; now they queue for the
--           depot's two service bays;
--         - G290 (§27): Waymo-AV-011 left at 1:33:51 PM with a critical, immobilizing steering/brake fault unrepaired. The
--           readmit path returned it to service from emergency staging, and the departure test reads only the charge and
--           the card's atoms, so §2's zeros could not see it. Rule 9 says no car leaves with a service still needed, ever.
--       Also: the cockpit's charge queue leaves out staged cars while no charger is free, and cars holding a reservation
--       (G288, §25); and 39 morning wash-bay refusals had an empty bay free on the calendar and a record that cannot say
--       which gate refused them (§19c).

-- ══ §0 BEFORE: eff13379 (0409), THE SAME DAY AND THE SAME OUTAGE UNDER 0550 ═══════════════════════════════════════════
--
--     §1  KPI 1 153.36 · KPI 2 3.57 · peak site kW 912.8 · KPI 4 1.283 · KPI 5 p50 28.6, p95 290.7 min · returns unserved
--         45. Charge wait (visits) p50 53.2, p95 326.6; 154 of 208 charged. Supply gap 57.2% of demand car-hours unmet.
--     §2  133 departures, 0 below 99%, 0 with a service open.   §3  0 door refusals, 0 tick failures, 0 floor rejections.
--     §4  7 escalations, all `waiting_for_a_charger`, all staged; none at the gate.
--     §11 fast chargers 86.5% of nameplate time, L2 95.3%; 15 twin faults and the 3 injected.
--     §15 43.1% of fleet time waiting for a charger (35.6% at the gate, 7.5% staged); 16.0 car-hours in a bay state in no bay.
--     §16 18 faults, none left short. 16 below 99% erased 1,568.1 minutes of accumulated wait (G279); 6 cars at 40-96% were
--         not recharged by the end, up to 423.5 minutes after their faults.
--     §17 each injected car charged again 86.5, 116.9 and 138.4 minutes after the fault, and left at 100%.
--     §18 127 gate stays began below target; 32 reached 240 minutes (longest 371.6); none was escalated (G282).
--     §19c 332 refused wash-bay seats (136 deep cleans, 196 washes); none with all three bays physically full (G283).
--     §21 93 bay visits, 34 in no bay: 960 of 2,008 bay-minutes (G286).
--     §23 (read before the purge) the 7 escalations carry no `at`; of the 32 gate stays at 240 minutes, none was told.
--     §24a (read before the purge) the needs-card seat got a bay 45 times and was refused 342: deep cleans 12 and 136,
--         washes 29 and 196, service 4 and 10. No seat came after a yield (0553 did not exist).
--     §22 (read before the purge, 2026-09-28 13:55 CT) of the 16 faults below 99%, 10 cars charged again; 179 times a car
--         that arrived at the gate after a fault started a charge before the faulted car did. Waymo-AV-035 (L2, 40%):
--         57, never recharged in 423.5 minutes. Waymo-AV-004 26, Tesla-AV-043 24, Waymo-AV-007 23, Waymo-AV-037 16.
--   Must read here:
--     - §2 0 and 0; §3 0, 0 and 0; §16 0 left short; §17 every injected session faulted, every car re-queued, each charger
--       out for its whole repair;
--     - §18 / §23: every gate wait below target that reaches 240 minutes escalated once;
--     - §21: 0 visits in no bay;
--     - §22: far fewer later arrivals charged ahead of a faulted car;
--     - §24: yields that free a bay, and a refused seat only where no hold could give way.

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The scorecard, for the shape of the day rather than a comparison: what was demanded, what was deployed, and where
--   cars waited.

\echo '=== 0410 §1 — the run and its scorecard ==='
SELECT r.sim_run_id, r.run_by, r.status, r.random_seed, r.sim_clock_start, r.sim_clock_current, r.tick_count,
       r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273';
SELECT public.ottoq_kpi_five('ab8075a3-4001-45b5-b9e2-747033ad2273');
SELECT public.ottoq_kpi_charge_wait('ab8075a3-4001-45b5-b9e2-747033ad2273');
SELECT public.ottoq_kpi_supply_gap('ab8075a3-4001-45b5-b9e2-747033ad2273') - 'by_hour_ct';
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): the run completed at 20:28 UTC (3:28 PM CT) after 1,100 ticks, sim
--   4:26 AM to 1:53 PM. KPI 1 134.1 (eff13379 153.36) · KPI 2 3.68 (3.57) · peak site kW 1,164.3 (912.8) · KPI 4 1.308
--   (1.283) · KPI 5 p50 14.7, p95 299.3 min (28.6, 290.7) · returns unserved 40 (45). Charge wait (visits) p50 62.2,
--   p95 389.5 (53.2, 326.6); 144 of 195 charged (154 of 208) and 51 still waiting at the end, 221.4 minutes so far at
--   the median. Supply gap 63.2% of 361.1 demand car-hours unmet (57.2%), peak shortfall 42 cars. §11b first: the twin
--   drew 12 charger faults to eff13379's 15. The car-hours that did not go to work are in §15 and §26: 70.2 car-hours
--   staged for a bay against 16.3, and 36.7 of them cars carrying the gate's own flag (G289). The rise in peak kW is
--   not examined here.

-- ══ §2 RULE 9 STILL HOLDS: NO DEPARTURE WITH A SERVICE OPEN OR A CHARGE SHORT ═════════════════════════════════════════
--
--   0402 §2's query. Both must be 0.

\echo '=== 0410 §2 — departures, and any that left unfinished ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (live, 20:06 UTC; sim 11:04 AM): 89 departures, 0 below 99% (min 99), 0 left with open work.
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 121 departures after the boot, 0 below 99% (min 99), 0 with an
--   atom open. But one of the 121 left with a fault open: Waymo-AV-011 deployed at 1:33:51 PM carrying a critical,
--   immobilizing `steering_brake_fault` that nothing had repaired (§27, G290). This query reads the card's atoms and
--   the charge; the fault is in `config.exception`, which neither this query nor the departure test
--   (`public.ottoq_departure_clear`) reads.

-- ══ §3 THE DOOR AND THE FLOOR (0544): NEITHER SHOULD EVER FIRE ════════════════════════════════════════════════════════

\echo '=== 0410 §3 — door refusals and floor rejections ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.dispatch_refused_unfinished') AS door_refusals,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed') AS tick_failures,
       count(*) FILTER (WHERE e.event_type = 'sim_tick_failed' AND e.payload::text LIKE '%0544 (CLAUDE.md rule 9)%') AS floor_rejections
  FROM public.ottoq_events e WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273';
-- READ (19:26 UTC, 2:26 PM CT; sim 5:43 AM, tick 140): 0 door refusals, 0 tick failures, 0 floor rejections.
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 0 door refusals, 0 tick failures, 0 floor rejections over the
--   whole run.

-- ══ §4 ESCALATIONS: THE GATE'S (G269) AND THE WAITS FOR A CHARGER OR THE SERVICE BAY (0546 (d), G274) ══════════════════
--
--   Every escalation, with its reason. A gate escalation (`must_do_work_open`) is a car held for bay work or its
--   check; 0545 (a) times it from the car's last state change, so no state change should fall inside its counted
--   hold. A remedy-wait escalation (0546 (d), `waiting_for_a_charger` or `waiting_for_the_service_bay`) is a car on
--   need_charge or need_service whose last state change is 240 minutes old; (a) makes that the start of its wait, so
--   again no state change should fall inside it. The `remedy_wait` stamp holds the run and the start of the wait, so a
--   car is escalated once per wait: `per_car_and_start` must be 1 everywhere.

\echo '=== 0410 §4 — escalations, by reason, and whether the car changed state inside the counted wait ==='
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
 WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e.event_type = 'twin.deploy_gate_escalated'
 ORDER BY e.sim_clock_at;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 52 escalations, each once per wait (`per_car_and_start` is 1
--   everywhere): 47 `waiting_for_a_charger` (41 at the gate, 6 staged) and 5 `waiting_for_the_service_bay` (all
--   staged), held 240.0-241.6 minutes. 42 show no state change inside the counted wait. Of the 10 that do, 4 are cars
--   at the gate whose arrival falls inside by the 0.1-minute rounding of `held_min`, and 6 are staged cars whose wait
--   spans a move by design (0551's bank carries a charge wait across moves and faults). Four of the five service-bay
--   escalations list nothing `missing`: Tesla-RT-002, Tesla-RT-004, Waymo-AV-039 and Waymo-AV-014 were at 100% with
--   every atom done, waiting for the service bay on the gate's own `deploy_gate_stuck` flag (§26, G289). The fifth,
--   Zoox-AV-079, owed a `fault_repair`. eff13379: 7 escalations, none at the gate.

-- ══ §5 G270: WHO GOT THE BAY SEATS ═══════════════════════════════════════════════════════════════════════════════════

\echo '=== 0410 §5 — needs-card seats by the seated car''s deploy time, and the gate''s holds ==='
SELECT d.enacted_action->>'purpose' AS purpose,
       CASE WHEN d.context_frame->>'minutes_to_deploy' IS NULL THEN 'no deploy time'
            WHEN (d.context_frame->>'minutes_to_deploy')::int < 0 THEN 'late'
            ELSE 'due later' END AS seated_car,
       count(*) AS seats,
       min((d.context_frame->>'minutes_to_deploy')::int) AS min_mtd, max((d.context_frame->>'minutes_to_deploy')::int) AS max_mtd
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND d.enacted_action->>'source' = 'needs_card' AND d.outcome_status = 'enacted'
 GROUP BY 1, 2 ORDER BY 1, 2;
WITH holds AS (
  SELECT e.entity_id, max((e.payload->'diff'->'config'->'to'->'deploy_gate'->>'held_min')::numeric) AS held
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate' ? 'held_min'
     AND e.payload->'diff'->'config'->'to'->'deploy_gate'->>'run' = e.sim_run_id::text   -- not a prior run's stamp
   GROUP BY 1)
SELECT count(*) AS cars_held, round(avg(held)) AS mean_max_hold_min, max(held) AS longest_hold_min,
       count(*) FILTER (WHERE held >= 240) AS reached_the_cap
  FROM holds;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): the needs card seated 64 cars in a bay: 34 washes (20 due later,
--   13 late, 1 with no deploy time), 18 deep cleans (9 and 9) and 12 service visits (5 and 7). Late cars were seated as
--   often as cars due later (G270 holds). The readiness gate held 83 cars: 23 minutes at the mean of each car's longest
--   hold, 201.3 at the longest, and no hold reached the 240-minute cap.

-- ══ §6 WHAT HOLDING COSTS ═════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0410 §6 — the gate, staging and the bays ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS recheck_events,
       count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_escalated') AS escalated_to_a_person,
       max((e.payload->>'held')::int) FILTER (WHERE e.event_type = 'twin.deploy_gate_summary') AS gate_held_max,
       max((e.payload->>'overflow')::int) FILTER (WHERE e.event_type = 'twin.staging_overflow') AS staging_overflow_max
  FROM public.ottoq_events e WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273';
SELECT (SELECT jsonb_object_agg(to_state, k) FROM (
          SELECT e.payload->'diff'->'current_state'->>'to' AS to_state, count(*) AS k
            FROM public.ottoq_events e WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
           GROUP BY 1) q) AS bay_entries;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 35 departure rechecks; 52 escalations to a person (§4); the gate
--   held at most 25 cars at once; staging overflow peaked at 52. Bay entries: 41 wash, 24 detail, 25 service (90;
--   eff13379 93).

-- ══ §7 G271: NO CAR STARVES WAITING FOR A CHARGER OR THE SERVICE BAY ═════════════════════════════════════════════════
--
--   0403 §7's waits, widened to need_service, with the car-hours and the waits that reached 240 minutes. A wait starts
--   where a staged car's step becomes need_charge (or need_service) and ends at its next change of state or step. The
--   teardown's `offline` at the run's last sim minute is not an end. The SoC at the start is the stream's last SoC for
--   the car at or before it. `visit` is the urgency of the car's latest visit at the wait's start, or 'no visit'.
--   Under 0546 (a) and (c) no group should be passed over all day: a boot car with no visit now competes on its ratio,
--   and a waiting car's ratio rises with its wait.

\echo '=== 0410 §7 — waits on need_charge and need_service, by SoC at the start and by how each ended ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): waits for a charger that ended at one: 46 below 90% (44 cars; p50
--   6.9, p95 117.7, max 438.3 minutes; 33.7 car-hours; 2 reached 240) and 35 top-offs at 90-98% (p50 1.7, p95 59.5); 27
--   more at 99-100% went back to the gate within 1.7 minutes. Four waits below 90% were still open at the end (17-49%;
--   20.9 car-hours; the longest 555.9 minutes), and one ended in a tow: Waymo-AV-007, at 20%, waited 285.2 minutes and
--   was taken offline for a vehicle fault at 9:22 AM (§27). Waits for a bay: 16 ended in the service bay after a p50 of
--   139.7 minutes (p95 276.4, max 289.0; 36.5 car-hours; 3 reached 240), and 11 were still open at the end, every car
--   at 100% (p50 138.6, max 273.5; 25.5 car-hours; 2 reached 240). The other waits for a bay were short: 81 back to the
--   gate within 9.2 minutes, 8 into a wash bay and 6 into a detail bay.

--   The same waits still open at the teardown, by whether the car had a visit (0546 (c)), and whether each wait that
--   reached 240 minutes was escalated once in its stay (0546 (d)). A stay is the car's time in staged_awaiting_service
--   since its last state change, which is what (d) times; one stay can hold more than one wait.

\echo '=== 0410 §7b — the waits still open at the end by visit, and the 240-minute waits against their escalations ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): every wait that reached 240 minutes was escalated once in its
--   stay: on need_charge 3 that ended and 2 still open, on need_service 3 and 2. Of the 15 waits open at the end (4
--   need_charge, 11 need_service), the 11 under 240 minutes carry no escalation, as they should. Every waiting car had
--   a visit (0546 (c)). One wait that did not reach 240 had an escalation in its stay: Tesla-AV-042's, 98.3 minutes
--   from 54% after its 9:07 AM fault, whose wait 0551's bank carried across the fault from 6:17 AM.

-- ══ §8 G273: NO RELEASE KEEPS A FLAG THE GATE RAISED ═══════════════════════════════════════════════════════════════════
--
--   0403 §8's query. Under 0546 (b) a release drops `deploy_gate_stuck` and `deploy_gate_hard_cap` with its stamp, so
--   those two rows must read 0. A flag raised by anything else is kept, as before, and may appear.

\echo '=== 0410 §8 — gate releases that kept a flag ==='
WITH rel AS (
  SELECT e.entity_id, e.event_seq, e.payload->'diff'->'config'->'to'->>'flagged_issue_type' AS flag_type
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'config'->'from' ? 'deploy_gate'
     AND NOT (e.payload->'diff'->'config'->'to' ? 'deploy_gate')
     AND (e.payload->'diff'->'config'->'to'->>'flagged_issue')::boolean)
SELECT flag_type, count(*) AS releases_keeping_the_flag, count(DISTINCT entity_id) AS cars,
       count(DISTINCT entity_id) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_events e3
          WHERE e3.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e3.entity_id = rel.entity_id
            AND e3.event_type = 'vehicle.state_changed' AND e3.event_seq > rel.event_seq
            AND e3.payload->'diff'->'current_state'->>'to' = 'in_service_bay')) AS later_in_service_bay
  FROM rel GROUP BY flag_type ORDER BY flag_type;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): no rows: no release kept a flag the gate raised. The gate raised
--   `deploy_gate_stuck` 14 times on 14 cars. 8 of those flags were cleared by a service-bay visit, not by a release,
--   and 6 of those 8 visits did nothing else (§26, G289).

-- ══ §9 LIVE PROBE: NO STAGED CAR IS RE-STAMPED WITHOUT A STATE CHANGE (G272) ═══════════════════════════════════════════
--
--   0403 §9's probe. Under 0546 (a), STEP 0 stamps only a car it moves into staging, which is a state change, so no
--   staged car should appear. The deployed telemetry still stamps deployed cars with each SoC drain (0546 §4: measured,
--   not changed), so deployed rows are expected. Run while the run is live.

\echo '=== 0410 §9 — cars stamped this tick with no state change ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND status = 'running')
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
-- READ (19:26 UTC, sim 5:43 AM): 14 deployed cars re-stamped with their SoC drain, as expected (0546 §4); no staged car.

--   §9b, the same moment from the queue's side: every car on need_charge with the wait the charge cursor reads (sim now
--   minus `last_state_change`), by whether it has a visit and by its charge.

\echo '=== 0410 §9b — the charge queue and the wait each car reads ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273')
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
-- READ (end): the run was not probed with this query while it was live.

-- ══ §10 G271: WHO THE CHARGERS WENT TO, BY WHETHER THE CAR HAD A VISIT ══════════════════════════════════════════════════
--
--   0403 §10's query. On 4acf0b1d no car without a visit got a charger after 5:00 AM. Under 0546 (c) they compete on
--   their ratio, and a top-off's ratio is high, so they should appear from 5:00 AM on.

\echo '=== 0410 §10 — charge sessions by start time and by whether the car had a visit ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
s AS (
  SELECT o.vehicle_id, o.started_at, o.soc_start,
         (SELECT vn.urgency FROM public.ottoq_visit_needs vn
           WHERE vn.vehicle_id = o.vehicle_id AND vn.sim_run_id = r.sim_run_id AND vn.arrived_at <= o.started_at
           ORDER BY vn.created_at DESC LIMIT 1) AS urgency
    FROM public.ocpp_sessions o, r WHERE o.sim_run_id = r.sim_run_id)
SELECT CASE WHEN started_at < timestamptz '2026-09-28 10:00:00+00' THEN 'before 5:00 AM CT' ELSE 'from 5:00 AM CT' END AS started,
       COALESCE(urgency, 'no visit') AS car, count(*) AS sessions, min(soc_start) AS min_soc, max(soc_start) AS max_soc
  FROM s GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 181 charge sessions. Before 5:00 AM: 18 for immediate dispatches
--   (14-97%), 27 boot cars with no visit (78-97%) and 5 standard visits (86-98%). From 5:00 AM: 91 standard (21-98%),
--   38 immediate (12-97%), 1 with no visit (95%) and 1 on a tech hold (44%).

-- ══ §11 THE CHARGERS: HOW BUSY, HOW MANY FAULTED, AND WHAT WAS FREE WHILE CARS WAITED ═══════════════════════════════════
--
--   Session hours against nameplate time by charger kind; every fault with its repair time and how long its charger
--   stood before its next car; and, per hour, the cars waiting on need_charge beside the chargers free by the stall
--   pointer. A charger free while cars wait is either faulted (capacity lost to faults), between two cars (turnover),
--   or a gap in the schedule, which is the only one of the three that orchestration alone can close.

\echo '=== 0410 §11 — charger use by kind ==='
WITH r AS (SELECT sim_run_id, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): fast chargers 71 sessions, 82.1 hours, 86.8% of nameplate time
--   (eff13379 86.5%); L2 110 sessions, 255.4 hours, 90.1% (95.3%).

\echo '=== 0410 §11d — sessions by charger kind and by charge at the start ==='
WITH r AS (SELECT * FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): DCFC: 47 sessions from below 50% (23 immediate; 97.8 minutes to
--   finish on average; 68.5 charger-hours), 16 top-offs from 90% or more (14.4 minutes; 3.4 hours), 7 from 70-89% and 1
--   from 50-69%. L2: 66 from below 50% (22 immediate; 239.7 minutes; 213.4 hours), 22 top-offs (27.5 minutes; 9.3
--   hours), 20 from 70-89% (75.9 minutes) and 2 from 50-69% (neither finished by the end).

\echo '=== 0410 §11b — every charger fault, its repair time, and how long its charger stood before its next car ==='
WITH f AS (
  SELECT e.sim_clock_at AS at, o.stall_id, e.payload->>'reason' AS reason, (e.payload->>'repair_minutes')::numeric AS repair_min
    FROM public.ottoq_events e JOIN public.ocpp_sessions o ON o.id::text = e.entity_id::text
   WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e.event_type = 'charge.session_faulted')
SELECT s.stall_code, f.at AT TIME ZONE 'America/Chicago' AS fault_ct, f.reason, f.repair_min,
       round(extract(epoch FROM ((SELECT min(o2.started_at) FROM public.ocpp_sessions o2
                                   WHERE o2.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND o2.stall_id = f.stall_id AND o2.started_at > f.at)
                                 - f.at))::numeric / 60, 1) AS stood_until_next_car_min
  FROM f JOIN public.stalls s ON s.id = f.stall_id ORDER BY f.at;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 15 faulted sessions: 12 drawn by the twin (eff13379 15) and the 3
--   injected. DCFC: connector faults of 46 and 61 minutes, an aborted session (13), a thermal emergency (50), and the
--   three injected at 7:45:05 AM, each charger standing 122.4 minutes before its next car. L2: connector 56 and 10,
--   communication 10, aborted sessions 55 and 151, station hardware 268 and 225, and a ground fault at 5:23 AM whose
--   723-minute repair outlasted the run (NASH-L2-STALL-02 took no other car). Every other charger took its next car
--   within 1.2 minutes of its repair (3.6 after DCFC-04's thermal fault).

--   §11c counts cars at the gate too (`avg_at_gate`): the charge cursor reads them as well as staged cars on need_charge
--   (§15). A charger that reads free by the pointer may be faulted: §11b lists the faults.
\echo '=== 0410 §11c — per hour: cars waiting on need_charge or at the gate, and chargers free by the stall pointer ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): cars waiting for a charger, staged (21 and 18 an hour in the boot
--   hours, 5-6 from 6 AM on) and at the gate (25-51 an hour, 45-51 from 8 AM on), against chargers free by the pointer:
--   fast chargers 0.1-0.4 free from 7 to 11 AM (4-18 charger-minutes an hour while cars waited), 0.7 at noon and 0.4 at
--   1 PM; L2 1.3-4.0 free (66-242 minutes an hour). A pointer-free L2 is not always a usable one: three L2s were down
--   for long stretches (§11b: STALL-02 from 5:23 AM on, STALL-09 6:17-10:45 AM, STALL-01 9:07 AM-12:52 PM).

\echo '=== 0410 §11e — charger turnover: from a session''s end to the charger''s next car, by where the car went ==='
--   Completed sessions only (a faulted session's gap is its repair, §11b). `car_went` is the car's first state after
--   the session other than holding, waiting or charging. Since 0547 a fast charger whose car left for a bay takes its
--   next car as soon as one whose car left for departure does (921e349c: p50 1.3, mean 2.1, max 14.4).
WITH r AS MATERIALIZED (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): every completed session's charger took a next car: fast chargers
--   after p50 1.1 minutes when the car went to a bay (max 2.5) and 1.0 when it went to depart (max 14.9); L2 0.7 (max
--   5.7) and 0.9 (max 3.7). G276 and 0547 hold.

-- ══ §12 G276 STAYS FIXED: A CHARGER IS FREE ONCE ITS CAR HAS LEFT IT FOR A BAY ══════════════════════════════════════
--
--   0405 §12's queries, kept as a regression check. On 921e349c, ae0597b7 and 0405bf42, §12a read no episode and §12b read
--   no refusal with the car on no stall. Both must read 0 on a new day too. Refusals with the car on this stall are
--   the guard doing its job, and they remain. §12c is the live census G121 was found with, for probes while the run is live.

\echo '=== 0410 §12a — charger time stuck with a pointer to a car that left, from the stall stream ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): no rows: no charger time stuck with a pointer to a car that left.
--   G276 stays fixed.

\echo '=== 0410 §12b — the guard''s refusals, by where the car was when it asked ==='
WITH a AS (
  SELECT a.vehicle_id, (a.payload->>'from_stall')::uuid AS from_stall, (a.payload->>'requested_at_sim')::timestamptz AS at_sim,
         a.payload->>'state' AS state, s.stall_type::text AS from_kind, a.status
    FROM public.ottoq_ops_approvals a JOIN public.stalls s ON s.id = (a.payload->>'from_stall')::uuid
   WHERE a.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND a.payload->>'reason' = 'automated_reassignment'),
pos AS (
  SELECT a.*,
         (SELECT e.payload->'diff'->'current_stall_id'->>'to' FROM public.ottoq_events e
           WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e.entity_id = a.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_stall_id' AND e.sim_clock_at <= a.at_sim
           ORDER BY e.event_seq DESC LIMIT 1) AS car_stall_at_request
    FROM a)
SELECT from_kind, state, status,
       CASE WHEN car_stall_at_request IS NULL THEN 'car on no stall' WHEN car_stall_at_request = from_stall::text THEN 'car on this stall'
            ELSE 'car on another stall' END AS car_position,
       count(*) AS n
  FROM pos GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 86 automated reassignment requests off a charger. Refused with the
--   car on that charger: 79 L2 and 2 DCFC (the guard doing its job). Refused with the car on another stall: 3 DCFC, the
--   three injected cars at 7:45:05 AM, which the fault door had moved to staging stalls E019, E020 and E022 in the same
--   tick. None refused with the car on no stall; 2 L2 requests expired (one car on no stall, one on its charger).

\echo '=== 0410 §12c — live: a stall that reads available with a pointer set, and where its car is ==='
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
-- READ (end): the run was not probed with this query while it was live; §12a and §12b cover the day.

-- ══ §13 G278 STAYS FIXED: NO CAR HOLDS A BAY BEFORE ITS BOOKING ═══════════════════════════════════════════════════
--
--   0406 §13's queries. On 921e349c, before 0549, 4 early entries held the wash bays for 465 minutes. On ae0597b7, under
--   0549:
--     - §13a read no entry more than 5 minutes before its booking;
--     - §13b had nothing to list (the one early reservation, Waymo-AV-020's, had been moved to start when the car went in);
--     - §13c read no booking longer than its service and no car past its booking.
--   The same must hold here. §13c shows a stretched booking as a long one; a car that stays past its booking shows in the
--   last column.

\echo '=== 0410 §13a — bay entries against their bookings: how early the car went in, and the bay-minutes held before the window ==='
WITH c AS (
  SELECT c.vehicle_id, c.command_type, c.payload->>'purpose' AS purpose, c.issued_at,
         b.during, s.stall_type::text AS bay
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
    JOIN public.stalls s ON s.id = b.stall_id
   WHERE c.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed')
SELECT purpose, count(*) AS entries,
       count(*) FILTER (WHERE lower(during) > issued_at + interval '5 minutes') AS entered_over_5_min_early,
       round(max(extract(epoch FROM lower(during) - issued_at) / 60)::numeric, 1) AS max_early_min,
       round(sum(GREATEST(extract(epoch FROM lower(during) - issued_at), 0) / 60) FILTER (WHERE lower(during) > issued_at + interval '5 minutes')::numeric, 1) AS bay_minutes_held_before_the_window
  FROM c GROUP BY 1 ORDER BY 1;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 76 bay entries by command (34 washes, 18 deep cleans, 24 service
--   visits), none more than 5 minutes before its booking. G278 stays fixed.

\echo '=== 0410 §13b — the early entries, and the other cars'' bookings on the same bay while the early car sat there ==='
WITH c AS (
  SELECT c.vehicle_id, c.payload->>'purpose' AS purpose, c.issued_at, b.stall_id, b.during, s.stall_code
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
    JOIN public.stalls s ON s.id = b.stall_id
   WHERE c.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed' AND lower(b.during) > c.issued_at + interval '5 minutes'),
x AS (
  SELECT c.*,
         (SELECT min(e.sim_clock_at) FROM public.ottoq_events e
           WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e.entity_id = c.vehicle_id
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
         WHERE b2.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND b2.stall_id = x.stall_id
           AND b2.vehicle_id IS DISTINCT FROM x.vehicle_id
           AND b2.during && tstzrange(x.issued_at, COALESCE(x.left_bay_at, upper(x.during)))) AS other_bookings_while_it_sat
  FROM x JOIN public.vehicles v ON v.id = x.vehicle_id
 ORDER BY x.issued_at;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): no rows (no early entry).

\echo '=== 0410 §13c — every bay command''s booking and time in the bay, by purpose (a stretched booking shows as a long one) ==='
WITH c AS (
  SELECT c.vehicle_id, c.payload->>'purpose' AS purpose, c.issued_at, b.during
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload->>'booking_id','')::uuid
   WHERE c.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND c.command_type IN ('enter_wash', 'enter_service')
     AND c.status::text = 'executed'),
x AS (
  SELECT c.*,
         extract(epoch FROM upper(c.during) - lower(c.during)) / 60 AS booked_min,
         extract(epoch FROM (SELECT min(e.sim_clock_at) FROM public.ottoq_events e
                              WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e.entity_id = c.vehicle_id
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): washes booked 9 minutes at the median (max 10) and in the bay 9.3
--   (max 10.5); deep cleans 25 and 25.3 (max 26.2); service 40 and 40.3 (max 60 and 60.4). No car stayed past its
--   booking.

-- ══ §14 G195 RE-MEASURED: PARKING HOLDS THAT OUTLIVE THEIR CAR, AND WHETHER STAGING EVER BINDS ═══════════════════════
--
--   G195's open half is the parking holds (`temp_hold`, `perimeter_hold`) that stay on the calendar after their car has
--   left the stall; its remedy, the departure sweep (`space_departure_release_enabled`), is off. It costs nothing while
--   staging has room, so §14a counts the leak (0372 §2(c)'s query) and §14b whether staging ever came near full, every
--   ten sim-minutes, from the calendar: stalls with a live booking, and among them stalls whose booked car had left.

\echo '=== 0410 §14a — parking holds that outlived their car, over the whole run (0372 §2(c)) ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): parking holds that outlived their car: temp holds 113 of 142 not
--   renewed (1,659 stall-minutes; p50 14.1, max 44.4) and 113 of 211 renewed (907; p50 8.2, max 14.5); perimeter holds
--   10 of 12 not renewed (443; p50 30.2, max 119.5) and none of 4 renewed. 3,009 stall-minutes in all. G195 stays open.

\echo '=== 0410 §14b — staging stalls on the calendar every ten sim-minutes, and how many of them held a car that had left ==='
WITH r AS MATERIALIZED (SELECT sim_run_id AS run, sim_clock_start AS t0, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): of 113 staging stalls, at most 73 were on the calendar at once
--   (39.4 at the mean), and at most 14 of them held a car that had left (3.5 at the mean). Staging never came near
--   full, so the leak cost nothing today.

-- ══ §15 WHERE THE FLEET'S HOURS WENT ═══════════════════════════════════════════════════════════════════════════════════
--
--   0407 §15's query. Each car's time from the run's first minute to its last tick, split by what it was doing, taken
--   from the state and step each `vehicle.state_changed` event leaves it in. A staged car is split by its step. A car at
--   the gate has its own row. The decide tick's charge cursor reads cars at the gate as well as staged cars on need_charge,
--   so a car below its target at the gate is waiting for a charger too. §7 counts only the staged waits, so the
--   time spent waiting for a charger is roughly rows c and d together. The boot puts every car into a state at the first
--   minute, so the first half hour carries the boot's backlog.

\echo '=== 0410 §15 — car-hours by what the car was doing, over the run ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): at work 132.8 car-hours (12.1% of fleet time); at the gate 390.9
--   (35.6%); staged for a charger 70.8 (6.5%); charging 337.5 (DCFC 82.1, L2 255.4; 30.8%); staged for a bay 70.2
--   (6.4%; eff13379 16.3, 1.5%); staged to deploy 34.0 (3.1%); staged for departure 15.4; in a bay 31.0 (service 16.2,
--   detail 9.0, wash 5.8); offline for a vehicle fault 4.9 (emergency staged 4.1, tow requested 0.8). Waiting for a
--   charger: 42.1% of fleet time (eff13379 43.1%). No car-hours in a bay state in no bay (eff13379 16.0; §21). The rise
--   in time staged for a bay is mostly §26: 36.7 of the 70.2 car-hours were cars carrying the gate's own flag.

-- ══ §16 RULE 9 AT A CHARGER FAULT: EVERY INTERRUPTED CAR IS RE-QUEUED TO FINISH ═════════════════════════════════════
--
--   0407 §16's query. A charger fault is one of the two reasons rule 9 lets a charge end short, and only if the car is
--   re-queued to finish. For every faulted session this query takes the car's charge at the fault, its next session
--   (when, on what kind of charger, and how it ended) and its next dispatch. `left without resuming` is allowed only for
--   a car already at 99% or more at the fault (the charge rule treats the target minus 1 as charged, 0493). The last
--   column must be 0. On 0405bf42, the same day without the outage, it read 0 over 19 faults (§0).

\echo '=== 0410 §16 — every charger fault: what the car did next, and at what charge it left ==='
WITH r AS (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 15 faults, none left short. DCFC: 2 cars at 99% left without
--   resuming, as allowed; 4 resumed and finished (67-93% at the fault; waits p50 11.3, max 98.5 minutes); 1 was still
--   charging at the end (Waymo-AV-028, 41%). L2: 2 at 99% left; 5 resumed and finished (73-98%; p50 36.2, max 39.2); 1
--   was still charging at the end (Tesla-AV-042, 54%, back on after 98.3). eff13379: 6 cars at 40-96% were never
--   recharged, up to 423.5 minutes after their faults.


--   §16b, the same faults with the wait each car had behind it when the faulted session started. Before 0551 the charge
--   cursor measured a car's wait from its last state change, and a fault moves the car from charging back to staging, so
--   the fault erased that wait (G279). Under 0551 the wait is banked (`config.charge_wait`) and the cursor reads it, so
--   `waited_after_min` should be short for a car that had waited long before its fault. §22 counts who went ahead.

\echo '=== 0410 §16b — per fault: the wait before the faulted session, the charge it got, and the wait after ==='
WITH r AS (SELECT sim_run_id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 11 of the 15 faults hit a car below 99%, and each car charged
--   again 1.0 to 98.5 minutes later (p50 29.6). The longest waits after a fault were Waymo-AV-004's (98.5, injected)
--   and Tesla-AV-042's (98.3, station hardware). eff13379: the injected cars waited 86.5, 116.9 and 138.4, and six cars
--   never charged again. The wait before the faulted session shows the day's line: Waymo-AV-028 waited 465.7 minutes
--   from 4:26 AM at 22% for its first charge (escalated at 8:35 AM), and Tesla-AV-042 and Waymo-AV-033 151.8 and 142.0.

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

\echo '=== 0410 §17a — the injection''s receipt, from the run''s payload ==='
SELECT r->>'stall_code' AS charger, (r->>'ok')::boolean AS ok, (r->>'sessions_stopped')::int AS sessions_stopped,
       jsonb_array_length(COALESCE(r->'report'->'vehicles', '[]'::jsonb)) AS cars_replanned,
       to_char((r->>'faulted_at_sim')::timestamptz AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS faulted_ct,
       to_char((r->>'recovers_at_sim')::timestamptz AT TIME ZONE 'America/Chicago', 'HH12:MI:SS AM') AS recovers_ct,
       (r->>'repair_minutes')::numeric AS repair_min,
       (sr.payload->'stress_injection_0410'->>'at_real')::timestamptz AS injected_at_real_utc
  FROM public.ottoq_sim_runs sr
  CROSS JOIN LATERAL jsonb_array_elements(sr.payload->'stress_injection_0410'->'results') r
 WHERE sr.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'
 ORDER BY 1;
-- READ (19:45 UTC, 2:45 PM CT): job 780 fired once, at 19:42:00 UTC, and succeeded in 0.44 s: no deadlock (0552 holds).
--   It unscheduled itself. DCFC-STALL-01, -02 and -03, each `ok`: one session stopped, no car replanned, faulted at sim
--   7:45:05 AM CT with a 120-minute repair, due back at 9:45:05. That is 4.5 sim-minutes later than eff13379's 7:40:35:
--   the job fires on the minute, and a real minute is 8 sim-minutes at 8x.

\echo '=== 0410 §17b — per injected charger: the stopped session, where its car went, and the charger''s outage ==='
WITH run AS MATERIALIZED (
  SELECT r.sim_run_id AS id, r.sim_clock_current AS t1, r.payload->'stress_injection_0410' AS inj
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (19:47 UTC, 2:47 PM CT; sim 8:17 AM): all three sessions `faulted`, `fault.operator_injected`; each car went to
--   `staged_awaiting_service`; each charger reads `Faulted` and its stall `maintenance`.
--   - DCFC-STALL-01: Tesla-AV-069, 48% → 92%. Plugged in again at 7:49:20 AM, 4.3 minutes after the fault, finished at
--     8:02:31 and left at 8:03:55 at 100%.
--   - DCFC-STALL-03: Waymo-AV-040, 49% → 67%. Charging again on a fast charger at 8:17 (75%).
--   - DCFC-STALL-02: Waymo-AV-004, 32% → 73%. Staged on need_charge, not yet recharged: at 8:25 no charger was free.
--   eff13379's three injected cars waited 86.5, 116.9 and 138.4 minutes to plug in again.

--   §17c, the injected stalls' own stream through the outage: every change of status, so the repair is seen returning the
--   stall (0550 (d)) and nothing else is seen returning it earlier.
\echo '=== 0410 §17c — the injected stalls'' status changes from the fault on ==='
WITH run AS MATERIALIZED (
  SELECT r.sim_run_id AS id, r.payload->'stress_injection_0410' AS inj FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (20:06 UTC, 3:06 PM CT; sim 10:59 AM): each injected stall went, at 7:45:05 AM, `occupied` → `available` as its
--   car was moved to staging, then `available` → `maintenance` in the same instant. All three went `maintenance` →
--   `available` at 9:46:31 AM, 121.4 minutes after the fault and the first tick past the 120-minute repair, and each
--   took its next car at 9:47:29. Nothing returned a stall early.

-- ══ §18 G282 RE-MEASURED: GATE STAYS BELOW TARGET THAT REACHED 240 MINUTES, AND AN ESCALATION INSIDE THE STAY ═════════
--
--   0546 (d) escalates a car to a person when it has waited past 240 minutes for a charger or the service bay (G274).
--   Before 0551 its loop read only staged cars on need_charge or need_service, so a car waiting at the gate was never
--   escalated (0409: 32 of 32 stays that reached 240 minutes). 0551 (d) adds the gate below the cursor's threshold and
--   reads the wait on the cursor's episode clock. This is 0409's query unchanged: it credits an escalation only inside
--   the stay, so a car told earlier in the same episode (while staged) reads as not told here; §23b credits the episode.


\echo '=== 0410 §18 — stays at the gate: how many reached 240 minutes, and how many of those a person was never told about ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 111 gate stays began below target after the boot; 25 reached 240
--   minutes (longest 365.2) and every one was escalated exactly once inside the stay, none twice. (The teardown's
--   `offline` ends every stay, so `still_there` reads 0.) The 16 boot cars at the gate began at the start and are not
--   counted here; §23a counts them. eff13379: 127 stays, 32 reached 240, none escalated. G282 holds.


-- ══ §19 G283 ON A THIRD DAY, UNDER 0553: CARS HELD FOR BAY WORK, AND THE WASH BAYS WHILE THEY WAITED ═══════════════════
--
--   0408 §19 found two cars at 100% held 250 and 330 minutes for a deep clean while the three wash bays were 54-57%
--   occupied. Deep cleans run in the wash bays, because the twin depot has no detail bay. Here each window comes from the
--   run itself: a car with a `must_do_work_open` escalation, from the start of its hold (the escalation's time less
--   `held_min`) to its next entry into a wash or detail bay, or the end of the run. For each window, the minutes cars
--   spent in the wash bays (either purpose) against the bays' minutes, and the bays' calendar.


\echo '=== 0410 §19 — each car escalated for bay work: its wait, and the wash bays in that window ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): no rows: no `must_do_work_open` escalation all day. Every
--   escalation was a wait for a charger or the service bay (§23a).

\echo '=== 0410 §19b — the wash bays'' calendar in the same windows: bookings used, released unused and superseded ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): no rows, as §19.

--   §19c, why the seat refused: every needs-card attempt at a wash bay that was refused, against the three bays at that
--   moment. `cars_in_bays` comes from the state stream; `calendar_free_bays` is the number of bays with no booking, known
--   at that moment and not yet released, overlapping the attempt's window (25 minutes for a deep clean, 9 for a wash). A
--   held booking re-timed later by the bay reconciler is read at its CURRENT window, so this undercounts the calendar's
--   share. §19d reads the reconciler's own log for one refused stretch.
\echo '=== 0410 §19c — each refused wash-bay seat: bays physically empty, and bays free on the calendar ==='
WITH run AS MATERIALIZED (SELECT sim_run_id AS id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (live, 19:50 UTC, through sim 8:40 AM): 72 refused deep cleans and 53 refused washes, none with all three bays
--   physically full (2.25 and 2.17 empty on average): 54 and 32 had an empty bay held on today's calendar. The live
--   snapshot at 8:48 AM shows what holds them now. The yield rightly leaves these holds alone: each is for a car that
--   can be at the bay before the waiting car would finish. WSH-01 stood empty with Tesla-RT-006's wash, 8:40-8:50,
--   while the car finished its L2 charge at 99% (ETA 8:51, G240), and Waymo-AV-035's at 9:03 (fast charger at 94%,
--   ETA 9:06). A deep clean (25 minutes) from 8:48 would have run into both.
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): (the whole run) the same 72 deep cleans and 53 washes as at 8:40
--   AM: no wash-bay seat was refused after 8:40 AM, and all 125 fell between 6:00 and 8:40 AM, in the morning wave.
--   None had all three bays physically full (2.25 and 2.17 empty on average). 86 had every empty bay held on the
--   calendar for the window the seat needed. 39 (18 deep cleans, 21 washes) had a bay that was empty, unpointed and
--   free on the calendar for this query's 25- and 9-minute windows: NASH-WSH-03 for 33 of them (6:35-7:45 AM) and
--   WSH-02 for 6 (8:37-8:38 AM). The decision records only `no_free_space`, so which gate refused those (staff, the
--   seat's own window, or another) cannot be read back. eff13379: 332 refused (136 and 196).
-- OPEN-ITEM: G283 remainder — 39 morning wash-bay refusals had an empty bay free on the calendar; the seat records only `no_free_space`, not which gate refused (§19c).

-- ══ §20 THE INJECTION JOB ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Every attempt of job 780 that got past its clock gate, with its outcome. Since 0552 the fault doors take the run's row
--   first, as the tick does, so no attempt should deadlock (0409 §20: two did, before 0552).

\echo '=== 0410 §20 — the injection job''s attempts ==='
SELECT d.jobid, d.start_time, d.status, round(extract(epoch FROM (d.end_time - d.start_time))::numeric, 2) AS secs,
       CASE WHEN d.return_message LIKE '%deadlock detected%' THEN 'deadlock' ELSE d.return_message END AS outcome
  FROM cron.job_run_details d
 WHERE d.jobid = 780 AND (d.status <> 'succeeded' OR d.end_time - d.start_time > interval '0.5 seconds')
 ORDER BY d.start_time;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): job 780 ran once a minute from 19:19 to 19:42 UTC, 24 times, all
--   succeeded: 23 no-ops (0.01-0.08 s) before the sim clock passed 7:39 AM, and the injection at 19:42:00 (0.44 s). It
--   then unscheduled itself (no row left in `cron.job`). No deadlock: 0552 holds.

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


\echo '=== 0410 §21 — each bay visit: in a bay, or in no bay, by where the car came from ==='
WITH run AS MATERIALIZED (SELECT sim_run_id AS id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (live, 19:19 and 19:26 UTC; sim 4:47 and 5:43 AM): 5 cars in a bay state each time, all 5 standing in a bay that
--   names them; 0 in a bay state in no bay.
-- READ (live, 20:06 UTC; sim 11:04 AM): 3 cars in a bay state, all 3 in the bay that names them.
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): (the whole run) 90 bay visits (41 wash, 24 detail, 25 service),
--   all 90 in a bay, 1,861 bay-minutes, none in no bay. Every visit came from staging; no car went straight off a
--   charger into a bay state. eff13379: 93 visits, 34 in no bay (960 of 2,008 bay-minutes). G286 holds over a whole
--   day.

-- ══ §22 G279 UNDER 0551: WHO WENT AHEAD OF A CAR RE-QUEUED BY A FAULT ══════════════════════════════════════════════════
--
--   For every fault on a car below 99%: how long until the car charged again (or the end), and how many cars that arrived
--   at the gate AFTER the fault started a charge before it did. Before 0551 a fault reset the car's wait to zero, so every
--   later arrival competed with it as an equal (eff13379: 179 such overtakings over 16 faults, §0). Under 0551 the car
--   keeps its banked wait (0551 (b)), and the cursor ranks it by the whole episode (0551 (c)), so a later arrival goes
--   ahead only when its ratio is higher: a short top-off, or an immediate dispatch. `overtaken_by_later_arrivals` should
--   be small, and `waited_after_min` short for a car that had waited long before its fault.

\echo '=== 0410 §22 — per fault below 99%: the wait after it, and the later arrivals that charged first ==='
WITH run AS MATERIALIZED (SELECT sim_run_id AS id, sim_clock_current AS t1 FROM public.ottoq_sim_runs WHERE sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (live, 20:06 UTC; sim 10:59 AM): 9 faults on cars below 99% (6 the twin's own, 3 injected), and all 9 cars
--   plugged in again. Later arrivals charged first 12 times in all: 5 ahead of Waymo-AV-004 (injected, 73%, waited
--   98.5 minutes), 4 ahead of Tesla-AV-042 (L2 station fault at 9:07 AM, 54%, 98.3), 2 ahead of Waymo-AV-033, 1 ahead
--   of Zoox-AV-080, and none ahead of the other five. Waits after the fault: 1.0 to 98.5 minutes. eff13379, over its
--   whole day: 179 overtakings over 16 faults, and 6 cars at 40-96% never recharged (§0).
-- READ (20:10 UTC): each car that charged ahead of Waymo-AV-004 (plugged in again at 9:23:35 AM), with how it was
--   seated. Four were immediate dispatches, which the cursor serves first by design: Tesla-AV-055 (8:51, DCFC; the
--   seat's rationale reads `immediate_dispatch`), Waymo-AV-026 (9:02), Waymo-AV-009 (9:09) and Waymo-AV-018 (9:22, L2).
--   The fifth, Tesla-AV-064, was seated at 8:43 on the fast charger its recall had booked (`reservation_honoured`). No
--   standard car overtook the banked car through the cursor.
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 11 faults on cars below 99% (8 the twin's own, 3 injected), and
--   all 11 cars charged again, 1.0 to 98.5 minutes after the fault (p50 29.6). Later arrivals charged first 13 times in
--   all: 5 ahead of Waymo-AV-004, 4 ahead of Tesla-AV-042, 2 ahead of Waymo-AV-033 (its first fault, at 98%), 1 ahead
--   of Zoox-AV-080 and 1 ahead of Waymo-AV-028 (41%, a thermal fault at 12:24 PM). eff13379: 179 over 16 faults, and 6
--   cars never recharged. G279 holds.

--   §22b, live only (the teardown ends every episode): the banks the cursor reads, `config.charge_wait`, on this run's cars.
\echo '=== 0410 §22b — live: cars carrying a charge-wait bank for this run ==='
SELECT v.display_name AS car, v.current_state::text AS state, v.config->>'svc_step' AS step, v.current_soc,
       (v.config->'charge_wait'->>'banked_min')::numeric AS banked_min,
       to_char((v.config->'charge_wait'->>'since')::timestamptz AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS episode_since_ct,
       round(public.ottoq_charge_wait_min(v.config, v.last_state_change, r.sim_clock_current, r.sim_run_id), 1) AS cursor_wait_min
  FROM public.vehicles v, public.ottoq_sim_runs r
 WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND v.home_depot_id = '11111111-1111-1111-1111-111111111111'
   AND v.config->'charge_wait'->>'run' = 'ab8075a3-4001-45b5-b9e2-747033ad2273'
 ORDER BY banked_min DESC NULLS LAST LIMIT 15;
-- READ (19:47 UTC, sim 8:17 AM): the three injected cars. Waymo-AV-004 carries a bank of 141.1 minutes, its whole wait
--   from 4:35 AM to its 6:56 AM session, so the cursor reads its wait as 173.2 minutes, not the 32 since the fault.
--   Waymo-AV-040 carries 31.8 (episode from 7:11 AM). Tesla-AV-069 has none: its episode ended when it reached target.

-- ══ §23 G282 UNDER 0551: A CAR WAITING AT THE GATE IS ESCALATED ═══════════════════════════════════════════════════════
--
--   §23a, every escalation by reason and where the car waited (0551 (d) records `at`). None may read under 240 minutes.
--   §23b, every stay at the gate that began below target and reached 240 minutes, and whether a person was told in its
--   episode: an escalation for the car, at or before the stay's end, whose `waiting_since` is at or before the stay's
--   start, with no completed charge between. A car escalated while staged and then moved to the gate is told once, not
--   twice (0551 (d): once per episode), which is why §18's per-stay count can read lower than §23b.

\echo '=== 0410 §23a — escalations by reason and where the car waited ==='
SELECT e.payload->>'reason' AS reason, e.payload->>'at' AS waited_at, count(*) AS escalations, count(DISTINCT e.entity_id) AS cars,
       round(min((e.payload->>'held_min')::numeric), 1) AS min_held_min, round(max((e.payload->>'held_min')::numeric), 1) AS max_held_min
  FROM public.ottoq_events e
 WHERE e.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND e.event_type = 'twin.deploy_gate_escalated'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (live, 20:06 UTC; sim 11:03 AM): 21 escalations, every one `waiting_for_a_charger`, held 240.1-240.5 minutes (none
--   early). 16 were cars at the GATE, all told at 8:35 AM, each waiting since 4:35 at 12-31% (the boot cohort). 5 were
--   staged: Zoox-004 and Waymo-AV-007 at 8:26, Tesla-AV-057 and Tesla-AV-051 at 8:36, and Tesla-AV-042 at 10:36 (54%,
--   waiting since its 6:17 arrival and through its 9:07 fault). eff13379 told a person about 7 cars all day, none of
--   them at the gate.
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 52 escalations: `waiting_for_a_charger` 41 at the gate (41 cars)
--   and 6 staged (6 cars), and `waiting_for_the_service_bay` 5, all staged; held 240.0-241.6 minutes. Of the 41 at the
--   gate, 16 were the boot cohort (8:35 AM) and 25 were cars that arrived between 7:28 and 9:51 AM at 33-49% and waited
--   242-365 minutes (§23b). eff13379: 7, none at the gate.

\echo '=== 0410 §23b — gate stays below target that reached 240 minutes: told in their episode, or not ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (live, 20:06 UTC; sim 11:03 AM): 81 gate stays began below target and none has yet reached 240 minutes as a
--   single stay. The 16 gate escalations (§23a) came on the episode clock, a car's whole wait across its moves between
--   the gate and staging (0551 (b)). A per-stay count cannot see them, which is why §18 reads lower.
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 25 gate stays that began below target reached 240 minutes (longest
--   365.2), and all 25 were escalated once, 240.0-240.5 minutes after the wait began (§18). This query counts 23 as
--   told, because it asks the wait to start within a minute of the stay: for Zoox-003 and Zoox-AV-083 the charge-wait
--   clock started 1.7 and 1.4 minutes after the car arrived, at the cursor's first read of it, so each was told 241.8
--   and 241.5 minutes after it arrived. eff13379: 32 stays, none told. G282 holds.

-- ══ §24 G283 UNDER 0553: A HOLD FOR A CAR THAT CANNOT COME GIVES WAY ═══════════════════════════════════════════════════
--
--   §24a, every needs-card seat at a bay, by outcome and whether it came after a yield (`yielded_holds`, 0553 (c)).
--   §24b, the yields themselves, from the bay reconciler's log (`blocked_by` starts `yield:`): holds moved to their car's
--   ETA (`yielded_to_a_car_waiting_now`), released because their leg was closed (`replanned_leg_closed`) or their car had
--   gone (`replanned_vehicle_absent`), or released for want of room (`replanned_no_window`).
--   §24c, what became of each moved hold: used, released, and why. A moved hold is a forward reservation; the car's work
--   stays open until a bay does it, and rule 9 (§2) must still read 0.

\echo '=== 0410 §24a — needs-card bay seats: outcome, and whether a yield came first ==='
SELECT d.proposed_action->>'stall_type' AS bay, d.proposed_action->>'purpose' AS purpose, d.outcome_status,
       -- the seat folds `yielded_holds` into the action it enacts or holds (enacted_action), not the proposal
       COALESCE((d.enacted_action->>'yielded_holds')::boolean, false) AS after_a_yield, count(*) AS decisions
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND d.proposed_action->>'source' = 'needs_card'
   AND d.proposed_action->>'stall_type' IN ('wash_bay', 'service_bay')
 GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
-- READ (live, 19:48 UTC, sim 8:35 AM): 5 seats came straight after a yield, 4 washes and 1 service, all seated
--   (`enacted_action.yielded_holds`; this query first read `proposed_action`, where the seat does not write it).
--   Refused so far: 125 wash-bay seats and 45 service-bay seats.
-- READ (live, 20:06 UTC; sim 11:04 AM): 10 seats straight after a yield, all seated. Needs-card bay seats so far: 52
--   seated, 170 refused.
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): the needs card seated 64 cars in a bay, 12 of them straight after
--   a yield (8 deep cleans, 3 washes, 1 service visit), and was refused 181 times: 72 deep cleans and 53 washes (all
--   before 8:40 AM, §19c) and 56 service visits. eff13379: 45 seated and 342 refused (136, 196 and 10). The service
--   refusals rose from 10 to 56: the service bay is the one that binds now, and §26 shows why.

\echo '=== 0410 §24b — the yields, from the bay reconciler''s log ==='
SELECT s.stall_type::text AS bay, r.action, r.reason, r.blocked_by, count(*) AS holds, count(DISTINCT r.vehicle_id) AS cars,
       round(avg(extract(epoch FROM (r.new_from - r.old_from)) / 60)::numeric, 1) AS avg_moved_min,
       round(max(extract(epoch FROM (r.new_from - r.old_from)) / 60)::numeric, 1) AS max_moved_min
  FROM public.bay_reservation_reconcile_2026_08_02 r JOIN public.stalls s ON s.id = r.stall_id
 WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND r.blocked_by LIKE 'yield:%'
 GROUP BY 1, 2, 3, 4 ORDER BY 1, 5 DESC;
-- READ (live, 19:48 UTC): 5 `ottoq.bay_hold_yielded` events, at 6:37, 7:12, 7:15, 7:17 and 8:22 AM, for Waymo-AV-026
--   (WSH-01), Zoox-002 (WSH-03), Waymo-AV-018 (SVC-02), Tesla-RT-004 (WSH-01) and Zoox-AV-079 (WSH-03). Six holds moved,
--   every one `yield:charging_l2`: a car on L2 whose charge would run past the waiting car's job. Each waiting car was
--   seated in the same tick.
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): 12 `ottoq.bay_hold_yielded` events moved 13 holds: 10 on the wash
--   bays (8 cars) and 1 on the service bay, each for a car on an L2 whose charge would outlast the waiting car's job
--   (moved 178.1 minutes on average, at most 290.9), and 2 wash-bay holds for cars that still owed a charge (moved 40.6
--   on average).

\echo '=== 0410 §24c — what became of each hold a yield moved ==='
SELECT b.purpose, b.state, b.release_reason, count(*) AS holds
  FROM public.ottoq_stall_bookings b
 WHERE b.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'
   AND b.booking_id IN (SELECT r.booking_id FROM public.bay_reservation_reconcile_2026_08_02 r
                         WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273' AND r.reason = 'yielded_to_a_car_waiting_now')
 GROUP BY 1, 2, 3 ORDER BY 1, 4 DESC;
-- READ (end; read 20:30-20:50 UTC, 3:30-3:50 PM CT): the 12 bookings a yield moved: 6 were used later (4 washes and 1
--   deep clean closed at the bay exit, 1 wash when its window elapsed with the car in the bay); 2 no-shows released by
--   the grace (a deep clean and a service visit); 1 deep clean replanned beyond the horizon; 1 wash whose window
--   elapsed unused; 2 deep cleans released when the run stopped.

-- ══ §25 G284 UNDER 0551: THE COCKPIT'S QUEUE IS THE LINE THE ENGINE SERVES (LIVE) ═══════════════════════════════════════
--
--   `public.ottoq_depot_queue` feeds the field-ops cockpit's queue positions. Under 0551 (e) it mirrors the charge cursor:
--   its filter, its keys and the run's clock. Read live: the head of the charge queue at one moment, then which cars the
--   chargers took over the next few minutes, and at what position each had stood.

\echo '=== 0410 §25 — live: the head of the cockpit''s charge queue ==='
SELECT q.queue_position, q.queue_depth, q.vehicle_ref, q.current_soc, q.is_immediate,
       to_char(q.waiting_since AT TIME ZONE 'America/Chicago', 'HH12:MI AM') AS waiting_since_ct
  FROM public.ottoq_depot_queue('11111111-1111-1111-1111-111111111111', 'ab8075a3-4001-45b5-b9e2-747033ad2273') q
 WHERE q.queue_kind = 'charge' ORDER BY q.queue_position LIMIT 10;
-- READ (19:26:47 UTC, 2:26 PM CT; sim 5:44:22 AM): 31 cars in the charge queue. The head is ten cars at the gate, all
--   waiting since 4:35 AM (the boot cohort), in charge order: Zoox-AV-077 45%, Zoox-AV-099 44%, Waymo-AV-015 43%,
--   Tesla-AV-053 43%, Zoox-AV-073 43%, Waymo-AV-037 42%, ... With equal waits the response ratio (wait + points) / points
--   ranks the car needing the fewest points first, which is the cursor's own order (0545 (c)).
-- READ (19:47 UTC, the follow-up): the head was served in exactly its order: #1 at 5:54:27 AM; #2 and #3 in the same tick
--   at 5:55:26; #4 5:57:09; #5 6:05:10; #6 6:07:37; #7 6:11:31; #8 6:13:20. Eight other cars charged in between:
--   - three staged since 4:37 AM (Zoox-AV-080, Waymo-AV-039, Tesla-AV-065). The queue lists a staged car only while a
--     charger is free (the cursor's candidate filter, copied as it is), and none was at the probe;
--   - two immediate dispatches that came back after the probe (Tesla-AV-067, Waymo-AV-025);
--   - two standard returns seated on the charger their recall had booked (`reservation_honoured`: Tesla-AV-045 at 6:08,
--     Waymo-001 at 6:13).
--   So the queue's order is the engine's order (G284 holds), but its positions leave out two kinds of car that go
--   ahead: staged cars while every charger is busy, and cars holding a reservation. At sim 8:25 AM, with no charger free,
--   the queue listed 52 cars at the gate and none of the 5 staged on need_charge, among them Waymo-AV-004 (§17b), whose
--   173-minute wait likely puts it near the front of the line. G288.
-- OPEN-ITEM: G288 — the cockpit's charge queue leaves out staged cars while no charger is free, and cars holding a reservation (§25).

-- ══ §26 G289 (NEW): THE GATE'S OWN FLAG SENDS FINISHED CARS TO THE SERVICE BAY ═══════════════════════════════════════
--
--   Found at the end, reading §4 and §15: four of the five service-bay escalations list nothing `missing`, and the time
--   staged for a bay rose from 16.3 to 70.2 car-hours. The gate flags a car it has held past its patience
--   (`deploy_gate_stuck`, 45 minutes) with `flagged_issue`, and a wash or detail bay's exit reads `flagged_issue` as
--   service work (`v_needs_svc` in `twin.ottoq_sim_advance_service_flow`; G273 named it). 0546 (b) drops the flag at the
--   gate's release, but a car held for its wash or deep clean leaves through the bay, not the release. Before 0554 the
--   service lane seated such a car by staff count in no bay (G286), so the cost was staff time. Now the car waits for a
--   real service-bay seat that only the needs card or a booking can give it. §26a splits the service bay's visits by what
--   they credited. §26b splits every episode staged on need_service by whether the car carried the gate's flag, and by
--   how the episode ended.

\echo '=== 0410 §26a — service-bay visits by what they credited, and the bay-minutes each kind took ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:40 UTC, 3:40 PM CT): 25 service-bay visits, 974.2 bay-minutes. 6 credited nothing and only cleared
--   `deploy_gate_stuck`: 268.1 bay-minutes (27.5%), 44.7 minutes each. 17 credited real work (15 with no flag; 2
--   `fault_repair` visits that also cleared the flag): 678.1 minutes. 2 were still in the bay at the end (28.0). One
--   service visit in four did nothing but take the flag off, on the depot's two scarcest seats.

\echo '=== 0410 §26b — episodes staged on need_service, by the gate''s flag and how each ended ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0, r.sim_clock_current AS t1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
              bool_or(flag = 'deploy_gate_stuck') AS gate_flag
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
-- READ (end; read 20:40 UTC, 3:40 PM CT): the 70.2 car-hours staged on need_service (§15) split 36.7 with the gate's
--   `deploy_gate_stuck` flag and 33.5 without. With the flag: 6 episodes on 6 cars ended in a service-bay visit that
--   credited nothing (18.6 car-hours, the longest 253.3 minutes), 3 cars were still waiting at the end (12.3, the
--   longest 273.5) and 2 episodes of one car left need_service another way (5.8). Every one of those cars was at 100%
--   with every atom on its card done: the service bay was the only thing between it and work. Without the flag: 23
--   episodes (14 cars) ended in a visit that credited work (9.3 car-hours), 8 cars were still waiting (13.2), and 65
--   short episodes on 52 cars left need_service for a wash or detail bay or the gate (10.8). The decide tick's service
--   seat names the kind: its `hold_no_bay` rows carry `need_source: flag` and `open_service_atoms: []` for these cars.
--   G289: the gate's patience flag is a note for a person, and the bay exit turns it into a service-bay visit.
-- OPEN-ITEM: G289 — the gate's own patience flag sends a finished car to the service bay through the bay exit (§26).

-- ══ §27 G290 (NEW): A CAR WITH AN UNREPAIRED STEERING/BRAKE FAULT LEFT THE DEPOT ═════════════════════════════════════
--
--   Found at the end, reading §7's one wait that ended in `tow_requested`. The twin's vehicle-fault model wrote two
--   faults on this run, into `config.exception`. §27a follows each from the fault to the teardown: every state change,
--   and the exception's own status at each.

\echo '=== 0410 §27a — every car with a vehicle exception: its state changes and the exception''s status at each ==='
WITH run AS MATERIALIZED (SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ab8075a3-4001-45b5-b9e2-747033ad2273'),
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
-- READ (end; read 20:45 UTC, 3:45 PM CT): two faults.
--   - Waymo-AV-007, a `non_critical_major` fault at 9:22 AM while it waited at 20% for a charger: `pending_approval`, a
--     technician approved an offline inspection at 9:34, retrieved to emergency staging at 9:47, and there it stayed
--     until the teardown, not charged and not repaired. Held, as rule 9 allows for a vehicle emergency.
--   - Waymo-AV-011, a `steering_brake_fault`, severity critical, `immobilizing: true`, at 10:47 AM while it charged on
--     L2 (NASH-L2-STALL-20). The eviction was deferred until the charge window ended (`deferred_awaiting_tech`,
--     `immobilizing_awaiting_tow`); at 1:07:30 PM the car went to `tow_requested` and at 1:32:35 to `emergency_staged`.
--     In the same second `ottoq.ottoq_readmit_resumed_visits` put it back on `staged_awaiting_service` to finish its
--     interrupted visit (exception status `readmitted_resume`), 19 seconds later the gate staged it for departure,
--     and at 1:33:51 PM it deployed at 99%, the fault still on it, repaired by nothing.
--   How: the readmit path takes any car in `emergency_staged` whose exception reads `retrieved_staged` and whose visit
--   was cut short, and ignores the car's own fault deferral by design (its "narrowed gate"); it reads neither
--   `immobilizing` nor `severity`. The shield judged the move and said no, in shadow: `SM.001` failed it ("actor
--   ottoq_engine not authorized for vehicle transition emergency_staged -> staged_awaiting_service"; only a command-center
--   operator or depot supervisor may). Then the departure test (`public.ottoq_departure_clear`, 0543) reads the charge
--   and the card's atoms, and the fault is in neither, so the dispatcher and 0544's trigger passed it. No function in the
--   engine marks a vehicle exception repaired or removes it; only the next run's seed strips it. G290.
-- OPEN-ITEM: G290 — a car with an unrepaired critical, immobilizing fault left the depot; the readmit path and the departure test do not read `config.exception` (§27).
