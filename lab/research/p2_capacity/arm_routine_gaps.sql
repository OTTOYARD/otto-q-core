-- lab/research/p2_capacity/arm_routine_gaps.sql -- run in a finished lab replica (psql -At -f). Of the visits that left
-- after charging on a fast-charger post: how many left with no interior clean done (by the post's arm or anyone), split
-- by what the visit records (meta.arm_routine.outcome: 'cleaned', 'immediate_turnaround' (an owner's turnaround on a
-- charge shorter than the arm's cycle, 0765, by design), or none decided), with each one's charges. G516: the 'none'
-- cases are cars the arm was never offered while charging (a triage that cleared the tidy in the charge's last tick, a
-- routine cut short on another post). LAB ONLY.
WITH run AS (SELECT sim_run_id, sim_clock_start AS t0 FROM ottoq_sim_runs LIMIT 1),
o AS (SELECT o.* FROM run r, public.ottoq_visit_outcomes(r.sim_run_id) o WHERE o.departed_at IS NOT NULL),
ses AS (
  SELECT s.vehicle_id, s.started_at, s.ended_at, s.status,
         floor(extract(epoch FROM s.started_at - r.t0) / 300) AS tick_in, floor(extract(epoch FROM s.ended_at - r.t0) / 300) AS tick_out
    FROM ocpp_sessions s JOIN stalls st ON st.id = s.stall_id CROSS JOIN run r
   WHERE s.sim_run_id = r.sim_run_id AND st.stall_type::text = 'dcfc' AND s.ended_at IS NOT NULL),
x AS (
  SELECT o.visit_id, o.departed_at, vn.meta -> 'arm_routine' ->> 'outcome' AS arm,
         EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'interior_tidy' AND a->>'status' = 'done') AS tidy_done,
         (SELECT count(*) FROM ses s WHERE s.vehicle_id = o.vehicle_id AND s.started_at >= o.arrived_at AND s.started_at < o.departed_at) AS n_dcfc,
         (SELECT count(*) FROM ses s WHERE s.vehicle_id = o.vehicle_id AND s.started_at >= o.arrived_at AND s.started_at < o.departed_at AND s.tick_in = s.tick_out) AS n_one_tick,
         (SELECT count(*) FROM ses s WHERE s.vehicle_id = o.vehicle_id AND s.started_at >= o.arrived_at AND s.started_at < o.departed_at AND s.status = 'faulted') AS n_faulted,
         (SELECT round(min(extract(epoch FROM s.ended_at - s.started_at) / 60)::numeric, 1) FROM ses s WHERE s.vehicle_id = o.vehicle_id AND s.started_at >= o.arrived_at AND s.started_at < o.departed_at) AS min_charge_min
    FROM o JOIN ottoq_visit_needs vn ON vn.visit_id = o.visit_id)
SELECT count(*) AS departed, count(*) FILTER (WHERE n_dcfc > 0) AS departed_after_dcfc,
       count(*) FILTER (WHERE n_dcfc > 0 AND NOT tidy_done) AS left_without_tidy,
       count(*) FILTER (WHERE n_dcfc > 0 AND NOT tidy_done AND n_one_tick = n_dcfc) AS of_which_all_charges_one_tick,
       count(*) FILTER (WHERE n_dcfc > 0 AND NOT tidy_done AND n_faulted > 0) AS of_which_a_fault,
       (SELECT json_object_agg(o, k) FROM (SELECT COALESCE(arm, 'none') AS o, count(*) AS k FROM x
          WHERE n_dcfc > 0 AND NOT tidy_done GROUP BY 1) z) AS arm_outcomes,
       (SELECT json_agg(json_build_object('v', left(visit_id::text, 8), 'arm', arm, 'n', n_dcfc, 'one_tick', n_one_tick, 'fault', n_faulted, 'min_charge_min', min_charge_min) ORDER BY departed_at)
          FROM x WHERE n_dcfc > 0 AND NOT tidy_done) AS list
  FROM x;
