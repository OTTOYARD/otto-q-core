-- lab/research/p2_capacity/post_idle_while_waiting.sql -- run in a finished lab replica (psql -At -f). Every 5-minute tick of the
-- day: the cars parked or at the gate whose charge has not begun (a visit with a charge to do, arrived, no session yet,
-- state staged_awaiting_service or arrived_at_gate) against the fast-charge posts with no car, no reservation and no
-- session, split by whether the post's last session ended in a fault (the charger is in repair, or was until the next car
-- plugged in: an upper bound on repair time). Post state is rebuilt from stall.state_changed events, car state from
-- vehicle.state_changed events. LAB ONLY.
WITH run AS (SELECT sim_run_id, sim_clock_start AS t0, sim_clock_current AS t1 FROM ottoq_sim_runs LIMIT 1),
ticks AS (SELECT t FROM run, generate_series(run.t0, run.t1, interval '5 min') t),
posts AS (SELECT s.id AS stall_id FROM stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'dcfc'),
ev AS (SELECT e.entity_id AS stall_id, e.sim_clock_at AS at, e.event_id, e.payload->'diff' AS d
         FROM ottoq_events e JOIN posts p ON p.stall_id = e.entity_id WHERE e.event_type = 'stall.state_changed'),
grid AS (
  SELECT tk.t, p.stall_id,
         COALESCE((SELECT NULLIF(o.d->'current_vehicle_id'->>'to','') FROM ev o WHERE o.stall_id = p.stall_id AND o.d ? 'current_vehicle_id' AND o.at <= tk.t ORDER BY o.at DESC, o.event_id DESC LIMIT 1),
                  (SELECT NULLIF(o.d->'current_vehicle_id'->>'from','') FROM ev o WHERE o.stall_id = p.stall_id AND o.d ? 'current_vehicle_id' AND o.at > tk.t ORDER BY o.at, o.event_id LIMIT 1)) AS occupant,
         COALESCE((SELECT NULLIF(o.d->'reserved_by'->>'to','') FROM ev o WHERE o.stall_id = p.stall_id AND o.d ? 'reserved_by' AND o.at <= tk.t ORDER BY o.at DESC, o.event_id DESC LIMIT 1),
                  (SELECT NULLIF(o.d->'reserved_by'->>'from','') FROM ev o WHERE o.stall_id = p.stall_id AND o.d ? 'reserved_by' AND o.at > tk.t ORDER BY o.at, o.event_id LIMIT 1)) AS reserved,
         EXISTS (SELECT 1 FROM ocpp_sessions s, run WHERE s.sim_run_id = run.sim_run_id AND s.stall_id = p.stall_id
                    AND s.started_at <= tk.t AND COALESCE(s.ended_at, 'infinity') > tk.t) AS charging,
         (SELECT s.status FROM ocpp_sessions s, run WHERE s.sim_run_id = run.sim_run_id AND s.stall_id = p.stall_id AND s.ended_at <= tk.t
           ORDER BY s.ended_at DESC LIMIT 1) = 'faulted' AS after_fault
    FROM ticks tk CROSS JOIN posts p),
vis AS (
  SELECT vn.visit_id, vn.vehicle_id, vn.arrived_at,
         (SELECT min(s.started_at) FROM ocpp_sessions s, run WHERE s.sim_run_id = run.sim_run_id AND s.vehicle_id = vn.vehicle_id AND s.started_at >= vn.arrived_at) AS first_charge
    FROM ottoq_visit_needs vn, run WHERE vn.sim_run_id = run.sim_run_id
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') <> 'cancelled')),
vstate AS (
  SELECT tk.t, v.visit_id,
         (SELECT COALESCE(e.payload->>'to', e.payload->'diff'->'current_state'->>'to') FROM ottoq_events e
           WHERE e.entity_id = v.vehicle_id AND e.event_type = 'vehicle.state_changed' AND e.sim_clock_at <= tk.t
             AND (e.payload ? 'to' OR e.payload->'diff' ? 'current_state') ORDER BY e.sim_clock_at DESC, e.event_id DESC LIMIT 1) AS st
    FROM ticks tk JOIN vis v ON v.arrived_at <= tk.t AND (v.first_charge IS NULL OR v.first_charge > tk.t)),
per_tick AS (
  SELECT g.t,
         (SELECT count(*) FROM vstate s WHERE s.t = g.t AND s.st IN ('staged_awaiting_service', 'arrived_at_gate')) AS waiting,
         count(*) FILTER (WHERE NOT g.charging AND g.occupant IS NULL AND g.reserved IS NULL AND g.after_fault) AS free_after_fault,
         count(*) FILTER (WHERE NOT g.charging AND g.occupant IS NULL AND g.reserved IS NULL AND NOT COALESCE(g.after_fault, false)) AS free_clean
    FROM grid g GROUP BY g.t)
SELECT json_build_object(
  'car_min_parked_or_at_gate_waiting_for_first_charge', sum(waiting) * 5,
  'post_min_free_after_a_fault_while_a_car_waited', sum(LEAST(waiting, free_after_fault)) * 5,
  'post_min_free_with_no_fault_while_a_car_waited', sum(LEAST(GREATEST(waiting - free_after_fault, 0), free_clean)) * 5,
  'ticks_with_a_clean_free_post_and_a_waiting_car', count(*) FILTER (WHERE waiting > free_after_fault AND free_clean > 0),
  'those_ticks_ct', (SELECT string_agg(to_char(t AT TIME ZONE 'America/Chicago', 'HH24:MI') || '(' || waiting || 'w/' || free_clean || 'f)', ' ' ORDER BY t) FROM per_tick p2 WHERE p2.waiting > p2.free_after_fault AND p2.free_clean > 0)
) FROM per_tick;
