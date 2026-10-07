-- 0415  **The agent's charge order, measured in the twin: taken whole (0614) it cost the depot uptime, departures and
--        on-time readiness against the same seed without it, because it put low batteries on L2s and left top-offs
--        waiting; 0617 and 0618 make the kernel check each order against its own before taking it.** One paired run
--        per arm, single readings, not ranges. (G318 new)
--
--       Written 2026-10-07, 4:10 PM CT. Read-only. Twin depot 11111111-…, scenario busy_day, seed 8950314943655796957,
--       sim 13:00 to 15:11:06 (2.19 sim-hours, 116 cars), live playback x3 (about 4.3 real seconds a tick in every
--       arm). Arms:
--
--         81787ef9  kernel order. Agent v22 (answered 74 of 121 passes; 47 fell back on HTTP 429/503).
--         0bbdcc07  agent order taken whole (0614/0615, agent v23: answered 84 of 84 in the window).
--         089f46bd  agent order checked by the kernel (0617, 0618, agent v24). §5.
--
--       Every run was started by ottoq_operator_start_run (which does not purge) with run_by operator_demo, so all
--       three are still in the database. 3bb6c77a is NOT an arm: its first tick ran before its playback was set and
--       jumped the clock to 13:30 (its tick 1 is at sim 13:30:00 where the arms' are at 13:00:31-41); it was stopped
--       after two ticks and 089f46bd was started with the start and the playback in one transaction.
--
-- ══ §1 METHOD: THE KPI BOARD, CUT AT 15:11:06 ═══════════════════════════════════════════════════════════════════════
--
--   81787ef9 ended at sim 15:11:06.568569; the other arms ran on. ottoq_twin_kpi_board reads a run from its start to its
--   current clock, and three of its inputs are not windowed by it: turnaround reads every state event, the charger
--   section counts every session event, and the on-time and charge-wait helpers take the run's own clock as horizon
--   and read live vehicle SoC and live atom status. §6 below creates pg_temp copies that take a horizon and bound
--   every input by it: events at or before it, plugs and session ends at or before it, a service step done when its
--   done_at is, a car not ready by the horizon counted as not ready (instead of by its live SoC). The fit profile
--   prorates the kWh of a session that crosses the horizon by time.
--
--   **The copies reproduce the board.** Run on 81787ef9 at its own end, they return every figure of the board as
--   saved before this window (agentq/baseline_81787ef9.json): uptime 40.6, on time 14/12/5 of 31, charge wait p50 16.1
--   and p95 86.4, 95 owing / 59 charged / 36 waiting, turnaround 63.8 / 84.0, 78 arrivals, 71 departures, 43 sent back,
--   busy 89.6 / 84.6, sessions 118 / 73 / 9, service 228 done / 244 open, energy 1,673 / 1,164 / 567.5. The one
--   difference is the fit profile's low-battery band, which the saved file read at a lower threshold than 50%.
--
-- ══ §2 THE ORDER TAKEN WHOLE AGAINST THE KERNEL'S, SIM 13:00-15:11:06 ════════════════════════════════════════════════
--
--                                               81787ef9 kernel    0bbdcc07 agent order
--   uptime, % of fleet time                         40.6               33.2
--   on the road, %                                  37.0               31.5
--   revenue hours                                   93.7               79.9
--   departures (per hour)                           71 (32.5)          61 (27.9)
--   arrivals                                        78                 82
--   ready by the due time                           14 of 31 (45.2%)   13 of 33 (39.4%)
--   late / not ready at the cut                     12 / 5             7 / 13
--   charge wait, cars plugged: p50 / p95 min        16.1 / 86.4        12.1 / 83.6
--   still waiting for a charger at the cut          36 of 95           46 of 100
--   p95 wait counting those still waiting           84.6               131.1
--   first service after arrival, p50 / p90 min      8.0 / 59.1         0.8 / 21.2
--   turnaround p50 / p90 min                        63.8 / 84.0        68.4 / 85.2
--   staged awaiting service, car-hours              13.63              33.18
--   sessions started / completed                    118 / 73           106 / 64
--   L2 / DCFC busy, %                               89.6 / 84.6        86.0 / 88.2
--   energy to cars, kWh                             1,673              1,681
--   DCFC hours from cars at 80%+ (G315)             23.7%              33.1%
--   battery at dispatch                             avg 100, min 99    avg 100, min 99
--
--   The depot did the same charging work (energy to cars within 0.5%) for fewer cars. Every car still left at 99-100%
--   (rule 9 held in both arms); what moved is who charged when.
--
-- ══ §3 WHY: THE DECISION LEDGER, SEAT BY SEAT ════════════════════════════════════════════════════════════════════════
--
--   (a) **The first 40 seats are the same cars in both arms** (tick 2, before any order). From tick 48 the arms
--       differ, and every difference traced is the order's. At tick 48 only an L2 was free: the kernel seated a 93%
--       car (about 20 minutes on an L2); the agent's order put first a 44% immediate-dispatch car it had named for a
--       fast charger, and that car took the L2. Between 13:00 and 14:00 the order put 6 cars at 13% to 44% on L2s
--       when only L2s were free or the one free fast charger had just gone to the order's rank above (ticks 48, 76,
--       78, 84, 92, 228); each held its L2 for 2 to 3.5 hours. In that hour the kernel's arm started 53 L2 sessions
--       from 80%+ and 3 from below 50%; the order's started 38 and 8.
--   (b) **0614's key let it happen.** A car named for the kind not free got rank + 1000, but a car the order did not
--       name got NULL and sorted after it, so when only L2s were free a low battery named for a fast charger still
--       went ahead of every unnamed car. 0617 (applied 20261007202316) gives an unnamed car 500.
--   (c) **Seven cars at 86-93% waited 137 to 188 minutes**, staged to leave and sent back for a top-off at 13:00:31.
--       In the kernel's arm the same seven cars plugged in at 13:31-13:38 and left by 14:50. The agent named each of
--       them 36 to 60 times (ranks 1 to 8), mostly for a fast charger: past their due time, the prompt's rule 2 ("a
--       car whose due_in_min is shorter than its min_on_l2 needs a fast charger") sent them to the scarcest charger,
--       behind the low batteries its rule 3 sent there too. The decide path tried car ab7adca4 59 times in 3 hours;
--       every try ended no_compatible_available_stall, because the cars ahead of it took each free charger first.
--       At 90 minutes they were pinned, and the free chargers then went to immediate dispatches and the pinned head;
--       they plugged in at 15:46-16:08.
--   (d) **Not the energy dials.** The agent also wrote dials in 0bbdcc07 (36 set_policy in the window, all
--       energy_reserve_shave and the two demand factors; none in 81787ef9). Per kind of charger and band of battery,
--       finished sessions charged at the same rate in both arms (L2 from 80%+: 0.198 against 0.201 %/min; DCFC below
--       50%: 0.958 against 0.863), and energy to cars was equal, so the dials did not slow charging. They do show in the
--       energy: 30-minute grid peak 647.0 kW against 567.5, grid cost $92.68 against $83.68 in the window.
--   (e) **The model was not the problem.** Agent v23 answered 84 of 84 passes (Ultra 58, Super 26) against v22's 74
--       of 121, so the retry and fallback did their job. The order was answered, accepted and followed (kind taken as
--       named 11 of 19 by 13:36); it was the wrong order.
--
-- ══ §4 WHAT WAS BUILT FROM IT ════════════════════════════════════════════════════════════════════════════════════════
--
--   0617  a car the order does not name sorts at 500, ahead of a car named for the kind not free (§3b).
--   0618  the kernel's check: ottoq_charge_line_projection projects the line from the order's moment, in its own order
--         and in the agent's, as the cursor keeps them (immediate dispatch, the pin, the key, the stall pick's kind
--         rule; every car to its full target); ottoq_charge_order_verdict takes the agent's when at least as many cars
--         are ready by their due time and the line is ready no later, or more cars at most 10% later. Otherwise the
--         order is recorded refused with both projections and the kernel's order stands. On 0bbdcc07's live line
--         (48 cars) it took 0.17 s and split the agent's three latest orders two refused (+2.9% minutes to ready),
--         one taken (-1.5%); after it was applied, the next 10 v23 orders split 5 taken, 4 refused, 1 before the apply.
--   v24   the prompt states the check, and orders the line the way it rewards: a car that makes its due time only on
--         a fast charger first, then the shortest charge first, a late car as either, dcfc for a car that owes a lot
--         only when one frees soon. Deployed as edge version 36, byte-identical to b16b01b.
--
-- ══ §5 THE CHECKED ORDER: 089f46bd, SAME SEED, SAME WINDOW ═════════════════════════════════════════════════════════════
--
--   PENDING: filled when 089f46bd passes sim 15:11:06.
--
-- ══ §6 REPRODUCE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Read-only: pg_temp functions only. Run as one statement batch; the last SELECT returns one board per arm.

