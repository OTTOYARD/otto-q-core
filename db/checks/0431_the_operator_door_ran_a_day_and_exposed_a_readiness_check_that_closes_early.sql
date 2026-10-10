-- 0431  **The operator door ran a whole day in the twin, every directive answered by its own operator, and it exposed
--        a readiness check that can close before the visit's work is done.** Step 4 of the twin data contract review
--        (2026-10-08). One deterministic pair, 0656's experiment f6128ef0, pair 134: twin_operator_door 0 against 1,
--        busy_day at the twin depot, 90 ticks of 6 sim-minutes from 8:00 AM CT, the agent quiesced. Written
--        2026-10-09 from 10:58 PM CT. One seed is one reading, not a range (G153). Every query below is read-only.
--
-- ══ §1 HOW THE PAIR RAN (reproduce: (1)) ══
--
--   One-shot cron job 794 ran ottoq_dial_pair(f6128ef0, its first seed 718694717691859268, an arm budget of 4,500 s) at
--   03:17 UTC (10:17 PM CT) and unscheduled itself. The pair held the world 2,445 s, to about 10:58 PM CT: control
--   658 s, treatment 1,787 s (the second arm in the pair's one transaction, 2.7x slower, as both arms of 0428's pairs).
--   Valid on every test the harness makes: complete (90 ticks each), the world identical, both arms paid the shield,
--   each arm read its own value of the flag, no arm error. 11 of 14 atoms moved; fp, ticks and calibration did not.
--   The flag changes when every directive is carried out, so every digest downstream of a command moves, h_cmd first
--   (an operator's answer is 'confirmed', the walk's was 'executed').
--
-- ══ §2 THE DOOR, IN THE TREATMENT ARM (reproduce: (2), (3)) ══
--
--     operator   directives   accepted   unable (vehicle_not_at_depot)
--     sim-a          220          211          9
--     sim-b          308          294         14
--
--   528 directives went out through the outbox and came back through the door: 528 directive.ack events, 528 inbox
--   rows, every one applied, and every directive's command row confirmed or refused under its own operator's name.
--   90 steps per operator, nothing held over at the end. 2 commands issued on the last tick expired unanswered (4 in
--   the control). ottoq_assert_operator_isolation over the arm: 0 violations on all five checks. 0655 held: the
--   finalizer left all 528 answers as their operators gave them. The control arm wrote 0 directive.ack events: the
--   walk answered its own commands, as it always has.
--
-- ══ §3 THE SCORECARD (reproduce: (4)) ══
--
--     key                                        off (0)    on (1)     delta
--     deployed_car_hours (primary, higher)          95.6      94.3      -1.3
--     unmet_demand_car_hours                       344.4     345.7      +1.3
--     trips_completed                                193       190        -3
--     charge_sessions                                211       213        +2
--     grid_import_kwh                             4,670.8   4,911.4    +240.7
--     energy_cost_usd                              336.72    357.00    +20.28
--     charge_wait_p50_min                             30        42       +12
--     charge_wait_p95_min                          307.2       372     +64.8
--     charges_waiting_at_horizon                      57        52        -5
--     median_turnaround_min                          180       156       -24
--     KPI 1 asset_hours_available_per_day         130.13    127.75     -2.38
--     KPI 2 service_point_turns_per_point_per_day   4.66      4.46     -0.20
--     KPI 3 peak_site_kw                           841.4     841.4         0
--     KPI 4 touch_events_per_turn                  0.368     0.374    +0.006
--     KPI 5 p95_time_to_service_min                  285         6      -279   NOT WHAT IT READS: §4
--     returns_unserved                                33        13       -20   NOT WHAT IT READS: §4
--     safety_critical_refused / _unprevented       0 / 0     0 / 0
--
--   The door carries a directive out at the clock it was issued, one tick (6 sim-minutes) sooner than the walk did
--   inside the next world tick. The arms deliver 240.7 kWh more and end 57.4 kWh fuller with the door on, with a
--   median turnaround 24 minutes shorter, and slightly fewer trips and deployed car-hours. One seed: these are single
--   readings, and a one-tick change in timing is inside the live twin's noise floor for most of them.
--
--   Vehicle first (rule 9), both arms: of the departures by cars that had come back, 84 (off) and 81 (on), not one
--   left with a required service open and not one left below 99% SoC (reproduce (8)).
--
-- ══ §4 THE FINDING: THE READINESS CHECK CAN CLOSE BEFORE THE VISIT'S WORK (G398; reproduce: (5), (6), (7)) ══
--
--   The readiness check is the last step of every visit: it confirms the car is fit to leave. In the treatment arm
--   150 visits closed theirs, 115 of them before the visit's other required work was done, on median about 3 minutes
--   after the car came back and on average 154 minutes before the check's planned start. 70 of those visits still
--   had required work open when the day ended. In the control arm 83 closed, none early. That is what KPI 5 and
--   returns_unserved read as service: KPI 5 takes a returned car's first leg to start, and an early readiness leg is
--   that first leg in 117 of the treatment's 164 measured returns (an interior inspection in 41 more; charges were
--   the first leg in 121 of 131 in the control). Read honestly, KPI 5 says nothing about the door on this pair.
--
--   The cause is a predicate, not the door. twin.ottoq_sim_advance_visit_atoms closes a pending readiness_check when
--   the car is staged_for_departure, or staged_awaiting_service with config svc_step 'ready', and reads a car with no
--   svc_step as 'ready' (COALESCE(v.config->>'svc_step', 'ready')). It never asks whether the visit's other atoms are
--   done. With the door on, the operators carry out OTTO-Q's staging directives at the start of each beat, before the
--   world moves, so a car that has just come back is staged with no svc_step yet, and its check closes on the spot.
--
--   The door made it common; it was already there. Across the 182 earlier twin-depot runs with the flag off whose
--   visits survive (since 2026-08-30), 411 of 18,349 readiness checks (2.2%) closed before their visit's other
--   required work: 252 of 1,367 (18.4%) on operator demo runs, the live twin a viewer watches, 141 of 13,360 (1.1%) on
--   research pairs and 18 of 3,622 (0.5%) on certification runs (reproduce (7)).
--
--   No car left early because of it. The departure test (0543, ottoq_departure_clear, at both dispatchers) reads
--   every required atom on its own, so a car whose readiness check closed early still waited for its charge and its
--   services (§3). What the early close does break is the check's meaning, and every reading that takes a closed
--   readiness check as a car's work being done.
--
-- ══ §5 WHAT FOLLOWS ══
--
--   (a) The flag stays 0. The next migration makes a readiness check close only when every other required atom of
--       its visit is done, the last atom by construction. It changes flag-off runs too (2.2% of checks), so it forces
--       a recertification. Then a second pair on the experiment's second seed, read as this one was.
--   (b) KPI 5's first leg should not be the readiness leg (a car's readiness check is not its service). With (a) in
--       place an early readiness leg cannot exist, so the KPI is not changed here.
--   (c) G399, open: twin.ottoq_sim_advance_visit_atoms labels every open visit of a car that is out 'complete', never
--       reading its required atoms. 8 visits on research pairs carry that label with every atom pending (reproduce (9)):
--       the car left at 100% 5-10 minutes before the arrival time of a visit generated for it, an arrival that never
--       happened. No car left with work open there; but the same line would label a real early departure complete.
--   (d) The second pair's arms are the first evidence the flip will be read on. This pair's are not: its treatment ran
--       the readiness defect at 77% of closes.
--
-- ══ queries ══

