-- lab/research/p2_capacity/svc_first_wait.sql (G523; LAB ONLY, read on a kept lab replica: psql -d ottoq_cap_<day> -f this).
-- Visits that held both a service bay and a wash bay, the service first: how long the car stood between its charge
-- (or the gate) and the service bay, how much of that wait a wash bay stood free, and the wash minutes after.
WITH r AS (SELECT sim_run_id AS run, sim_clock_start t0, sim_clock_current t1 FROM ottoq_sim_runs WHERE run_by='ab_harness' ORDER BY started_at DESC LIMIT 1),
o AS (SELECT x.* FROM r, public.ottoq_visit_outcomes(r.run) x),
bk AS (SELECT o.visit_id, st.stall_type::text lane, lower(b.during) s, LEAST(upper(b.during), COALESCE(b.released_at, upper(b.during))) e
         FROM o, r, ottoq_stall_bookings b JOIN stalls st ON st.id=b.stall_id
        WHERE b.sim_run_id=r.run AND b.vehicle_id=o.vehicle_id AND st.stall_type::text IN ('service_bay','wash_bay')
          AND b.state IN ('active','done','interrupted') AND lower(b.during) >= o.arrived_at AND (o.departed_at IS NULL OR lower(b.during) < o.departed_at)),
v AS (SELECT o.visit_id, o.vehicle_id, o.arrived_at,
             (SELECT min(s) FROM bk WHERE bk.visit_id=o.visit_id AND lane='service_bay') svc_s,
             (SELECT min(s) FROM bk WHERE bk.visit_id=o.visit_id AND lane='wash_bay') wash_s,
             (SELECT max(COALESCE(s.ended_at, s.started_at)) FROM ocpp_sessions s, r WHERE s.sim_run_id=r.run AND s.vehicle_id=o.vehicle_id
                AND s.started_at >= o.arrived_at AND (o.departed_at IS NULL OR s.started_at < o.departed_at)) charge_end
        FROM o),
w AS (SELECT v.*, COALESCE(v.charge_end, v.arrived_at) free_at FROM v WHERE v.svc_s IS NOT NULL AND v.wash_s IS NOT NULL AND v.svc_s < v.wash_s)
SELECT count(*) visits_service_then_wash,
       round(sum(GREATEST(extract(epoch FROM (svc_s - free_at))/60, 0))::numeric, 0) min_waiting_for_the_service_bay,
       round(sum((SELECT count(*) FROM generate_series(w.free_at, w.svc_s - interval '5 minutes', interval '5 minutes') g
                   WHERE (SELECT count(*) FROM ottoq_stall_bookings b2 JOIN stalls s2 ON s2.id=b2.stall_id, r
                           WHERE b2.sim_run_id=r.run AND s2.depot_id='11111111-1111-1111-1111-111111111111' AND s2.stall_type='wash_bay'
                             AND b2.state IN ('held','active','done','interrupted') AND b2.during @> g) < 3) * 5)::numeric, 0) min_a_wash_bay_stood_free,
       round(sum(extract(epoch FROM (LEAST((SELECT max(e) FROM bk WHERE bk.visit_id=w.visit_id AND lane='wash_bay'), r.t1) - w.wash_s))/60)::numeric, 0) wash_min_after
  FROM w, r;
