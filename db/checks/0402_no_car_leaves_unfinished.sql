-- 0402  **No car leaves unfinished: the first operator run under 0543, beside c9d14225.**
--
--       Written on 2026-09-27 (CT) around the validation run started after 0543 (applied 20260928013804): no car leaves
--       the depot with a service still needed, ever (Chase, 8:00 PM CT; CLAUDE.md rule 9; FINDINGS G268). Also the first
--       operator run under 0542 (G267: a car that owes its charge goes to the charger; the gate never releases an
--       unfinished car). Read-only. Started by one-shot cron 772 once the recert sweep under 0543 had passed (all nine
--       columns by 01:58 UTC): `ottoq_start_busy_run(8, 1, 9055713631887914180)`, busy_day at 8x on c9d14225's seed.
--       Run 9eab647f began at 02:15:00 UTC (9:15 PM CT) and was booted by 02:16:11; its sim clock opens at 09:41 UTC
--       (4:41 AM CT), as c9d14225's did. Cron 772's first four firings returned without starting it: pg_cron fires the
--       recert runner (cron 746) at second :00 of every minute too, and `ottoq_certification_in_flight` counts that
--       runner's sub-second idle pass as a rig in flight. A five-second `pg_sleep` before the guard fixed it. A guard of
--       this kind in any future one-shot must wait out the runner's second.
--
--       **Closer to c9d14225 than c9d14225 was to ad106e55, and still not a pair.** Both runs were started with the seed
--       passed, so both open at the same sim minute (4:41 AM CT) and draw the same world. What differs is the engine:
--       0542 and 0543 together. A difference below is theirs jointly; neither can be credited alone from this run.
--
--       **c9d14225's side is §0, read before this run purged it** (`ottoq_purge_prior_runs`, class 'engine'). Re-running
--       §0 now returns nothing.
--
--       The run's id is 9eab647f-01ae-4c32-92eb-a9803f1397af below.

-- ══ §0 BEFORE: c9d14225 (read 2026-09-28 01:47-01:52 UTC, 8:47-8:52 PM CT, before the purge) ══════════════════════════
--
--   The departure query of §2, on c9d14225. A departure is a state change into en_route_to_deployment or deployed after
--   the run's first tick (the boot's prime deployment happens at the first tick and is excluded). Its visit is the
--   car's latest visit that arrived before it left; a service was open at departure unless it was done or cancelled by
--   then (`COALESCE(done_at, closed_at)`, since a satisfied charge carries closed_at). Its charge is the dispatch
--   record's soc_at_dispatch_pct.
--   READ: **90 departures, all from staged_for_departure. 10 left with work open (0 of it required): exterior wash 5,
--   preventive maintenance 2, sensor calibration 2, deep clean 2. 22 had no visit; 10 of those left below 99% (as low
--   as 80%).** The must-do census on its atoms: optional were exterior wash 28 (17 done), deep clean 7 (0 done),
--   preventive maintenance 20 (6 done), remote diagnostics 9 (9 done), sensor calibration 10 (4 done). Bay entries 31
--   wash, 15 detail, 24 service; 31 needs-card bay admissions; the readiness gate held at most 9 cars at once; staging
--   overflow peaked at 35; 6 deferred services were started by the overnight crew.

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0402 §1 — the run and its scorecard, beside c9d14225 (0401 §1''s READ) ==='
SELECT r.sim_run_id, r.run_by, r.status, r.random_seed, r.sim_clock_start, r.sim_clock_current, r.tick_count,
       r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af';