CREATE FUNCTION pg_temp.kw_charge_wait(p_run uuid, p_h timestamptz) RETURNS jsonb LANGUAGE sql STABLE AS $f$
  WITH h AS (
    SELECT r.sim_run_id AS run, LEAST(COALESCE(r.sim_clock_current, r.sim_clock_start), p_h) AS horizon
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run),
  v AS (
    SELECT vn.visit_id, vn.vehicle_id, vn.arrived_at,
           (SELECT a FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge' LIMIT 1) AS ca
      FROM public.ottoq_visit_needs vn, h
     WHERE vn.sim_run_id = h.run AND vn.arrived_at IS NOT NULL AND vn.arrived_at <= h.horizon
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge')),
  w AS (
    SELECT v.*, h.horizon,
           (SELECT min(o.started_at) FROM public.ocpp_sessions o
             WHERE o.sim_run_id = h.run AND o.vehicle_id = v.vehicle_id AND o.started_at >= v.arrived_at
               AND o.started_at <= h.horizon
               AND o.started_at < COALESCE((SELECT min(d.dispatched_at) FROM public.ottoq_vehicle_dispatches d
                                             WHERE d.sim_run_id = h.run AND d.vehicle_id = v.vehicle_id
                                               AND d.dispatched_at > v.arrived_at AND d.dispatched_at <= h.horizon),
                                           'infinity')) AS first_plug
      FROM v, h),
  x AS (
    SELECT w.*,
           CASE WHEN w.first_plug IS NOT NULL THEN 'charged'
                WHEN COALESCE(w.ca->>'status', 'open') IN ('done','skipped','cancelled')
                     AND COALESCE(NULLIF(w.ca->>'closed_at','')::timestamptz, NULLIF(w.ca->>'done_at','')::timestamptz,
                                  w.horizon) <= w.horizon THEN 'closed_without_a_session'
                ELSE 'waiting' END AS outcome,
           EXTRACT(epoch FROM COALESCE(w.first_plug, w.horizon) - w.arrived_at) / 60.0 AS m
      FROM w)
  SELECT jsonb_build_object(
    'owing', count(*),
    'charged', count(*) FILTER (WHERE outcome = 'charged'),
    'waiting_at_end', count(*) FILTER (WHERE outcome = 'waiting'),
    'closed_without_a_session', count(*) FILTER (WHERE outcome = 'closed_without_a_session'),
    'p50_min', round(percentile_cont(0.5)  WITHIN GROUP (ORDER BY m) FILTER (WHERE outcome = 'charged')::numeric, 1),
    'p95_min', round(percentile_cont(0.95) WITHIN GROUP (ORDER BY m) FILTER (WHERE outcome = 'charged')::numeric, 1),
    'waiting_p50_so_far_min', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY m) FILTER (WHERE outcome = 'waiting')::numeric, 1),
    'p95_floor_min', round(percentile_cont(0.95) WITHIN GROUP (ORDER BY m) FILTER (WHERE outcome <> 'closed_without_a_session')::numeric, 1))
    FROM x;
