-- migration-version: 20261007031040
-- migration-name:    the_kpi_board_prices_the_demand_charge
--
-- 0611  **The KPI board prices the demand charge.** The board's energy cost was the energy charge alone: $229.92 on
--       run fd6ed035 (3,198 kWh at $0.0719). The twin depot's own tariff, NES GSA-3, in public.ottoq_depot_tariffs
--       since 2026-07-09 from the NES rate PDF, also bills every kW of the month's highest 30 minutes of grid draw:
--       $20.34 a kW in October. On fd6ed035 that is $12,989 a month at 638.6 kW, 56 times the run's energy bill. A
--       depot owner reads money first, and the board left out the larger part. Section 6b adds the 30-minute peak, the
--       minute it starts, the same peak with the battery taken out, both monthly charges and the tariff row used.
--
--   MEASURED BEFORE THIS FILE, fd6ed035 (1,578 readings, sim 13:00..18:50 UTC): full-window 30-minute grid peak
--   638.6 kW; without the battery 715.9 kW, so the battery is worth 77.3 kW, $1,572 a month. Grid import equals
--   max(load - solar - battery, 0) on every reading to within 0.10 kW, so taking the battery output out is exact on
--   these readings; what it cannot say is how OTTO-Q would have charged without a battery (charging is held as it was).
--
--   WHY NOT CALL ottoq_arm_peak_profile, THE SWEEP SCORER (0577/0439), which already prices this peak: it averages the
--   run's last windows over fewer than 30 minutes, and on fd6ed035 a final 19.6-minute window sets its peak (654.1 kW,
--   $315 a month above the full-window figure). An absolute figure on a board must not carry that. The board counts
--   full windows only. The scorer is NOT changed here: it is the research wing's instrument, both arms of its pairs
--   end on the same tick, and changing it would move its recorded results. The difference is named in the board's
--   basis, and V3 checks the board never reads above it.
--
--   Everything else in the function is byte-for-byte 0610's (V2 compares the whole board before and after, inside
--   this transaction). CREATE OR REPLACE keeps the owner and the grants; the write-free gate runs on the new source.
--   forces_recert FALSE, forces_dial_restart FALSE: a read nothing on the tick path calls.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0611 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0610 applied and the live board is 0610's; the tariff table has what 6b reads; this file not applied ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0610_the_kpi_boards_turnaround_in_one_pass') THEN
    RAISE EXCEPTION '0611 P1: 0610 is not applied; apply it first';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'public.ottoq_twin_kpi_board(uuid)'::regprocedure)
     IS DISTINCT FROM 'e73f79ff2428e0c0e237fb7d019c7195' THEN
    RAISE EXCEPTION '0611 P1: the live KPI board is not 0610''s source (md5 e73f79ff); someone changed it since. Read it before replacing it';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_depot_tariffs'
        AND column_name IN ('schedule_code', 'utility', 'season', 'season_months', 'demand_first_block_usd_kw',
                            'demand_excess_usd_kw', 'block_kw', 'demand_basis', 'effective_from', 'provenance', 'active')) <> 11 THEN
    RAISE EXCEPTION '0611 P1: public.ottoq_depot_tariffs lacks a column section 6b reads';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0611_the_kpi_board_prices_the_demand_charge') THEN
    RAISE EXCEPTION '0611 P1: already applied';
  END IF;
END $premises$;

-- ── snapshot before the replace ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0611_pre', 'function', 'public', 'ottoq_twin_kpi_board',
       pg_get_functiondef('public.ottoq_twin_kpi_board(uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_twin_kpi_board(uuid)'::regprocedure));

-- ── what 0610 returns on the newest completed twin-depot run with a state history, kept for V2 and V3 ──
CREATE TEMP TABLE _0611_before ON COMMIT DROP AS
SELECT r.sim_run_id, r.depot_id, public.ottoq_twin_kpi_board(r.sim_run_id) AS board
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed'
   AND EXISTS (SELECT 1 FROM public.ottoq_events e WHERE e.sim_run_id = r.sim_run_id AND e.event_type = 'vehicle.state_changed'
                 AND e.payload -> 'diff' ? 'current_state')
 ORDER BY r.started_at DESC
 LIMIT 1;