-- (1) The pair and its validity
SELECT p.pair_id, p.seed, p.ran_at, p.wall_s, p.complete, p.world_identical, p.both_paid_shield, p.dial_read_a, p.dial_read_b,
       p.differs, p.moved, p.run_a, p.run_b, p.metrics_a -> 'arm_error' AS err_a, p.metrics_b -> 'arm_error' AS err_b
  FROM public.ottoq_dial_pair_ledger p WHERE p.experiment_id = 'f6128ef0-ff37-4ed5-8764-aaef15de6bb7' ORDER BY p.pair_id;

-- (2) Who answered each arm's commands
WITH p AS (SELECT run_a, run_b FROM public.ottoq_dial_pair_ledger WHERE pair_id = 134)
SELECT CASE WHEN c.sim_run_id = p.run_a THEN 'control' ELSE 'treatment' END AS arm,
       c.status, COALESCE(c.confirmed_by, '-') AS confirmed_by, count(*) AS n
  FROM public.ottoq_vehicle_commands c, p WHERE c.sim_run_id IN (p.run_a, p.run_b)
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

-- (3) The treatment arm's operators, acks, inbox and isolation
WITH p AS (SELECT run_b FROM public.ottoq_dial_pair_ledger WHERE pair_id = 134)
SELECT o.source_name, o.outcome, o.ack ->> 'disposition' AS ack, COALESCE(o.ack ->> 'reason', '-') AS reason,
       o.door ->> 'disposition' AS door, count(*) AS n
  FROM twin.ottoq_twin_operator_log o, p WHERE o.sim_run_id = p.run_b GROUP BY 1, 2, 3, 4, 5 ORDER BY 1, 2;
