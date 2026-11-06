-- lab/research/p2_capacity/g520_phantoms.sql -- run in a finished lab replica (psql -At -f). G520's count: the visits opened
-- while their car was still out at work, before it turned for home (a dispatch of the car began before the visit opened,
-- and the car had not yet turned home when it did). The legitimate visit of a recall opens on the tick the car turns home
-- (arrived_at = the dispatch's returning_started_at), so it is not counted. Per status and urgency, the cars, and how the
-- scorecard reads the run. LAB ONLY.
WITH run AS (SELECT sim_run_id FROM ottoq_sim_runs WHERE run_by = 'ab_harness' ORDER BY started_at DESC LIMIT 1),
v AS (
  SELECT vn.visit_id, vn.vehicle_id, vn.arrived_at, vn.status, vn.urgency,
         EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
                  WHERE d.vehicle_id = vn.vehicle_id AND d.sim_run_id = vn.sim_run_id
                    AND d.dispatched_at < vn.arrived_at
                    AND (d.returning_started_at IS NULL OR vn.arrived_at < d.returning_started_at)) AS opened_while_out
    FROM ottoq_visit_needs vn, run
   WHERE vn.sim_run_id = run.sim_run_id AND vn.depot_id = '11111111-1111-1111-1111-111111111111')
SELECT json_build_object(
  'visits', (SELECT count(*) FROM v),
  'opened_while_out', (SELECT count(*) FROM v WHERE opened_while_out),
  'cars', (SELECT count(DISTINCT vehicle_id) FROM v WHERE opened_while_out),
  'by_status', (SELECT json_object_agg(status, n) FROM (SELECT status, count(*) n FROM v WHERE opened_while_out GROUP BY 1) s),
  'by_urgency', (SELECT json_object_agg(COALESCE(urgency, '?'), n) FROM (SELECT urgency, count(*) n FROM v WHERE opened_while_out GROUP BY 1) s),
  'first', (SELECT json_agg(x) FROM (SELECT left(vehicle_id::text, 8) car, arrived_at, status, urgency FROM v
                                       WHERE opened_while_out ORDER BY arrived_at LIMIT 5) x));
