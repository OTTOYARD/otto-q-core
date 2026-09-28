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
-- READ: pending.

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
-- READ: pending.

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
-- READ: pending. Every row must read must_do = true, and no_executor must be 0.

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
-- READ: pending.

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
-- READ: pending.

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
-- READ: pending. need_deploy cars are the gate's, and it releases, routes or holds them each tick, so they are left
--   out; §4's escalations are the ones it could not finish.
