-- migration-version: 20261007024116
-- migration-name:    the_kpi_tab_reads_uptime_turnaround_service_and_energy
--
-- 0609  **The KPI tab reads what a depot owner, an OEM and an investor ask first: uptime, turnaround, service and
--       energy.** One read-only function over the run's own rows, and its grant to anon (the twin's reads all go out
--       on the anon key), in their own file because opening a read is an exposure decision (0560, 0606).
--
-- ══ §1 WHAT IT IS FOR ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-06: "the KPI tab is super weak and unclear and not reader friendly ... the first half is just random
--   super technical information that the average depot manager or owner or OEM or Investor would have any idea about.
--   It should hang very heavily on Vehicle up time and any other autonomous vehicle or depot KPI's that are extremely
--   relevant for revenue energy turnaround time service is completed, etc."
--
--   The five (CLAUDE.md 2.9, ottoq_kpi_five) stay exactly as they are and stay on the tab, under the new board. This
--   adds public.ottoq_twin_kpi_board(sim_run_id): every figure computed from ONE run's rows, inside that run's window
--   (sim_clock_start .. sim_clock_current), so each regenerates from the run id printed beside it.
--
-- ══ §2 WHAT IT MEASURES, AND FROM WHAT ══════════════════════════════════════════════════════════════════════════════
--
--   FLEET TIME   ottoq_events vehicle.state_changed rows that carry current_state (the signed stream; 1,380 of 31,225
--                on run fd6ed035, the same 1,380 transitions public.vehicle_state_log holds for that window), each state
--                held until the car's next change, clipped to the window. Before its first change a car held the state
--                that change left. Measured on fd6ed035: 677.8 car-hours = 116 cars x 5.84 h, every hour accounted for.
--   UPTIME       on the road (deployed) + leaving + staged ready, over fleet time less offline. Ready counts as up
--                because the car can work; a car driving back to the depot does not.
--   TURNAROUND   gate arrival (from en_route_to_depot or deployed) to the first staged_for_departure before the car's
--                next arrival. A visit still open at the end is COUNTED and its time so far reported, never timed as
--                finished: on a run stopped mid-day the finished visits are the shorter ones, and the board says so.
--   FLOW         arrivals, departures, and the times a car staged to leave was sent back to finish its work (rule 9).
--   DEPARTURES   battery at dispatch (ottoq_vehicle_dispatches.soc_at_dispatch_pct) for every dispatch inside the
--                window; miles and kWh of the trips that came back inside it.
--   SERVICE      the steps OTTO-Q planned on each visit (ottoq_visit_needs.atoms), done and open, by service.
--   ENERGY       site_energy_snapshots at the run's depot, each reading held until the next: kWh to cars, grid import,
--                solar, battery, cost (import x the reading's tariff rate), solar share, and the 15-minute peaks the
--                five already carry (ottoq_kpi_peak_site_kw, _demand).
--   CHARGERS     car-hours charging per charger type over (stalls of that type at the run's depot x window hours), and
--                the session started / completed / faulted events.
--   ON TIME, CHARGER WAIT   ottoq_kpi_dispatch_readiness and ottoq_kpi_charge_wait, carried as they are (their caveats
--                live in their own definitions, unchanged).
--
--   Nothing here is a final-frame instantaneous count (AGENTS.md: never quote vehicles_turned_around, fleet_ready_pct
--   or gate_backlog). Every figure is integrated over the run or counted inside it.
--
-- ══ §3 WHAT anon CAN THEN SEE, AND WHAT IT CANNOT ═══════════════════════════════════════════════════════════════════
--
--   CAN: anyone with the public anon key who names a run id (ids are already public through the twin's run list) can
--   read that run's aggregates above. CANNOT: read a single row, a vehicle id, an operator, a token or a ledger; change
--   anything (the function and both helpers it calls are asserted write-free on their comment-stripped source before the
--   grant). ottoq_kpi_charge_wait stays service-role only for direct calls; the board calls it as its owner, as the
--   control door already does for the five.
--
-- ══ §4 forces_recert FALSE, forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   A new read nothing on the tick path calls (V3), and a privilege bit. Invisible to every certification atom and every
--   dial arm.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0609 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: what it reads exists; this file is not applied ──
DO $premises$
BEGIN
  IF to_regprocedure('public.ottoq_kpi_dispatch_readiness(uuid)') IS NULL OR to_regprocedure('public.ottoq_kpi_charge_wait(uuid)') IS NULL
     OR to_regclass('public.ottoq_kpi_peak_site_kw') IS NULL OR to_regclass('public.ottoq_kpi_peak_site_kw_demand') IS NULL
     OR to_regclass('public.site_energy_snapshots') IS NULL OR to_regclass('public.ottoq_visit_needs') IS NULL THEN
    RAISE EXCEPTION '0609 P1: a source the board reads is missing';
  END IF;
  IF to_regprocedure('public.ottoq_twin_kpi_board(uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0609_the_kpi_tab_reads_uptime_turnaround_service_and_energy') THEN
    RAISE EXCEPTION '0609 P1: already applied';
  END IF;
END $premises$;

CREATE OR REPLACE FUNCTION public.ottoq_twin_kpi_board(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0609. The KPI tab's board for one run: fleet uptime and where fleet time went, turnaround, flow, battery at dispatch,
   service steps, energy and cost, charger use, on-time readiness and the wait for a charger. Every figure from this
   run's own rows inside its window. Read-only (asserted before the grant). */
DECLARE
  r          record;
  v_hours    numeric;
  v_split    jsonb;
  v_cars     integer;
  v_turn     jsonb;
  v_flow     jsonb;
  v_out      jsonb;
  v_service  jsonb;
  v_energy   jsonb;
  v_chargers jsonb;
  v_ready    jsonb;
  v_wait     jsonb;
  v_events   bigint;
BEGIN
  IF p_sim_run_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'run_required');
  END IF;
  SELECT s.sim_run_id, s.depot_id, s.scenario_code, s.status, s.purged_at,
         s.sim_clock_start AS t0, COALESCE(s.sim_clock_current, s.sim_clock_start) AS t1
    INTO r
    FROM public.ottoq_sim_runs s
   WHERE s.sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_run', 'sim_run_id', p_sim_run_id);
  END IF;
  v_hours := GREATEST(EXTRACT(epoch FROM r.t1 - r.t0) / 3600.0, 0);

  SELECT count(*) INTO v_events
    FROM public.ottoq_events e
   WHERE e.sim_run_id = p_sim_run_id AND e.event_type = 'vehicle.state_changed'
     AND e.payload -> 'diff' ? 'current_state';
  IF v_events = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_state_history', 'sim_run_id', p_sim_run_id,
      'purged_at', r.purged_at,
      'message', 'This run has no vehicle state history left (purged, or it never ticked). Its archive keeps the five KPIs.');
  END IF;

  -- ── 1. FLEET TIME: every car's state, held from one recorded change to the next, inside the run window ──────────
  WITH ev AS (
    SELECT e.entity_id AS vid, e.sim_clock_at AS at, e.event_seq AS seq,
           e.payload -> 'diff' -> 'current_state' ->> 'from' AS fs,
           e.payload -> 'diff' -> 'current_state' ->> 'to'   AS ts
      FROM public.ottoq_events e
     WHERE e.sim_run_id = p_sim_run_id AND e.event_type = 'vehicle.state_changed'
       AND e.payload -> 'diff' ? 'current_state' AND e.sim_clock_at IS NOT NULL),
  seg AS (
    SELECT ev.vid, ev.ts AS state, GREATEST(ev.at, r.t0) AS s0,
           LEAST(COALESCE(lead(ev.at) OVER (PARTITION BY ev.vid ORDER BY ev.at, ev.seq), r.t1), r.t1) AS s1
      FROM ev
    UNION ALL
    -- before its first recorded change, a car held the state that change left
    SELECT f.vid, f.fs, r.t0, LEAST(f.at, r.t1)
      FROM (SELECT DISTINCT ON (vid) vid, at, fs FROM ev ORDER BY vid, at, seq) f
     WHERE f.at > r.t0),
  g AS (
    SELECT vid,
           CASE state
             WHEN 'deployed'                 THEN 'on_road'
             WHEN 'en_route_to_deployment'   THEN 'leaving'
             WHEN 'en_route_to_depot'        THEN 'returning'
             WHEN 'staged_for_departure'     THEN 'ready'
             WHEN 'charging_dcfc'            THEN 'charging_dcfc'
             WHEN 'charging_l2'              THEN 'charging_l2'
             WHEN 'in_wash_bay'              THEN 'in_bay'
             WHEN 'in_detail_bay'            THEN 'in_bay'
             WHEN 'in_service_bay'           THEN 'in_bay'
             WHEN 'arrived_at_gate'          THEN 'queue'
             WHEN 'staged_awaiting_service'  THEN 'between_steps'
             WHEN 'charge_complete_holding'  THEN 'between_steps'
             WHEN 'service_complete_holding' THEN 'between_steps'
             WHEN 'emergency_staged'         THEN 'between_steps'
             WHEN 'out_of_service'           THEN 'down'
             WHEN 'tow_requested'            THEN 'down'
             WHEN 'offline'                  THEN 'offline'
             ELSE 'other' END AS grp,
           GREATEST(EXTRACT(epoch FROM s1 - s0), 0) / 3600.0 AS h
      FROM seg)
  SELECT jsonb_object_agg(grp, round(hours, 2)), max(cars)::int
    INTO v_split, v_cars
    FROM (SELECT grp, sum(h) AS hours, (SELECT count(DISTINCT vid) FROM g) AS cars FROM g GROUP BY grp) x;

  -- ── 2. TURNAROUND: one visit per arrival at the gate, to the first moment the car is staged ready ────────────────
  WITH ev AS (
    SELECT e.entity_id AS vid, e.sim_clock_at AS at, e.event_seq AS seq,
           e.payload -> 'diff' -> 'current_state' ->> 'from' AS fs,
           e.payload -> 'diff' -> 'current_state' ->> 'to'   AS ts
      FROM public.ottoq_events e
     WHERE e.sim_run_id = p_sim_run_id AND e.event_type = 'vehicle.state_changed'
       AND e.payload -> 'diff' ? 'current_state' AND e.sim_clock_at IS NOT NULL),
  arr AS (
    SELECT vid, at, seq, lead(at) OVER (PARTITION BY vid ORDER BY at, seq) AS next_arr
      FROM ev WHERE ts = 'arrived_at_gate' AND fs IN ('en_route_to_depot', 'deployed') AND at > r.t0),
  v AS (
    SELECT a.vid, a.at AS arrived,
           (SELECT min(e.at) FROM ev e WHERE e.vid = a.vid AND e.ts = 'staged_for_departure'
               AND (e.at, e.seq) > (a.at, a.seq) AND (a.next_arr IS NULL OR e.at < a.next_arr)) AS ready_at,
           (SELECT min(e.at) FROM ev e WHERE e.vid = a.vid AND e.ts IN ('deployed', 'en_route_to_deployment')
               AND (e.at, e.seq) > (a.at, a.seq) AND (a.next_arr IS NULL OR e.at <= a.next_arr)) AS left_at,
           (SELECT min(e.at) FROM ev e WHERE e.vid = a.vid
               AND e.ts IN ('charging_dcfc', 'charging_l2', 'in_wash_bay', 'in_detail_bay', 'in_service_bay')
               AND (e.at, e.seq) > (a.at, a.seq) AND (a.next_arr IS NULL OR e.at < a.next_arr)) AS first_service
      FROM arr a)
  SELECT jsonb_build_object(
           'arrivals',              count(*),
           'finished',              count(*) FILTER (WHERE ready_at IS NOT NULL),
           'still_in_depot',        count(*) FILTER (WHERE ready_at IS NULL),
           'p50_min',               round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM ready_at - arrived) / 60.0)
                                            FILTER (WHERE ready_at IS NOT NULL))::numeric, 1),
           'p90_min',               round((percentile_cont(0.9) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM ready_at - arrived) / 60.0)
                                            FILTER (WHERE ready_at IS NOT NULL))::numeric, 1),
           'dwell_p50_min',         round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM left_at - arrived) / 60.0)
                                            FILTER (WHERE left_at IS NOT NULL))::numeric, 1),
           'served',                count(*) FILTER (WHERE first_service IS NOT NULL),
           'first_service_p50_min', round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM first_service - arrived) / 60.0)
                                            FILTER (WHERE first_service IS NOT NULL))::numeric, 1),
           'first_service_p90_min', round((percentile_cont(0.9) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM first_service - arrived) / 60.0)
                                            FILTER (WHERE first_service IS NOT NULL))::numeric, 1),
           'open_so_far_p50_min',   round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM r.t1 - arrived) / 60.0)
                                            FILTER (WHERE ready_at IS NULL))::numeric, 1))
    INTO v_turn
    FROM v;

  -- ── 3. FLOW: cars in, cars out, inside the window ─────────────────────────────────────────────────────────────────
  SELECT jsonb_build_object(
           'departures', count(*) FILTER (WHERE x.ts = 'deployed'),
           'arrivals',   count(*) FILTER (WHERE x.ts = 'arrived_at_gate' AND x.fs IN ('en_route_to_depot', 'deployed')),
           'sent_back_before_leaving', count(*) FILTER (WHERE x.fs = 'staged_for_departure' AND x.ts = 'staged_awaiting_service'))
    INTO v_flow
    FROM (SELECT e.payload -> 'diff' -> 'current_state' ->> 'from' AS fs,
                 e.payload -> 'diff' -> 'current_state' ->> 'to'   AS ts
            FROM public.ottoq_events e
           WHERE e.sim_run_id = p_sim_run_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload -> 'diff' ? 'current_state'
             AND e.sim_clock_at > r.t0 AND e.sim_clock_at <= r.t1) x;

  -- ── 4. DEPARTURES: battery at dispatch, and what the trips that came back did ─────────────────────────────────────
  SELECT jsonb_build_object(
           'dispatched',          count(*),
           'soc_avg',             round(avg(d.soc_at_dispatch_pct), 1),
           'soc_min',             round(min(d.soc_at_dispatch_pct), 1),
           'at_99_or_more',       count(*) FILTER (WHERE d.soc_at_dispatch_pct >= 99),
           'soc_unknown',         count(*) FILTER (WHERE d.soc_at_dispatch_pct IS NULL))
    INTO v_out
    FROM public.ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = p_sim_run_id AND d.dispatched_at > r.t0 AND d.dispatched_at <= r.t1;
  v_out := v_out || (
    SELECT jsonb_build_object(
             'trips_back',        count(*),
             'miles',             round(sum(d.miles_driven), 0),
             'kwh_used',          round(sum(d.energy_consumed_kwh), 0),
             'soc_back_avg',      round(avg(d.soc_at_return_pct), 1))
      FROM public.ottoq_vehicle_dispatches d
     WHERE d.sim_run_id = p_sim_run_id AND d.actual_return_at IS NOT NULL
       AND d.actual_return_at > r.t0 AND d.actual_return_at <= r.t1);

  -- ── 5. SERVICE: the steps OTTO-Q planned for each visit, by service ───────────────────────────────────────────────
  WITH a AS (
    SELECT e ->> 'svc' AS svc, COALESCE(e ->> 'status', 'never_started') AS st,
           COALESCE((e ->> 'must_do')::boolean, false) AS must_do
      FROM public.ottoq_visit_needs vn, jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) e
     WHERE vn.sim_run_id = p_sim_run_id)
  SELECT jsonb_build_object(
           'steps',          (SELECT count(*) FROM a),
           'done',           (SELECT count(*) FROM a WHERE st = 'done'),
           'required',       (SELECT count(*) FROM a WHERE must_do),
           'required_done',  (SELECT count(*) FROM a WHERE must_do AND st = 'done'),
           'required_open',  (SELECT count(*) FROM a WHERE must_do AND st NOT IN ('done', 'cancelled')),
           'cancelled',      (SELECT count(*) FROM a WHERE st = 'cancelled'),
           'by_service',     COALESCE((
              SELECT jsonb_agg(jsonb_build_object('svc', s.svc, 'name', COALESCE(c.display_name, s.svc), 'lane', c.lane,
                                                  'done', s.done, 'total', s.total) ORDER BY s.done DESC, s.svc)
                FROM (SELECT svc, count(*) FILTER (WHERE st = 'done') AS done, count(*) AS total FROM a GROUP BY svc) s
                LEFT JOIN public.service_cadence_policy c ON c.svc = s.svc), '[]'::jsonb))
    INTO v_service;

  -- ── 6. ENERGY: every site reading, held until the next one ────────────────────────────────────────────────────────
  WITH s AS (
    SELECT x.*, EXTRACT(epoch FROM (lead(x."timestamp") OVER (ORDER BY x."timestamp") - x."timestamp")) / 3600.0 AS dh
      FROM public.site_energy_snapshots x
     WHERE x.sim_run_id = p_sim_run_id AND x.depot_id = r.depot_id
       AND x."timestamp" >= r.t0 AND x."timestamp" <= r.t1),
  t AS (
    SELECT count(*) AS n,
           sum(COALESCE(total_ev_charging_kw, 0) * COALESCE(dh, 0))                       AS ev_kwh,
           sum(COALESCE(grid_import_kw, 0) * COALESCE(dh, 0))                             AS import_kwh,
           sum(COALESCE(grid_export_kw, 0) * COALESCE(dh, 0))                             AS export_kwh,
           sum(COALESCE(solar_generation_kw, 0) * COALESCE(dh, 0))                        AS solar_kwh,
           sum(GREATEST(COALESCE(bess_output_kw, 0), 0) * COALESCE(dh, 0))                AS bess_out_kwh,
           sum(GREATEST(-COALESCE(bess_output_kw, 0), 0) * COALESCE(dh, 0))               AS bess_in_kwh,
           sum((COALESCE(building_load_kw, 0) + COALESCE(lighting_load_kw, 0)) * COALESCE(dh, 0)) AS site_kwh,
           sum(COALESCE(grid_import_kw, 0) * COALESCE(dh, 0) * current_rate_per_kwh)
             FILTER (WHERE current_rate_per_kwh IS NOT NULL)                               AS cost_usd,
           sum(COALESCE(grid_import_kw, 0) * COALESCE(dh, 0))
             FILTER (WHERE current_rate_per_kwh IS NOT NULL)                               AS priced_kwh
      FROM s)
  SELECT jsonb_build_object(
           'snapshots',             t.n,
           'to_cars_kwh',           round(t.ev_kwh, 0),
           'grid_import_kwh',       round(t.import_kwh, 0),
           'grid_export_kwh',       round(t.export_kwh, 0),
           'solar_kwh',             round(t.solar_kwh, 0),
           'battery_out_kwh',       round(t.bess_out_kwh, 0),
           'battery_in_kwh',        round(t.bess_in_kwh, 0),
           'building_kwh',          round(t.site_kwh, 0),
           'grid_cost_usd',         round(t.cost_usd, 2),
           'grid_price_usd_kwh',    round(t.cost_usd / NULLIF(t.priced_kwh, 0), 4),
           'solar_share_pct',       round(100.0 * t.solar_kwh / NULLIF(t.import_kwh + t.solar_kwh + t.bess_out_kwh, 0), 1),
           'peak_grid_kw_15min',    (SELECT k.peak_site_kw_15min FROM public.ottoq_kpi_peak_site_kw k WHERE k.sim_run_id = p_sim_run_id),
           'peak_load_kw_15min',    (SELECT k.peak_site_kw_demand_15min FROM public.ottoq_kpi_peak_site_kw_demand k WHERE k.sim_run_id = p_sim_run_id))
    INTO v_energy
    FROM t;

  -- ── 7. CHARGERS: car-hours on each charger type over the stalls of that type at this depot ────────────────────────
  SELECT jsonb_build_object(
           'dcfc_stalls',        count(*) FILTER (WHERE st.stall_type::text = 'dcfc'),
           'l2_stalls',          count(*) FILTER (WHERE st.stall_type::text = 'l2'),
           'dcfc_busy_pct',      round(100.0 * COALESCE((v_split ->> 'charging_dcfc')::numeric, 0)
                                   / NULLIF(count(*) FILTER (WHERE st.stall_type::text = 'dcfc') * v_hours, 0), 1),
           'l2_busy_pct',        round(100.0 * COALESCE((v_split ->> 'charging_l2')::numeric, 0)
                                   / NULLIF(count(*) FILTER (WHERE st.stall_type::text = 'l2') * v_hours, 0), 1),
           'sessions_started',   (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id = p_sim_run_id AND e.event_type = 'charge.session_started'),
           'sessions_completed', (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id = p_sim_run_id AND e.event_type = 'charge.session_completed'),
           'sessions_faulted',   (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id = p_sim_run_id AND e.event_type = 'charge.session_faulted'))
    INTO v_chargers
    FROM public.stalls st
   WHERE st.depot_id = r.depot_id;

  -- ── 8. ON TIME and THE WAIT FOR A CHARGER: the engine's own measures, carried as they are ────────────────────────
  v_ready := public.ottoq_kpi_dispatch_readiness(p_sim_run_id);
  v_wait  := public.ottoq_kpi_charge_wait(p_sim_run_id);

  RETURN jsonb_build_object(
    'ok',          true,
    'sim_run_id',  r.sim_run_id,
    'depot_id',    r.depot_id,
    'scenario',    r.scenario_code,
    'status',      r.status,
    'window',      jsonb_build_object('from', r.t0, 'to', r.t1, 'hours', round(v_hours, 2)),
    'cars',        v_cars,
    'fleet_hours', round(v_hours * v_cars, 1),
    'split_hours', v_split,
    'uptime', jsonb_build_object(
       'pct',               round(100.0 * (COALESCE((v_split ->> 'on_road')::numeric, 0) + COALESCE((v_split ->> 'leaving')::numeric, 0)
                                    + COALESCE((v_split ->> 'ready')::numeric, 0))
                              / NULLIF(v_hours * v_cars - COALESCE((v_split ->> 'offline')::numeric, 0) - COALESCE((v_split ->> 'other')::numeric, 0), 0), 1),
       'on_road_pct',       round(100.0 * COALESCE((v_split ->> 'on_road')::numeric, 0)
                              / NULLIF(v_hours * v_cars - COALESCE((v_split ->> 'offline')::numeric, 0) - COALESCE((v_split ->> 'other')::numeric, 0), 0), 1),
       'revenue_hours',     round(COALESCE((v_split ->> 'on_road')::numeric, 0), 1),
       'revenue_hours_per_car_day', round(COALESCE((v_split ->> 'on_road')::numeric, 0) / NULLIF(v_cars, 0) * 24.0 / NULLIF(v_hours, 0), 1)),
    'turnaround',  v_turn,
    'flow',        v_flow || jsonb_build_object('departures_per_hour', round(((v_flow ->> 'departures')::numeric) / NULLIF(v_hours, 0), 1)),
    'departures',  v_out,
    'service',     v_service,
    'energy',      v_energy,
    'chargers',    v_chargers,
    'on_time',     jsonb_build_object(
       'pct', v_ready -> 'on_time_pct', 'on_time', v_ready -> 'on_time', 'late', v_ready -> 'late',
       'stranded', v_ready -> 'stranded', 'with_due', v_ready -> 'visits_with_due', 'p50_late_min', v_ready -> 'p50_late_min',
       'basis', 'ottoq_kpi_dispatch_readiness: a visit with a due time is on time when a charge reaches its target by that time. Its end-of-run battery reading is live shared state, correct while this is the last run to touch the fleet.'),
    'charger_wait', jsonb_build_object(
       'p50_min', v_wait -> 'p50_wait_min', 'p95_min', v_wait -> 'p95_wait_min', 'p95_floor_min', v_wait -> 'p95_wait_floor_min',
       'charged', v_wait -> 'charged', 'waiting_at_end', v_wait -> 'waiting_at_horizon', 'owing', v_wait -> 'visits_owing_a_charge',
       'waiting_p50_so_far_min', v_wait -> 'waiting_p50_so_far_min'),
    'basis', jsonb_build_object(
       'fleet_time',  'public.ottoq_events vehicle.state_changed rows that carry current_state, each state held until the car''s next change, clipped to sim_clock_start..sim_clock_current. Before a car''s first change it held the state that change left.',
       'uptime',      'on the road (deployed) + leaving + staged ready, over fleet time less offline. Ready counts as up: the car can work.',
       'turnaround',  'from a car''s arrival at the gate (from en_route_to_depot or deployed) to its first staged_for_departure before its next arrival. Visits still open at the end are counted, not timed.',
       'energy',      'public.site_energy_snapshots, each reading held until the next. Cost is grid import times the reading''s tariff rate.',
       'chargers',    'car-hours charging_dcfc / charging_l2 over (stalls of that type at this depot x window hours). A faulted charger still counts as a stall.'));