CREATE OR REPLACE FUNCTION public.ottoq_twin_kpi_board(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0609, turnaround in one pass since 0610, the demand charge since 0611. The KPI tab's board for one run: fleet uptime and where fleet time went,
   turnaround, flow, battery at dispatch, service steps, energy and cost, charger use, on-time readiness and the wait for
   a charger. Every figure from this run's own rows inside its window. Read-only (asserted before the grant). */
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
  v_tar_code text;
  v_tar_util text;
  v_tar_seas text;
  v_tar_basis text;
  v_tar_block numeric;
  v_tar_r1   numeric;
  v_tar_r2   numeric;
  v_tar_src  text;
  v_g30      numeric;
  v_nl30     numeric;
  v_g30_at   timestamptz;
  v_priced   boolean;
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
  -- 0610: one pass. Each event takes the number of the arrival it follows (a running count per car), so a visit is
  -- every event from its arrival to the next one, and its moments are min(at) per kind inside that group. 0609 found
  -- the same moments with three correlated subqueries per arrival, which cost about 2.7 s on a 24-sim-hour run.
  WITH ev AS (
    SELECT e.entity_id AS vid, e.sim_clock_at AS at, e.event_seq AS seq,
           e.payload -> 'diff' -> 'current_state' ->> 'from' AS fs,
           e.payload -> 'diff' -> 'current_state' ->> 'to'   AS ts
      FROM public.ottoq_events e
     WHERE e.sim_run_id = p_sim_run_id AND e.event_type = 'vehicle.state_changed'
       AND e.payload -> 'diff' ? 'current_state' AND e.sim_clock_at IS NOT NULL),
  k AS (
    SELECT ev.*,
           (ev.ts = 'arrived_at_gate' AND ev.fs IN ('en_route_to_depot', 'deployed') AND ev.at > r.t0) AS is_arr
      FROM ev),
  n AS (
    SELECT k.*, sum(CASE WHEN k.is_arr THEN 1 ELSE 0 END)
                  OVER (PARTITION BY k.vid ORDER BY k.at, k.seq ROWS UNBOUNDED PRECEDING) AS visit_no
      FROM k),
  v AS (
    SELECT vid, visit_no,
           min(at) FILTER (WHERE is_arr) AS arrived,
           min(at) FILTER (WHERE ts = 'staged_for_departure' AND NOT is_arr) AS ready_at,
           min(at) FILTER (WHERE ts IN ('deployed', 'en_route_to_deployment')) AS left_at,
           min(at) FILTER (WHERE ts IN ('charging_dcfc', 'charging_l2', 'in_wash_bay', 'in_detail_bay', 'in_service_bay')) AS first_service
      FROM n
     WHERE visit_no > 0
     GROUP BY vid, visit_no)
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

  -- ── 6b. DEMAND CHARGE (0611): the depot's tariff, priced on its own basis ────────────────────────────────────────
  -- The twin depot's tariff (NES GSA-3) bills the highest 30 consecutive minutes of grid draw in the month. Only windows
  -- with 30 full minutes of readings count, so the run's last, shorter window cannot set the peak. Without the battery:
  -- the same readings with its output taken out, charging held as it was.
  SELECT t.schedule_code, t.utility, t.season, t.demand_basis, t.block_kw,
         t.demand_first_block_usd_kw, COALESCE(t.demand_excess_usd_kw, t.demand_first_block_usd_kw),
         t.provenance ->> 'source_url'
    INTO v_tar_code, v_tar_util, v_tar_seas, v_tar_basis, v_tar_block, v_tar_r1, v_tar_r2, v_tar_src
    FROM public.ottoq_depot_tariffs t
   WHERE t.depot_id = r.depot_id AND t.active
     AND EXTRACT(MONTH FROM (r.t0 AT TIME ZONE 'America/Chicago'))::int = ANY (t.season_months)
   ORDER BY t.effective_from DESC
   LIMIT 1;
  WITH s AS (
    SELECT x."timestamp" AS t,
           GREATEST(COALESCE(x.grid_import_kw, 0), 0) AS g,
           GREATEST(COALESCE(x.total_ev_charging_kw, 0) + COALESCE(x.building_load_kw, 0) + COALESCE(x.lighting_load_kw, 0)
                    - COALESCE(x.solar_generation_kw, 0), 0) AS nl
      FROM public.site_energy_snapshots x
     WHERE x.sim_run_id = p_sim_run_id AND x.depot_id = r.depot_id
       AND x."timestamp" >= r.t0 AND x."timestamp" <= r.t1),
  w AS (
    SELECT s.t, max(s.t) OVER () AS t_last,
           avg(s.g)  OVER (ORDER BY s.t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30,
           avg(s.nl) OVER (ORDER BY s.t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS nl30
      FROM s)
  SELECT max(w.g30), max(w.nl30), (array_agg(w.t ORDER BY w.g30 DESC, w.t))[1]
    INTO v_g30, v_nl30, v_g30_at
    FROM w
   WHERE w.t <= w.t_last - interval '30 minutes';
  v_priced := v_tar_r1 IS NOT NULL AND v_tar_basis IS NOT DISTINCT FROM 'NCP_30min';
  v_energy := v_energy || jsonb_build_object(
    'peak_grid_kw_30min',                      round(v_g30, 1),
    'peak_grid_30min_from',                    v_g30_at,
    'peak_without_battery_kw_30min',           round(v_nl30, 1),
    'demand_charge_usd_month',                 CASE WHEN v_priced AND v_g30 IS NOT NULL THEN round(
                                                 v_tar_r1 * LEAST(v_g30, COALESCE(v_tar_block, v_g30))
                                                 + v_tar_r2 * GREATEST(0, v_g30 - COALESCE(v_tar_block, v_g30)), 2) END,
    'demand_charge_without_battery_usd_month', CASE WHEN v_priced AND v_nl30 IS NOT NULL THEN round(
                                                 v_tar_r1 * LEAST(v_nl30, COALESCE(v_tar_block, v_nl30))
                                                 + v_tar_r2 * GREATEST(0, v_nl30 - COALESCE(v_tar_block, v_nl30)), 2) END,
    'demand_tariff',                           CASE WHEN v_tar_r1 IS NOT NULL THEN jsonb_build_object(
                                                 'schedule', v_tar_code, 'utility', v_tar_util, 'season', v_tar_seas,
                                                 'basis', v_tar_basis, 'usd_per_kw', v_tar_r1, 'block_kw', v_tar_block,
                                                 'usd_per_kw_above_block', v_tar_r2, 'source_url', v_tar_src,
                                                 'priced', v_priced) END);

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
       'demand',      'public.ottoq_depot_tariffs for the month the run starts in (CT), priced on its own basis. NES GSA-3: the highest 30 consecutive minutes of grid import (non-coincident), block_kw at usd_per_kw and the rest at usd_per_kw_above_block. Only windows with 30 full minutes of readings count. The bill takes the month''s highest window, so this is the charge if this run''s peak is the month''s. Without the battery: the same readings with the battery output taken out, charging held as it was. The sweep scorer ottoq_arm_peak_profile also counts the last, shorter windows, so it can read higher.',
       'chargers',    'car-hours charging_dcfc / charging_l2 over (stalls of that type at this depot x window hours). A faulted charger still counts as a stall.'));
END

$fn$;


-- ── the safety gate (0405, 0560, 0606, 0609, 0610): the new source is write-free too ──
DO $gate$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'public.ottoq_twin_kpi_board(uuid)'::regprocedure;
  IF v_src ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\(|set_config[[:space:]]*\()' THEN
    RAISE EXCEPTION '0611: the KPI board contains a write; it must not be granted to anon';
  END IF;
END $gate$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  b       record;
  v_after jsonb;
  v_e     jsonb;
  v_new   text[] := ARRAY['peak_grid_kw_30min', 'peak_grid_30min_from', 'peak_without_battery_kw_30min',
                          'demand_charge_usd_month', 'demand_charge_without_battery_usd_month', 'demand_tariff'];
  v_n     bigint;
  v_g     numeric;
  v_nl    numeric;
  v_blk   numeric;
  v_r1    numeric;
  v_r2    numeric;
  v_sc    numeric;
BEGIN
  -- V1: the grant survived the replace
  IF NOT has_function_privilege('anon', 'public.ottoq_twin_kpi_board(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0611 V1: anon lost EXECUTE on the KPI board';
  END IF;

  SELECT * INTO b FROM _0611_before;
  IF NOT FOUND THEN
    RAISE NOTICE '0611 V2/V3: no completed twin-depot run with a state history; nothing to compare';
    RETURN;
  END IF;
  v_after := public.ottoq_twin_kpi_board(b.sim_run_id);
  v_e := v_after -> 'energy';

  -- V2: everything 0610 returned is unchanged. on_time is left out: its end-of-run battery reading is live shared state.
  IF (v_after - 'energy' - 'basis' - 'on_time') IS DISTINCT FROM (b.board - 'energy' - 'basis' - 'on_time') THEN
    RAISE EXCEPTION '0611 V2: the board changed outside energy on run %', b.sim_run_id;
  END IF;
  IF (v_e - v_new) IS DISTINCT FROM (b.board -> 'energy') THEN
    RAISE EXCEPTION '0611 V2: an energy figure 0610 returned changed on run %: before % after %', b.sim_run_id, b.board -> 'energy', v_e - v_new;
  END IF;
  IF ((v_after -> 'basis') - 'demand') IS DISTINCT FROM (b.board -> 'basis') OR NOT (v_after -> 'basis') ? 'demand' THEN
    RAISE EXCEPTION '0611 V2: the basis changed beyond the one new entry on run %', b.sim_run_id;
  END IF;
  IF NOT (v_e ?& v_new) THEN
    RAISE EXCEPTION '0611 V2: a new energy key is missing on run %: %', b.sim_run_id, v_e;
  END IF;

  -- V3: an independent derivation (one correlated average per reading, not a window frame) of both peaks and both
  -- charges, priced on the tariff row the sweep scorer's own predicate picks. Skipped above 4,000 readings (quadratic).
  SELECT count(*) INTO v_n FROM public.site_energy_snapshots s WHERE s.sim_run_id = b.sim_run_id;
  IF v_n > 4000 THEN
    RAISE NOTICE '0611 V3: % readings on run %; independent derivation skipped', v_n, b.sim_run_id;
    RETURN;
  END IF;
  WITH rr AS (
    SELECT x.depot_id, x.sim_clock_start AS t0, COALESCE(x.sim_clock_current, x.sim_clock_start) AS t1
      FROM public.ottoq_sim_runs x WHERE x.sim_run_id = b.sim_run_id),
  s AS (
    SELECT e."timestamp" AS t, GREATEST(COALESCE(e.grid_import_kw, 0), 0) AS g,
           GREATEST(COALESCE(e.total_ev_charging_kw, 0) + COALESCE(e.building_load_kw, 0) + COALESCE(e.lighting_load_kw, 0)
                    - COALESCE(e.solar_generation_kw, 0), 0) AS nl
      FROM public.site_energy_snapshots e, rr
     WHERE e.sim_run_id = b.sim_run_id AND e.depot_id = rr.depot_id AND e."timestamp" >= rr.t0 AND e."timestamp" <= rr.t1),
  m AS (SELECT max(s.t) AS tl FROM s)
  SELECT max(a.g30), max(a.nl30) INTO v_g, v_nl
    FROM (SELECT (SELECT avg(s2.g)  FROM s s2 WHERE s2.t >= s1.t AND s2.t <= s1.t + interval '29 minutes 59 seconds') AS g30,
                 (SELECT avg(s2.nl) FROM s s2 WHERE s2.t >= s1.t AND s2.t <= s1.t + interval '29 minutes 59 seconds') AS nl30
            FROM s s1, m
           WHERE s1.t <= m.tl - interval '30 minutes') a;
  SELECT t.block_kw, t.demand_first_block_usd_kw, COALESCE(t.demand_excess_usd_kw, t.demand_first_block_usd_kw)
    INTO v_blk, v_r1, v_r2
    FROM public.ottoq_depot_tariffs t, public.ottoq_sim_runs x
   WHERE x.sim_run_id = b.sim_run_id AND t.depot_id = x.depot_id AND t.active
     AND EXTRACT(MONTH FROM (x.sim_clock_start AT TIME ZONE 'America/Chicago'))::int = ANY (t.season_months)
   ORDER BY t.effective_from DESC
   LIMIT 1;
  IF (v_e ->> 'peak_grid_kw_30min')::numeric IS DISTINCT FROM round(v_g, 1)
     OR (v_e ->> 'peak_without_battery_kw_30min')::numeric IS DISTINCT FROM round(v_nl, 1)
     OR (v_e ->> 'demand_charge_usd_month')::numeric IS DISTINCT FROM
          round(v_r1 * LEAST(v_g, COALESCE(v_blk, v_g)) + v_r2 * GREATEST(0, v_g - COALESCE(v_blk, v_g)), 2)
     OR (v_e ->> 'demand_charge_without_battery_usd_month')::numeric IS DISTINCT FROM
          round(v_r1 * LEAST(v_nl, COALESCE(v_blk, v_nl)) + v_r2 * GREATEST(0, v_nl - COALESCE(v_blk, v_nl)), 2) THEN
    RAISE EXCEPTION '0611 V3: the board''s demand figures differ from an independent derivation on run %: board % derived peak % / % at %, %, %',
      b.sim_run_id, v_e, v_g, v_nl, v_r1, v_r2, v_blk;
  END IF;
  -- and the board never reads above the sweep scorer, which also counts the last, shorter windows
  v_sc := (public.ottoq_arm_peak_profile(b.sim_run_id, b.depot_id) -> 'peak_30min_kw' ->> '0')::numeric;
  IF (v_e ->> 'peak_grid_kw_30min')::numeric > v_sc + 0.05 THEN
    RAISE EXCEPTION '0611 V3: the board''s full-window peak % reads above the scorer''s % on run %', v_e ->> 'peak_grid_kw_30min', v_sc, b.sim_run_id;
  END IF;
  RAISE NOTICE '0611 V3 on run %: peak % kW (scorer %), without battery % kW, $% / $% a month',
    b.sim_run_id, v_e ->> 'peak_grid_kw_30min', v_sc, v_e ->> 'peak_without_battery_kw_30min',
    v_e ->> 'demand_charge_usd_month', v_e ->> 'demand_charge_without_battery_usd_month';
END $verify$;

-- Rollback: re-apply 0610's CREATE OR REPLACE FUNCTION block (or the '0611_pre' row in public.ottoq_schema_snapshots);
-- DELETE FROM public.ottoq_cert_lineage WHERE name = '0611_the_kpi_board_prices_the_demand_charge'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0611_the_kpi_board_prices_the_demand_charge', false, false,
  'The KPI board adds the monthly demand charge on the depot tariff''s own basis (NES GSA-3: highest full 30-minute grid draw), the same peak without the battery, and the tariff row used. Everything 0610 returned is unchanged (V2). A read nothing on the tick path calls.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