WITH p AS (SELECT run_b FROM public.ottoq_dial_pair_ledger WHERE pair_id = 134)
SELECT (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id = p.run_b AND e.event_type = 'directive.ack') AS ack_events,
       (SELECT count(*) FROM public.ottoq_v2_inbox i WHERE i.sim_run_id = p.run_b) AS inbox_rows
  FROM p;
SELECT i.* FROM public.ottoq_dial_pair_ledger p, public.ottoq_assert_operator_isolation(p.run_b) i WHERE p.pair_id = 134;

-- (4) The scorecard
SELECT k.key, p.metrics_a -> k.key AS control, p.metrics_b -> k.key AS treatment, p.delta -> k.key AS delta
  FROM public.ottoq_dial_pair_ledger p,
       unnest(ARRAY['deployed_car_hours','unmet_demand_car_hours','trips_completed','charge_sessions','grid_import_kwh',
                    'energy_cost_usd','charge_wait_p50_min','charge_wait_p95_min','charges_waiting_at_horizon',
                    'median_turnaround_min','asset_hours_available_per_day','service_point_turns_per_point_per_day',
                    'peak_site_kw','touch_events_per_turn','p95_time_to_service_min','returns_unserved',
                    'safety_critical_refused','safety_critical_unprevented','soc_end_kwh','wall_s']) AS k(key)
 WHERE p.pair_id = 134 ORDER BY k.key;

-- (5) The first leg after each return, by kind
WITH p AS (SELECT run_a, run_b FROM public.ottoq_dial_pair_ledger WHERE pair_id = 134),
firsts AS (
  SELECT CASE WHEN d.sim_run_id = p.run_a THEN 'control' ELSE 'treatment' END AS arm,
         (SELECT l.leg_type || '|' || COALESCE(l.duration_basis ->> 'atom', '-') || '|' || round(EXTRACT(EPOCH FROM (l.actual_start_sim - d.actual_return_at)) / 60)
            FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = d.sim_run_id AND l.vehicle_id = d.vehicle_id AND l.leg_type <> ALL (ARRAY['taxi', 'stage'])
             AND l.actual_start_sim >= d.actual_return_at
           ORDER BY l.actual_start_sim LIMIT 1) AS first_leg
    FROM public.ottoq_vehicle_dispatches d, p
   WHERE d.sim_run_id IN (p.run_a, p.run_b) AND d.actual_return_at IS NOT NULL)
SELECT arm, split_part(first_leg, '|', 1) AS leg_type, split_part(first_leg, '|', 2) AS atom, count(*) AS n,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY split_part(first_leg, '|', 3)::numeric) AS p50_min_after_return
  FROM firsts WHERE first_leg IS NOT NULL GROUP BY 1, 2, 3 ORDER BY 1, 4 DESC;