$f$;

CREATE FUNCTION pg_temp.kw_readiness(p_run uuid, p_h timestamptz) RETURNS jsonb LANGUAGE sql STABLE AS $f$
  WITH h AS (
    SELECT LEAST(COALESCE(r.sim_clock_current, r.sim_clock_start), p_h) AS horizon
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run),
  v AS (
    SELECT vn.visit_id, vn.vehicle_id, vn.arrived_at, vn.dispatch_due_at AS due,
           COALESCE(vn.target_soc, public.ottoq_default_target_soc()) AS tgt
      FROM public.ottoq_visit_needs vn, h
     WHERE vn.sim_run_id = p_run AND vn.dispatch_due_at IS NOT NULL AND vn.dispatch_due_at <= h.horizon),
  r AS (
    SELECT v.*,
           (SELECT min(cs.ended_at) FROM public.ocpp_sessions cs, h
             WHERE cs.sim_run_id = p_run AND cs.vehicle_id = v.vehicle_id AND cs.soc_end >= v.tgt
               AND cs.ended_at <= h.horizon) AS ready_at,
           (SELECT min(cs.ended_at) FROM public.ocpp_sessions cs, h
             WHERE cs.sim_run_id = p_run AND cs.vehicle_id = v.vehicle_id AND cs.soc_end >= v.tgt
               AND cs.started_at >= v.arrived_at AND cs.ended_at <= h.horizon) AS ready_visit_at
      FROM v)
  SELECT jsonb_build_object(
    'with_due', count(*),
    'on_time', count(*) FILTER (WHERE ready_at IS NOT NULL AND ready_at <= due),
    'late', count(*) FILTER (WHERE ready_at IS NOT NULL AND ready_at > due),
    'not_ready_at_end', count(*) FILTER (WHERE ready_at IS NULL),
    'pct', round(100.0 * count(*) FILTER (WHERE ready_at IS NOT NULL AND ready_at <= due) / NULLIF(count(*), 0), 1),
    'p50_late_min', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM ready_at - due) / 60.0)
                          FILTER (WHERE ready_at > due)::numeric, 1),
    'this_visit_on_time', count(*) FILTER (WHERE ready_visit_at IS NOT NULL AND ready_visit_at <= due),
    'this_visit_late', count(*) FILTER (WHERE ready_visit_at IS NOT NULL AND ready_visit_at > due),
    'this_visit_not_ready', count(*) FILTER (WHERE ready_visit_at IS NULL))
    FROM r;