SELECT public.ottoq_kpi_five('9eab647f-01ae-4c32-92eb-a9803f1397af');
SELECT public.ottoq_kpi_charge_wait('9eab647f-01ae-4c32-92eb-a9803f1397af');
SELECT public.ottoq_kpi_supply_gap('9eab647f-01ae-4c32-92eb-a9803f1397af') - 'by_hour_ct';
SELECT sim_run_id, metrics FROM public.ottoq_run_archives WHERE sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af';
-- READ (2026-09-28 03:25-03:40 UTC, 10:25-10:40 PM CT): the governor stopped the run at 03:24:00 UTC (10:24 PM CT), sim
--   1:47 PM CT, 546 sim-minutes and 1,086 ticks. c9d14225 (0401 §1's READ) ran 552 sim-minutes, 1,110 ticks, on the
--   same seed from the same sim minute. This run first, then c9d14225:
--     KPI 1 asset hours 124.45 against 104.22 · KPI 2 turns per point 3.01 against 2.70
--     KPI 3 peak site kW 1,090.5 (demand 1,118.6) against 1,527.4 (demand 1,530.9)
--     KPI 4 touches per turn 1.006 against 1.359 · KPI 5 p95 time to service 248.6 min (p50 9.3) against 287.7 (p50
--       20.6) · returns unserved 22 against 16
--     charge wait: p50 52.6, p95 333, max 475.1 min; 153 of 179 visits owing a charge charged, 26 still waiting at the
--       end. c9d14225: p50 56.8, p95 346.2, max 445.5; 128 of 162; 34.
--     supply gap: 229.2 of 355.6 demand car-hours unmet (64.5%), 126.4 deployed, peak shortfall 40. c9d14225: 256.5 of
--       360.4 (71.2%), 103.9 deployed, 44.
--     archive: 116 dispatches against 94, 174 charge sessions against 156, 514 tasks completed against 419.
--   **Holding every car until it is finished did not cost the day its deployed hours: 22% more car-hours out, 22 more
--   dispatches, 18 more charges.** One run each on the same seed and world, so a comparison, not a paired test, and the
--   difference is 0542's and 0543's jointly: 0542 routed a car that still owed its charge to a charger instead of
--   releasing it as ready, where c9d14225 had left such cars sitting (G267). The rule's own cost is in §4-§6, and it is
--   a capacity cost, not a charge-short or service-short car.
--   **The charge-wait KPI does not see a car with no visit.** It counts visits that arrived owing a charge. The eight
--   boot cars §6 names waited the whole run for a charger with no visit on record, so none of them is in its 26.

-- ══ §2 THE RULE: NO DEPARTURE WITH A SERVICE OPEN OR A CHARGE SHORT ═════════════════════════════════════════════════
--
--   Both must be 0. A departure below target - 1 or with any service open is a breach of rule 9, whatever the
--   service's urgency.

\echo '=== 0402 §2 — departures, and any that left unfinished ==='
WITH run AS (
  SELECT r.sim_run_id AS id, r.sim_clock_start AS t0 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af'),
dep AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS left_at, e.payload->'diff'->'current_state'->>'from' AS from_state
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
  SELECT dv.vehicle_id, dv.left_at, a->>'svc' AS svc, COALESCE((a->>'must_do')::boolean, false) AS must_do
    FROM dv JOIN public.ottoq_visit_needs vn ON vn.visit_id = dv.visit_id
    CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
   WHERE a->>'svc' <> 'readiness_check'
     AND NOT (COALESCE(a->>'status', 'pending') IN ('done', 'cancelled')
              AND COALESCE((a->>'done_at')::timestamptz, (a->>'closed_at')::timestamptz, dv.left_at) <= dv.left_at))
SELECT (SELECT count(*) FROM dv) AS departures,
       (SELECT count(*) FROM dv WHERE visit_id IS NULL) AS no_visit,
       (SELECT count(*) FROM dv WHERE soc < 99) AS below_99,
       (SELECT min(soc) FROM dv) AS min_soc,
       (SELECT count(DISTINCT (vehicle_id, left_at)) FROM open_at) AS left_with_open_work,
       (SELECT jsonb_object_agg(svc, k) FROM (SELECT svc, count(*) AS k FROM open_at GROUP BY svc) q) AS open_by_svc,
       (SELECT jsonb_object_agg(from_state, k) FROM (SELECT from_state, count(*) AS k FROM dv GROUP BY 1) q) AS from_states;
-- READ (2026-09-28 03:25 UTC): **112 departures, 0 below 99% (the lowest was 99), 0 with a service open**, all 112 from
--   staged_for_departure, 13 with no visit. c9d14225 (§0): 90 departures, 10 with work open, 10 below 99% (as low as
--   80%). The rule held for the whole day.

-- ══ §3 EVERY SERVICE FOUND NEEDED IS REQUIRED, AND WHAT BECAME OF IT ═══════════════════════════════════════════════════

\echo '=== 0402 §3 — the must-do census, and each service done or still open at the end ==='
SELECT a->>'svc' AS svc, COALESCE((a->>'must_do')::boolean, false) AS must_do, count(*) AS atoms,
       count(*) FILTER (WHERE a->>'status' = 'done') AS done,
       count(*) FILTER (WHERE a->>'status' = 'cancelled') AS cancelled,
       count(*) FILTER (WHERE COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')) AS open,
       count(*) FILTER (WHERE (a->>'no_executor')::boolean) AS no_executor
  FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
 WHERE vn.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-28 03:27 UTC): **every row reads must_do = true and no_executor is 0.** Done / open at the end, by
--   service: charge 111 / 68 of 179; exterior wash 27 / 11 of 38; deep clean 11 / 16 of 27; interior inspection 150 / 22
--   of 172; tidy 29 / 7 of 44 (8 cancelled); item retrieval 9 / 1 of 10; preventive maintenance 11 / 9 of 20; walkaround
--   77 / 0; readiness check 99 / 85 of 184; remote diagnostics 11 / 0; sensor calibration 3 / 7 of 10; sensor clean 7 / 2
--   of 11 (2 cancelled); triage check 26 / 3 of 29; fault repair 0 / 2 of 2. "Open" is work on cars still in the depot
--   at the teardown. The 10 cancelled atoms were all `cleared_by_triage` with verdict clear: the triage looked and the
--   cabin or sensors did not need it. Nothing was skipped. c9d14225 had 74 optional atoms of five services.

-- ══ §4 RE-ORCHESTRATION: WHAT THE RECHECK AND THE GATE DID ══════════════════════════════════════════════════════════════

\echo '=== 0402 §4 — cars kept from leaving unfinished, cars sent back to the gate, cars escalated to a person ==='
SELECT count(*) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS recheck_events,
       sum((e.payload->>'rerouted')::int) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS rerouted,
       sum((e.payload->>'back_to_gate')::int) FILTER (WHERE e.event_type = 'twin.departure_recheck') AS back_to_gate,
       count(*) FILTER (WHERE e.event_type = 'twin.deploy_gate_escalated') AS escalated_to_a_person,
       max((e.payload->>'held')::int) FILTER (WHERE e.event_type = 'twin.deploy_gate_summary') AS gate_held_max,
       max((e.payload->>'overflow')::int) FILTER (WHERE e.event_type = 'twin.staging_overflow') AS staging_overflow_max,
       count(*) FILTER (WHERE e.event_type = 'twin.deferred_service_started') AS overnight_deferred_started
  FROM public.ottoq_events e WHERE e.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af';
SELECT c->>'remedy' AS remedy, count(*) AS cars, min((c->>'soc')::numeric) AS min_soc,
       (SELECT jsonb_object_agg(s, k) FROM (SELECT s, count(*) AS k
          FROM public.ottoq_events e2 CROSS JOIN LATERAL jsonb_array_elements(e2.payload->'cars') c2
          CROSS JOIN LATERAL jsonb_array_elements_text(c2->'open') s
         WHERE e2.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af' AND e2.event_type = 'twin.departure_recheck' AND c2->>'remedy' = c->>'remedy'
         GROUP BY s) q) AS open_services
  FROM public.ottoq_events e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'cars') c
 WHERE e.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af' AND e.event_type = 'twin.departure_recheck'
 GROUP BY 1 ORDER BY 1;
