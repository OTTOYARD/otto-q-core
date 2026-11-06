-- lab/research/p2_capacity/uptime_by_hour.sql -- run in a finished lab replica (psql -At -F ' ' -f). Every hour of the
-- day (CT), sampled each half hour as steady_state.py's UPTIME_SQL does: the share of the fleet out at work (the fleet
-- less the cars whose visit is open), the share the work side asked for (ottoq_deploy_target_now), and the cars in the
-- depot (distinct cars; G520's visits, opened while the car was out and never departed, left out). LAB ONLY.
WITH r AS (SELECT sim_run_id AS run, sim_clock_start AS t0, sim_clock_current AS t1 FROM ottoq_sim_runs ORDER BY started_at DESC LIMIT 1),
o0 AS (SELECT x.* FROM r, public.ottoq_visit_outcomes(r.run) x),
o AS (SELECT o0.* FROM o0  -- G520: a visit the twin opened while its car was still out at work, which never departed,
       -- is not a visit (the car came home later, on a visit of its own); counted, it doubles the car and takes its later charge
       WHERE NOT (o0.departed_at IS NULL AND (SELECT COALESCE(e.payload->>'to', e.payload->'diff'->'current_state'->>'to')
                    FROM ottoq_events e WHERE e.entity_type = 'vehicle' AND e.entity_id = o0.vehicle_id AND e.event_type = 'vehicle.state_changed'
                     AND e.sim_clock_at <= o0.arrived_at AND (e.payload ? 'to' OR e.payload->'diff' ? 'current_state')
                   ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) IN ('deployed', 'en_route_to_deployment'))),
fleet AS (SELECT count(*)::numeric AS n FROM vehicles WHERE home_depot_id = '11111111-1111-1111-1111-111111111111' AND category = 'autonomous'),
h AS (SELECT g AS at FROM r, generate_series(r.t0, r.t1, interval '30 minutes') g)
SELECT to_char(date_trunc('hour', h.at AT TIME ZONE 'America/Chicago'), 'HH24') AS hr,
       round(avg(((SELECT n FROM fleet) - (SELECT count(DISTINCT o.vehicle_id) FROM o WHERE o.arrived_at <= h.at AND (o.departed_at IS NULL OR o.departed_at > h.at))) / (SELECT n FROM fleet)) * 100) AS out_pct,
       round(avg(public.ottoq_deploy_target_now(r.run, '11111111-1111-1111-1111-111111111111', h.at) / (SELECT n FROM fleet)) * 100) AS asked_pct,
       round(avg((SELECT count(DISTINCT o.vehicle_id) FROM o WHERE o.arrived_at <= h.at AND (o.departed_at IS NULL OR o.departed_at > h.at)))) AS in_depot
  FROM h, r GROUP BY date_trunc('hour', h.at AT TIME ZONE 'America/Chicago') ORDER BY date_trunc('hour', h.at AT TIME ZONE 'America/Chicago');