$f$;

CREATE FUNCTION pg_temp.kw_fit(p_run uuid, p_h timestamptz) RETURNS jsonb LANGUAGE sql STABLE AS $f$
  WITH run AS (
    SELECT r.depot_id, LEAST(COALESCE(r.sim_clock_current, r.sim_clock_start), p_h) AS t_end, r.sim_clock_current AS now_sim
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run),
  s AS (
    SELECT st.stall_type::text AS t, o.soc_start,
           COALESCE(o.energy_delivered_kwh, 0)
             * CASE WHEN COALESCE(o.ended_at, run.now_sim) <= run.t_end THEN 1
                    ELSE EXTRACT(epoch FROM run.t_end - o.started_at)
                         / NULLIF(EXTRACT(epoch FROM COALESCE(o.ended_at, run.now_sim) - o.started_at), 0) END AS kwh,
           EXTRACT(epoch FROM LEAST(COALESCE(o.ended_at, run.t_end), run.t_end) - o.started_at) / 3600.0 AS h
      FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id CROSS JOIN run
     WHERE o.sim_run_id = p_run AND o.depot_id = run.depot_id AND st.depot_id = run.depot_id
       AND st.stall_type::text IN ('dcfc', 'l2') AND o.started_at <= run.t_end),
  agg AS (
    SELECT s.t, count(*) AS n, sum(s.h) AS h, sum(s.kwh) AS kwh,
           COALESCE(sum(s.h) FILTER (WHERE s.soc_start >= 80), 0) AS h_hi,
           count(*) FILTER (WHERE s.soc_start < 50) AS n_lo,
           avg(s.h) FILTER (WHERE s.soc_start < 50) AS h_lo
      FROM s GROUP BY s.t),
  dec AS (
    SELECT count(*) FILTER (WHERE d.proposed_action->>'stall_type' = 'dcfc'
                              AND d.proposed_action->'rationale'->>'wanted_type' = 'l2') AS fast_wanted_l2,
           count(*) FILTER (WHERE d.proposed_action->>'stall_type' = 'l2'
                              AND d.proposed_action->'rationale'->>'wanted_type' = 'dcfc') AS l2_wanted_fast
      FROM public.ottoq_decisions d, run
     WHERE d.sim_run_id = p_run AND d.depot_id = run.depot_id AND d.action_context = 'stall_assignment'
       AND d.outcome_status = 'enacted' AND d.sim_clock <= run.t_end)
  SELECT jsonb_build_object(
    'by_type', (SELECT jsonb_object_agg(a.t, jsonb_build_object(
        'sessions', a.n, 'session_hours', round(a.h, 1), 'kwh', round(a.kwh, 0),
        'hours_from_hi_soc', round(a.h_hi, 1), 'pct_hours_from_hi_soc', round(100 * a.h_hi / NULLIF(a.h, 0), 1),
        'sessions_from_lo_soc', a.n_lo, 'avg_min_from_lo_soc', round(a.h_lo * 60, 0))) FROM agg a),
    'fast_picks_by_cars_wanting_l2', (SELECT fast_wanted_l2 FROM dec),
    'l2_picks_by_cars_wanting_fast', (SELECT l2_wanted_fast FROM dec));