-- (6) Readiness checks closed before their visit's other required work, this pair
WITH p AS (SELECT run_a, run_b FROM public.ottoq_dial_pair_ledger WHERE pair_id = 134),
v AS (
  SELECT CASE WHEN vn.sim_run_id = p.run_a THEN 'control' ELSE 'treatment' END AS arm,
         (SELECT (a->>'done_at')::timestamptz FROM jsonb_array_elements(vn.atoms) a
           WHERE a->>'svc' = 'readiness_check' AND a->>'status' = 'done' LIMIT 1) AS ready_at,
         (SELECT max((a->>'done_at')::timestamptz) FROM jsonb_array_elements(vn.atoms) a
           WHERE a->>'svc' <> 'readiness_check' AND COALESCE((a->>'must_do')::boolean, false) AND a->>'status' = 'done') AS last_other_done,
         (SELECT count(*) FROM jsonb_array_elements(vn.atoms) a
           WHERE a->>'svc' <> 'readiness_check' AND COALESCE((a->>'must_do')::boolean, false)
             AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')) AS other_open
    FROM public.ottoq_visit_needs vn, p WHERE vn.sim_run_id IN (p.run_a, p.run_b))
SELECT arm, count(ready_at) AS readiness_done,
       count(*) FILTER (WHERE ready_at IS NOT NULL AND (other_open > 0 OR last_other_done > ready_at)) AS closed_before_the_work,
       count(*) FILTER (WHERE ready_at IS NOT NULL AND other_open > 0) AS work_still_open_at_the_end
  FROM v GROUP BY 1 ORDER BY 1;

-- (7) The same, on every earlier twin-depot run whose visits survive, by who ran it
WITH v AS (
  SELECT r.run_by,
         (SELECT (a->>'done_at')::timestamptz FROM jsonb_array_elements(vn.atoms) a
           WHERE a->>'svc' = 'readiness_check' AND a->>'status' = 'done' LIMIT 1) AS ready_at,
         (SELECT max((a->>'done_at')::timestamptz) FROM jsonb_array_elements(vn.atoms) a
           WHERE a->>'svc' <> 'readiness_check' AND COALESCE((a->>'must_do')::boolean, false) AND a->>'status' = 'done') AS last_other_done,
         (SELECT count(*) FROM jsonb_array_elements(vn.atoms) a
           WHERE a->>'svc' <> 'readiness_check' AND COALESCE((a->>'must_do')::boolean, false)
             AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')) AS other_open
    FROM public.ottoq_visit_needs vn JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
   WHERE vn.depot_id = '11111111-1111-1111-1111-111111111111'
     AND vn.sim_run_id <> '50d87ed3-785b-4c15-ba02-e463978f8a2d')
SELECT COALESCE(run_by, '-') AS run_by, count(ready_at) AS readiness_done,
       count(*) FILTER (WHERE ready_at IS NOT NULL AND (other_open > 0 OR last_other_done > ready_at)) AS closed_before_the_work
  FROM v GROUP BY 1 ORDER BY 1;

-- (8) Vehicle first: departures by cars that had come back, against their visit's required work and their charge
WITH p AS (SELECT run_a, run_b FROM public.ottoq_dial_pair_ledger WHERE pair_id = 134),
d AS (
  SELECT CASE WHEN d.sim_run_id = p.run_a THEN 'control' ELSE 'treatment' END AS arm, d.dispatched_at, d.soc_at_dispatch_pct,
         (SELECT vn.visit_id FROM public.ottoq_visit_needs vn
           WHERE vn.sim_run_id = d.sim_run_id AND vn.vehicle_id = d.vehicle_id AND vn.arrived_at <= d.dispatched_at
           ORDER BY vn.arrived_at DESC LIMIT 1) AS visit_id
    FROM public.ottoq_vehicle_dispatches d, p WHERE d.sim_run_id IN (p.run_a, p.run_b))
SELECT d.arm, count(*) FILTER (WHERE d.visit_id IS NOT NULL) AS departures_after_a_visit,
       count(*) FILTER (WHERE d.visit_id IS NOT NULL AND EXISTS (
         SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
          WHERE vn.visit_id = d.visit_id AND a->>'svc' <> 'readiness_check' AND COALESCE((a->>'must_do')::boolean, false)
            AND (COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled') OR (a->>'done_at')::timestamptz > d.dispatched_at))) AS left_with_work_open,
       count(*) FILTER (WHERE d.visit_id IS NOT NULL AND d.soc_at_dispatch_pct < 99) AS left_below_99_pct
  FROM d GROUP BY 1 ORDER BY 1;

-- (9) G399: visits marked complete with every required atom pending
SELECT vn.visit_id, r.run_by, vn.sim_run_id, vn.visit_key, vn.archetype, vn.urgency, vn.arrived_at,
       (SELECT string_agg(a->>'svc', ',') FROM jsonb_array_elements(vn.atoms) a
         WHERE COALESCE((a->>'must_do')::boolean, false) AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')) AS open_must_do
  FROM public.ottoq_visit_needs vn JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
 WHERE vn.depot_id = '11111111-1111-1111-1111-111111111111' AND vn.status = 'complete'
   AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                WHERE a->>'svc' <> 'readiness_check' AND COALESCE((a->>'must_do')::boolean, false)
                  AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled'));