SELECT e.entity_id AS vehicle_id, e.sim_clock_at AT TIME ZONE 'America/Chicago' AS escalated_ct,
       e.payload->>'held_min' AS held_min, e.payload->>'remedy' AS remedy, e.payload->'missing' AS missing
  FROM public.ottoq_events e
 WHERE e.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af' AND e.event_type = 'twin.deploy_gate_escalated' ORDER BY e.sim_clock_at;
-- READ (2026-09-28 03:30 UTC): 41 recheck events. **2 cars rerouted, both at the boot tick** (4:51 AM CT: 91% and 96%,
--   nothing open, to need_charge), so after the boot no car was ever staged to leave unfinished. 42 sent back to the
--   gate, 35 distinct cars, none more than twice: nothing bounced. The gate held at most 32 cars at once (the boot tick);
--   staging overflow peaked at 54, against 35 on c9d14225. No tick failed; no overnight-deferred service started (0543
--   defers nothing).
--   **4 cars escalated to a person, and the first was a false alarm (G269).** Tesla-AV-061 at 10:25 AM, "held 285.8 min,
--   missing charge" at 100%: it had been charging on an L2 from 18% since 5:39 AM (two state changes inside the counted
--   hold), came back to the gate the tick its charge closed, and left at 100% with everything done at 10:27. The gate's
--   clock started when it first held the car and ran through the charge. **The other three were real, and all three
--   waited for a deep clean at 100%**: Tesla-AV-060 (12:24 PM), Tesla-AV-050 (1:07 PM), Waymo-AV-031 (1:29 PM), each
--   held 240 minutes with no state change, 336, 37 and 386 minutes past their deploy time, and none was seated before
--   the teardown. §5 says why.