$f$;

CREATE FUNCTION pg_temp.kw_board(p_run uuid, p_h timestamptz) RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
  r record; v_hours numeric; v_split jsonb; v_cars int; v_turn jsonb; v_flow jsonb; v_out jsonb;
  v_service jsonb; v_energy jsonb; v_chargers jsonb; v_g30 numeric; v_den numeric;
BEGIN
  SELECT s.sim_run_id, s.depot_id, s.sim_clock_start AS t0,
         LEAST(COALESCE(s.sim_clock_current, s.sim_clock_start), p_h) AS t1
    INTO r FROM public.ottoq_sim_runs s WHERE s.sim_run_id = p_run;
  v_hours := GREATEST(EXTRACT(epoch FROM r.t1 - r.t0) / 3600.0, 0);

  WITH ev AS (
    SELECT e.entity_id AS vid, e.sim_clock_at AS at, e.event_seq AS seq,
           e.payload->'diff'->'current_state'->>'from' AS fs, e.payload->'diff'->'current_state'->>'to' AS ts
      FROM public.ottoq_events e
     WHERE e.sim_run_id = p_run AND e.event_type = 'vehicle.state_changed'
       AND e.payload->'diff' ? 'current_state' AND e.sim_clock_at IS NOT NULL AND e.sim_clock_at <= r.t1),
  seg AS (
    SELECT ev.vid, ev.ts AS state, GREATEST(ev.at, r.t0) AS s0,
           LEAST(COALESCE(lead(ev.at) OVER (PARTITION BY ev.vid ORDER BY ev.at, ev.seq), r.t1), r.t1) AS s1
      FROM ev
    UNION ALL
    SELECT f.vid, f.fs, r.t0, LEAST(f.at, r.t1)
      FROM (SELECT DISTINCT ON (vid) vid, at, fs FROM ev ORDER BY vid, at, seq) f
     WHERE f.at > r.t0),
  g AS (
    SELECT vid,
           CASE state
             WHEN 'deployed' THEN 'on_road' WHEN 'en_route_to_deployment' THEN 'leaving'
             WHEN 'en_route_to_depot' THEN 'returning' WHEN 'staged_for_departure' THEN 'ready'
             WHEN 'charging_dcfc' THEN 'charging_dcfc' WHEN 'charging_l2' THEN 'charging_l2'
             WHEN 'in_wash_bay' THEN 'in_bay' WHEN 'in_detail_bay' THEN 'in_bay' WHEN 'in_service_bay' THEN 'in_bay'
             WHEN 'arrived_at_gate' THEN 'queue'
             WHEN 'staged_awaiting_service' THEN 'between_steps' WHEN 'charge_complete_holding' THEN 'between_steps'
             WHEN 'service_complete_holding' THEN 'between_steps' WHEN 'emergency_staged' THEN 'between_steps'
             WHEN 'out_of_service' THEN 'down' WHEN 'tow_requested' THEN 'down'
             WHEN 'offline' THEN 'offline' ELSE 'other' END AS grp,
           GREATEST(EXTRACT(epoch FROM s1 - s0), 0) / 3600.0 AS h
      FROM seg)
  SELECT jsonb_object_agg(grp, round(hours, 2)), max(cars)::int INTO v_split, v_cars
    FROM (SELECT grp, sum(h) AS hours, (SELECT count(DISTINCT vid) FROM g) AS cars FROM g GROUP BY grp) x;

  WITH ev AS (
    SELECT e.entity_id AS vid, e.sim_clock_at AS at, e.event_seq AS seq,
           e.payload->'diff'->'current_state'->>'from' AS fs, e.payload->'diff'->'current_state'->>'to' AS ts
      FROM public.ottoq_events e
     WHERE e.sim_run_id = p_run AND e.event_type = 'vehicle.state_changed'
       AND e.payload->'diff' ? 'current_state' AND e.sim_clock_at IS NOT NULL AND e.sim_clock_at <= r.t1),
  k AS (SELECT ev.*, (ev.ts = 'arrived_at_gate' AND ev.fs IN ('en_route_to_depot','deployed') AND ev.at > r.t0) AS is_arr FROM ev),
  n AS (SELECT k.*, sum(CASE WHEN k.is_arr THEN 1 ELSE 0 END)
                      OVER (PARTITION BY k.vid ORDER BY k.at, k.seq ROWS UNBOUNDED PRECEDING) AS visit_no FROM k),
  v AS (
    SELECT vid, visit_no,
           min(at) FILTER (WHERE is_arr) AS arrived,
           min(at) FILTER (WHERE ts = 'staged_for_departure' AND NOT is_arr) AS ready_at,
           min(at) FILTER (WHERE ts IN ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay','in_service_bay')) AS first_service
      FROM n WHERE visit_no > 0 GROUP BY vid, visit_no)
  SELECT jsonb_build_object(
           'arrivals', count(*),
           'finished', count(*) FILTER (WHERE ready_at IS NOT NULL),
           'p50_min', round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM ready_at - arrived) / 60.0)
                             FILTER (WHERE ready_at IS NOT NULL))::numeric, 1),
           'p90_min', round((percentile_cont(0.9) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM ready_at - arrived) / 60.0)
                             FILTER (WHERE ready_at IS NOT NULL))::numeric, 1),
           'served', count(*) FILTER (WHERE first_service IS NOT NULL),
           'first_service_p50_min', round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM first_service - arrived) / 60.0)
                             FILTER (WHERE first_service IS NOT NULL))::numeric, 1),
           'first_service_p90_min', round((percentile_cont(0.9) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM first_service - arrived) / 60.0)
                             FILTER (WHERE first_service IS NOT NULL))::numeric, 1),
           'open_so_far_p50_min', round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM r.t1 - arrived) / 60.0)
                             FILTER (WHERE ready_at IS NULL))::numeric, 1))
    INTO v_turn FROM v;

  SELECT jsonb_build_object(
           'departures', count(*) FILTER (WHERE x.ts = 'deployed'),
           'arrivals', count(*) FILTER (WHERE x.ts = 'arrived_at_gate' AND x.fs IN ('en_route_to_depot','deployed')),
           'sent_back_before_leaving', count(*) FILTER (WHERE x.fs = 'staged_for_departure' AND x.ts = 'staged_awaiting_service'))
    INTO v_flow
    FROM (SELECT e.payload->'diff'->'current_state'->>'from' AS fs, e.payload->'diff'->'current_state'->>'to' AS ts
            FROM public.ottoq_events e
           WHERE e.sim_run_id = p_run AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'
             AND e.sim_clock_at > r.t0 AND e.sim_clock_at <= r.t1) x;

  SELECT jsonb_build_object('dispatched', count(*), 'soc_avg', round(avg(d.soc_at_dispatch_pct), 1),
           'soc_min', round(min(d.soc_at_dispatch_pct), 1), 'at_99_or_more', count(*) FILTER (WHERE d.soc_at_dispatch_pct >= 99))
    INTO v_out
    FROM public.ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = p_run AND d.dispatched_at > r.t0 AND d.dispatched_at <= r.t1;

  WITH a AS (
    SELECT CASE WHEN e->>'status' = 'done' AND COALESCE(NULLIF(e->>'done_at','')::timestamptz, r.t1) <= r.t1 THEN 'done'
                WHEN e->>'status' = 'cancelled' THEN 'cancelled' ELSE 'open' END AS st,
           COALESCE((e->>'must_do')::boolean, false) AS must_do
      FROM public.ottoq_visit_needs vn, jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) e
     WHERE vn.sim_run_id = p_run AND vn.arrived_at <= r.t1)
  SELECT jsonb_build_object('steps', count(*), 'done', count(*) FILTER (WHERE st = 'done'),
           'required', count(*) FILTER (WHERE must_do),
           'required_open', count(*) FILTER (WHERE must_do AND st = 'open'),
           'cancelled', count(*) FILTER (WHERE st = 'cancelled'))
    INTO v_service FROM a;

  WITH s AS (
    SELECT x.*, EXTRACT(epoch FROM (lead(x."timestamp") OVER (ORDER BY x."timestamp") - x."timestamp")) / 3600.0 AS dh
      FROM public.site_energy_snapshots x
     WHERE x.sim_run_id = p_run AND x.depot_id = r.depot_id AND x."timestamp" >= r.t0 AND x."timestamp" <= r.t1)
  SELECT jsonb_build_object('to_cars_kwh', round(sum(COALESCE(total_ev_charging_kw, 0) * COALESCE(dh, 0)), 0),
           'grid_import_kwh', round(sum(COALESCE(grid_import_kw, 0) * COALESCE(dh, 0)), 0),
           'grid_cost_usd', round(sum(COALESCE(grid_import_kw, 0) * COALESCE(dh, 0) * current_rate_per_kwh)
                                  FILTER (WHERE current_rate_per_kwh IS NOT NULL), 2))
    INTO v_energy FROM s;
  WITH s AS (
    SELECT x."timestamp" AS t, GREATEST(COALESCE(x.grid_import_kw, 0), 0) AS g
      FROM public.site_energy_snapshots x
     WHERE x.sim_run_id = p_run AND x.depot_id = r.depot_id AND x."timestamp" >= r.t0 AND x."timestamp" <= r.t1),
  w AS (SELECT s.t, max(s.t) OVER () AS t_last,
               avg(s.g) OVER (ORDER BY s.t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30 FROM s)
  SELECT max(w.g30) INTO v_g30 FROM w WHERE w.t <= w.t_last - interval '30 minutes';
  v_energy := v_energy || jsonb_build_object('peak_grid_kw_30min', round(v_g30, 1));

  SELECT jsonb_build_object(
           'dcfc_busy_pct', round(100.0 * COALESCE((v_split->>'charging_dcfc')::numeric, 0)
                                  / NULLIF(count(*) FILTER (WHERE st.stall_type::text = 'dcfc') * v_hours, 0), 1),
           'l2_busy_pct', round(100.0 * COALESCE((v_split->>'charging_l2')::numeric, 0)
                                  / NULLIF(count(*) FILTER (WHERE st.stall_type::text = 'l2') * v_hours, 0), 1),
           'sessions_started', (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id = p_run
                                   AND e.event_type = 'charge.session_started' AND e.sim_clock_at <= r.t1),
           'sessions_completed', (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id = p_run
                                   AND e.event_type = 'charge.session_completed' AND e.sim_clock_at <= r.t1),
           'sessions_faulted', (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id = p_run
                                   AND e.event_type = 'charge.session_faulted' AND e.sim_clock_at <= r.t1))
    INTO v_chargers
    FROM public.stalls st WHERE st.depot_id = r.depot_id;

  v_den := v_hours * v_cars - COALESCE((v_split->>'offline')::numeric, 0) - COALESCE((v_split->>'other')::numeric, 0);
  RETURN jsonb_build_object(
    'window', jsonb_build_object('from', r.t0, 'to', r.t1, 'hours', round(v_hours, 2)),
    'cars', v_cars,
    'uptime_pct', round(100.0 * (COALESCE((v_split->>'on_road')::numeric, 0) + COALESCE((v_split->>'leaving')::numeric, 0)
                                 + COALESCE((v_split->>'ready')::numeric, 0)) / NULLIF(v_den, 0), 1),
    'on_road_pct', round(100.0 * COALESCE((v_split->>'on_road')::numeric, 0) / NULLIF(v_den, 0), 1),
    'revenue_hours', round(COALESCE((v_split->>'on_road')::numeric, 0), 1),
    'split_hours', v_split,
    'turnaround', v_turn,
    'flow', v_flow || jsonb_build_object('departures_per_hour', round((v_flow->>'departures')::numeric / NULLIF(v_hours, 0), 1)),
    'departures', v_out,
    'service', v_service,
    'energy', v_energy,
    'chargers', v_chargers,
    'on_time', pg_temp.kw_readiness(p_run, p_h),
    'charger_wait', pg_temp.kw_charge_wait(p_run, p_h),
    'fit', pg_temp.kw_fit(p_run, p_h));
END
$f$;

SELECT x.arm, x.run, pg_temp.kw_board(x.run::uuid, '2026-10-07 15:11:06.568569+00') AS board
  FROM (VALUES ('kernel order',              '81787ef9-2b64-41bf-9969-93d348ae2446'),
               ('agent order, taken whole',  '0bbdcc07-6b45-4b55-a929-77ed4c76ab35'),
               ('agent order, checked',      '089f46bd-0798-4de7-b238-d0b9147353be')) x(arm, run);

-- the agent's passes and orders inside the window, per arm (evidence ledgers: they survive a purge)
SELECT m.sim_run_id::text AS run, m.model, m.outcome, count(*) AS calls
  FROM public.ottoq_model_call_ledger m
 WHERE m.sim_run_id IN ('81787ef9-2b64-41bf-9969-93d348ae2446','0bbdcc07-6b45-4b55-a929-77ed4c76ab35','089f46bd-0798-4de7-b238-d0b9147353be')
   AND m.provider = 'nvidia_nemotron' AND m.sim_clock <= '2026-10-07 15:11:06.568569+00'
 GROUP BY 1,2,3 ORDER BY 1,2,3;

SELECT o.sim_run_id::text AS run, o.status, o.projection->>'reason' AS verdict, count(*) AS orders
  FROM public.ottoq_agent_charge_orders o
 WHERE o.sim_run_id IN ('0bbdcc07-6b45-4b55-a929-77ed4c76ab35','089f46bd-0798-4de7-b238-d0b9147353be')
   AND o.sim_clock <= '2026-10-07 15:11:06.568569+00'
 GROUP BY 1,2,3 ORDER BY 1,2,3;