END

$fn$;

REVOKE ALL ON FUNCTION public.ottoq_twin_kpi_board(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ── the safety gate (0405, 0560, 0606): write-free on its comment-stripped source, and the helpers it calls ──
DO $gate$
DECLARE v_src text;
BEGIN
  FOR v_src IN
    SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g')
      FROM pg_proc p
     WHERE p.oid IN ('public.ottoq_twin_kpi_board(uuid)'::regprocedure,
                     'public.ottoq_kpi_dispatch_readiness(uuid)'::regprocedure,
                     'public.ottoq_kpi_charge_wait(uuid)'::regprocedure)
  LOOP
    IF v_src ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\(|set_config[[:space:]]*\()' THEN
      RAISE EXCEPTION '0609: the KPI board (or a helper it calls) contains a write; it must not be granted to anon';
    END IF;
  END LOOP;
  IF (public.ottoq_twin_kpi_board(NULL) ->> 'error') IS DISTINCT FROM 'run_required' THEN
    RAISE EXCEPTION '0609: the KPI board answers without a run';
  END IF;
END $gate$;

GRANT EXECUTE ON FUNCTION public.ottoq_twin_kpi_board(uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_twin_kpi_board(uuid) IS
'0609. The KPI tab''s board for one run (anon-executable, read-only): fleet uptime and the split of fleet time, turnaround gate to ready, flow, battery at dispatch, service steps done and open, energy (kWh to cars, grid, solar, cost, 15-min peaks), charger use, on-time readiness and the wait for a charger. Every figure from the run''s own rows inside sim_clock_start..sim_clock_current; definitions in the payload''s basis key.';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_run uuid; v_b jsonb; v_split numeric; v_fleet numeric;
BEGIN
  -- V1: anon has this one read
  IF NOT has_function_privilege('anon', 'public.ottoq_twin_kpi_board(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0609 V1: the grant did not take';
  END IF;
  -- V2: the helpers keep their own grants (the board opens no other door)
  IF has_function_privilege('anon', 'public.ottoq_kpi_charge_wait(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0609 V2: anon can call ottoq_kpi_charge_wait directly';
  END IF;
  -- V3: nothing on the tick path, and no existing routine, calls it
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname <> 'ottoq_twin_kpi_board'
                AND p.prosrc ~* 'ottoq_twin_kpi_board') THEN
    RAISE EXCEPTION '0609 V3: an existing routine calls the KPI board';
  END IF;
  -- V4: on the newest twin-depot run that has a state history, every car-hour is accounted for once
  SELECT r.sim_run_id INTO v_run
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND EXISTS (SELECT 1 FROM public.ottoq_events e WHERE e.sim_run_id = r.sim_run_id AND e.event_type = 'vehicle.state_changed'
                   AND e.payload -> 'diff' ? 'current_state')
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    v_b := public.ottoq_twin_kpi_board(v_run);
    IF (v_b ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION '0609 V4: the board did not answer for run %: %', v_run, v_b; END IF;
    SELECT sum(value::numeric) INTO v_split FROM jsonb_each_text(v_b -> 'split_hours');
    v_fleet := (v_b ->> 'fleet_hours')::numeric;
    IF abs(v_split - v_fleet) > greatest(0.5, 0.002 * v_fleet) THEN
      RAISE EXCEPTION '0609 V4: fleet time does not add up on run %: split % vs fleet %', v_run, v_split, v_fleet;
    END IF;
    IF (v_b -> 'uptime' ->> 'pct')::numeric NOT BETWEEN 0 AND 100 THEN
      RAISE EXCEPTION '0609 V4: uptime out of range on run %: %', v_run, v_b -> 'uptime';
    END IF;
  END IF;
END $verify$;

-- Rollback: DROP FUNCTION public.ottoq_twin_kpi_board(uuid); DELETE FROM public.ottoq_cert_lineage WHERE
-- name = '0609_the_kpi_tab_reads_uptime_turnaround_service_and_energy'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0609_the_kpi_tab_reads_uptime_turnaround_service_and_energy', false, false,
  'A read-only, run-scoped aggregate function for the twin''s KPI tab (uptime, turnaround, service, energy, chargers) and its GRANT to anon. Nothing on the tick path calls it (V3); a privilege bit is invisible to every certification atom and dial arm.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