-- ══ §5 WHAT HOLDING COSTS, AND THE BAYS IT LOADS ══════════════════════════════════════════════════════════════════════

\echo '=== 0402 §5 — bay entries, needs-card admissions, and cars still in the depot at the end with work open ==='
SELECT (SELECT jsonb_object_agg(to_state, k) FROM (
          SELECT e.payload->'diff'->'current_state'->>'to' AS to_state, count(*) AS k
            FROM public.ottoq_events e WHERE e.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af' AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
           GROUP BY 1) q) AS bay_entries,
       (SELECT count(*) FROM public.ottoq_decisions d
         WHERE d.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af' AND d.enacted_action->>'source' = 'needs_card' AND d.outcome_status = 'enacted')
         AS needs_card_bay_admissions;
-- the cars' last state in the signed stream (the teardown resets vehicles, so read the stream, not the table)
WITH last AS (
  SELECT DISTINCT ON (e.entity_id) e.entity_id AS vehicle_id, e.payload->'diff'->'current_state'->>'to' AS last_state,
         e.sim_clock_at AS since
    FROM public.ottoq_events e
   WHERE e.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff' ? 'current_state'
     AND e.payload->'diff'->'current_state'->>'to' <> 'offline'
   ORDER BY e.entity_id, e.sim_clock_at DESC)
SELECT l.last_state, count(*) AS cars,
       round(avg(extract(epoch FROM (r.sim_clock_current - l.since)) / 60.0)) AS mean_min_in_state
  FROM last l, public.ottoq_sim_runs r WHERE r.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af'
 GROUP BY 1 ORDER BY 2 DESC;
-- READ (2026-09-28 03:32 UTC): bay entries 32 wash, 12 detail, 27 service (c9d14225: 31, 15, 24); 32 needs-card bay
--   admissions (c9d14225: 31).
--   **The bay admission seated the cars that were not late (G270).** By the seated car's deploy time on the needs card
--   (the decision's context frame): 15 seats went to cars due out later (47 to 758 minutes ahead) and 10 to cars with no
--   deploy time, against 7 to cars already late (wash 6, detail 1). Its order is urgency, resumption, `fits_window`,
--   deploy time, shortest job, and `fits_window` is false for every car past its deploy time, because no work fits a
--   window that has closed. Under rule 9 that sorts the latest cars last. At 12:24 PM ten cars were held at the gate for
--   a wash or a deep clean, eight of them 37 to 426 minutes late.
--   **And the lane is two seats.** Wash and detail share LEAST(cleaning staff 3, wash supervisors 2) = 2 seats on 3 wash
--   bays: the third bay waits for a third wash supervisor. A deep clean takes 25 minutes against a wash's 9.
--   Where the cars were at the teardown (last state in the signed stream): staged 34 (mean 330 min there), charging on
--   L2 26, waiting at the gate 23 (mean 150 min; 22 of them at 43-49%), deployed 15, fast-charging 10, service bay 2,
--   charge complete 2, detail bay 1, wash bay 1, tow requested 1, inbound 1. Of the 34 staged: 23 held at the gate
--   (need_deploy: 9 for a deep clean, 5 for a wash, 1 for its charge), 9 waiting for a charger, 2 ready. All 10 fast
--   chargers and 26 of the 30 L2s had a car on them. **Holding costs capacity, and three resources bind: chargers, the two cleaning seats,
--   and staging.**

-- ══ §6 LIVE PROBE: A HELD CAR THAT NOTHING WILL MOVE (run while the run is live) ═══════════════════════════════════════
--
--   Each held car should be on a path: need_charge below target - 1 (the charge cursor), need_service with service-bay
--   work (the service lane), need_deploy with wash or detail work (the bay admission), or in-place work under way. A row
--   here is a car no path takes.

\echo '=== 0402 §6 — held cars no path will move ==='
SELECT v.display_name, v.current_state, v.config->>'svc_step' AS step, v.current_soc,
       public.ottoq_effective_target_soc_at(v.id, r.sim_clock_current) AS target,
       (SELECT array_agg(DISTINCT a->>'svc') FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
         WHERE vn.vehicle_id = v.id AND vn.sim_run_id = r.sim_run_id AND vn.status IN ('open', 'in_progress')
           AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')) AS open_svcs,
       round(extract(epoch FROM (r.sim_clock_current - v.last_state_change)) / 60.0) AS min_in_state
  FROM public.vehicles v, public.ottoq_sim_runs r
 WHERE r.sim_run_id = '9eab647f-01ae-4c32-92eb-a9803f1397af' AND r.status = 'running'
   AND v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
   AND v.current_state = 'staged_awaiting_service'
   AND NOT (
         (v.config->>'svc_step' = 'need_charge'
          AND v.current_soc < public.ottoq_effective_target_soc_at(v.id, r.sim_clock_current) - 1)
      OR (v.config->>'svc_step' = 'need_service' AND EXISTS (
            SELECT 1 FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
              JOIN public.service_cadence_policy cp ON cp.svc = a->>'svc' AND cp.is_active AND cp.lane = 'service_bay'
             WHERE vn.vehicle_id = v.id AND vn.sim_run_id = r.sim_run_id AND vn.status IN ('open', 'in_progress')
               AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')))
      OR (v.config->>'svc_step' = 'need_deploy'))
 ORDER BY min_in_state DESC;
-- READ: need_deploy cars are the gate's, and it releases, routes or holds them each tick, so they are left out; §4's
--   escalations are the ones it could not finish.
--   Early probe 02:23 UTC (9:23 PM CT; sim 5:47 AM CT, tick 111): **empty.** 14 departures, all at 100% with nothing
--   open; 33 cars on need_charge, every one below its target - 1.
--   Mid-run probe 02:45 UTC (9:45 PM CT; sim 8:43 AM CT, tick 461): **empty again.** §2 so far: 49 departures, 0 below
--   99% (lowest 99), 0 with work open. §4 so far: 13 recheck events; 2 cars rerouted, both at the boot tick (91% and
--   96%, no work open, to need_charge); 13 cars sent back to the gate, 13 distinct, once each, so nothing bounced; 0
--   escalated to a person. The gate's peak of 32 held was the boot tick. Held at the probe: 4 cars at 100% waiting for
--   the wash lane (an exterior wash 85 min; deep cleans 97, 36 and 25 min) while it was full: 2 of 2 seats, since its
--   capacity is LEAST(3 cleaning staff, 2 wash supervisors). The bay admission had seated 17 so far (13 washes, 2 deep
--   cleans, 1 fault repair, 1 calibration). 24 cars on need_charge (33-98%, the longest 237 min); staging overflow
--   peaked at 54, against 35 for the whole of c9d14225.
--   Watch for the end read: (4b) orders across cars by urgency, fits-window, deadline and then SHORTEST job, with no
--   term for how long a car has waited, so under steady wash demand a 25-minute deep clean can be passed over by
--   9-minute washes again and again. A car held that way reaches the gate's hard cap at 240 minutes and is escalated
--   to a person.
--   End read (2026-09-28 03:35 UTC, from the signed stream; the teardown resets the cars): **9 cars sat the whole run on
--   need_charge at 91-98% (G271)**: Tesla-AV-051, -052, -068, Waymo-005, Waymo-AV-007, -015, -025, Zoox-AV-094, -100, in
--   staging from 4:41 or 4:51 AM to the teardown, their charge never moving. Eight have no visit: boot cars placed
--   ready in staging. Each was a candidate for the charge cursor all day (below its target - 1, a charger free), and the
--   cursor serves the lowest charge first (`current_soc ASC`), so with cars arriving at 43-49% all day a car that needed
--   only a top-off never reached the front. Rule 9 keeps it until it is full; the cursor never fills it. About 80 car-hours
--   idle, against 126.4 deployed. The ninth, Tesla-AV-051, also owed a deep clean from a rider flag the in-depot sweep
--   raised at 9:49 AM; that visit shows `superseded` only because the teardown closed it (`run_completed`).
