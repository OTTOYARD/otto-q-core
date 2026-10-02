-- migration-version: 20261002195422
-- migration-name:    the_value_tab_names_the_test_a_charger_claim_failed
--
-- 0581  **When the Value tab withholds the charger claim, it says which test failed, in that test's numbers.** Read-only.
--       (G306)
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0576's capital lens claims chargers avoided only if OTTO-Q with the fewer fast chargers did at least as well as a
--   plain depot with the more on EVERY test day, on two tests: cars served and ride demand met. When the claim fails, the
--   sentence gave the cars served whichever test failed. Night 2 measured (db/checks/0414 §6):
--       "Not on every test day: with 10 fast chargers OTTO-Q served 353.0 cars a day, against 337.0 at a plain depot with 20."
--   OTTO-Q with 10 did serve more cars than the plain depot with 20. What it failed was ride demand met, 7.7% against
--   12.1%, which the sentence never named. An investor reading it would take the served count as the failure.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_value_summary` only. The comparison counts each test on its own, and the withholding sentence names each:
--       "Not on every test day. Against a plain depot with 20 fast chargers, OTTO-Q with 10 served at least as many cars
--        (353.0 a day against 337.0) but met less of the ride demand on the one test day (7.7% against 12.1%)."
--   A test that failed says on how many of the test days; one that held says so; "and" joins two failures. The sentence
--   when both hold, the claim itself, the capital figures and every other key are unchanged. The investor block gains
--   `chargers_test`, the same comparison as numbers (test days; each side's cars a day and demand met; the days each
--   test held), for a reader that wants the table rather than the sentence. The twin's Value tab reads only
--   `chargers_statement`, so it needs no change.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the function is the body 0576 wrote (md5 pinned), and this has not been applied. It goes to
--   `ottoq_schema_snapshots` as '0581_pre'.
--   V1: the function still reads every sweep the way it did: for each value sweep, every key but the investor block's
--   sentence and `chargers_test` equals what the '0581_pre' body returns (executed, both bodies, side by side). V2: on
--   the live value sweep, a withheld claim's sentence names ride demand when ride demand failed and the cars served
--   when they failed. Executed with constructed days by tests/test_throughput_sweep_sql.py.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: a read-only report of evidence. Nothing the engine reads.
--
-- ROLLBACK: re-create public.ottoq_value_summary from its '0581_pre' snapshot; DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0581_the_value_tab_names_the_test_a_charger_claim_failed'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0581 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0576's body, not yet applied ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0581_the_value_tab_names_the_test_a_charger_claim_failed') THEN
    RAISE EXCEPTION '0581 P1: already applied';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_value_summary(text)'::regprocedure)
     <> 'd5a2bc41020e901c2a56cb504e7df804' THEN
    RAISE EXCEPTION '0581 P1: ottoq_value_summary is not the body 0576 wrote';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0581_pre', 'function', 'public', 'ottoq_value_summary', d, md5(d)
  FROM (SELECT pg_get_functiondef('public.ottoq_value_summary(text)'::regprocedure) AS d) z;

-- the body 0576 wrote, kept for V1 as a temporary function: it lives in this session's own schema and goes with it
DO $pre$
BEGIN
  EXECUTE replace(pg_get_functiondef('public.ottoq_value_summary(text)'::regprocedure),
                  'public.ottoq_value_summary(', 'pg_temp.ottoq_value_summary_0581_pre(');
  REVOKE ALL ON FUNCTION pg_temp.ottoq_value_summary_0581_pre(text) FROM PUBLIC;
END $pre$;

CREATE OR REPLACE FUNCTION public.ottoq_value_summary(p_sweep_code text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  -- 0577: the demand charge is read from this many minutes into each test day, past the opening plug-in. Night 1
  -- (db/checks/0413 §4): the opening's tail kept the next peak at the cut on 13 of 19 days at 60 minutes, 4 of 19 at 180.
  c_open_min CONSTANT int := 180;
  sw        public.ottoq_throughput_sweeps%ROWTYPE;
  v_floor   timestamptz := public.ottoq_dial_pair_floor();
  v_depot   uuid;
  v_fleet   numeric;
  v_hours   numeric;
  v_depot_j jsonb;
  v_sources jsonb;
  v_notes   jsonb := jsonb_build_array(
    'A month is 30 days like the ones measured.',
    'Each depot is billed on the cheapest Nashville Electric Service rate it qualifies for: time-of-use (TGSA-3), standard (GSA-3) or the EV rate (EVC, no demand charge).',
    'Revenue counts ride demand met only, never cars out beyond what riders asked for.',
    'The plain depot is first come, first served with no energy planning. OTTO-Q is the engine as it runs today.',
    'Only test days on the calibrated twin count (0573 charge and service times, 0574 prices).');
  v_result  jsonb;
BEGIN
  SELECT * INTO sw FROM public.ottoq_throughput_sweeps s
   WHERE (p_sweep_code IS NULL AND s.sweep_code LIKE 'value\_%') OR s.sweep_code = p_sweep_code
   ORDER BY s.created_at DESC, s.sweep_id DESC LIMIT 1;

  v_depot := COALESCE(sw.depot_id, '11111111-1111-1111-1111-111111111111'::uuid);
  v_fleet := COALESCE((SELECT f.fleet_size FROM public.ottoq_fleet_buildouts f WHERE f.fleet_code = sw.fleet_code),
                      (SELECT count(*) FROM public.vehicles v WHERE v.category = 'autonomous' AND v.home_depot_id = v_depot));
  v_depot_j := jsonb_build_object(
    'name',        COALESCE((SELECT d.name FROM public.depots d WHERE d.id = v_depot), 'Twin depot'),
    'fleet',       v_fleet,
    'battery_kwh', COALESCE((SELECT sum(b.capacity_kwh) FROM public.ottoq_bess_units b WHERE b.depot_id = v_depot), 0),
    'battery_kw',  COALESCE((SELECT sum(b.max_discharge_kw) FROM public.ottoq_bess_units b WHERE b.depot_id = v_depot), 0),
    'solar_kw',    COALESCE((SELECT sum(c.nameplate_ac_kw) FROM public.ottoq_canopy_state c WHERE c.depot_id = v_depot), 0),
    'tariff',      'Nashville Electric Service, time-of-use (TGSA-3) plus the TVA fuel adjustment');
  v_sources := COALESCE((
    SELECT jsonb_agg(jsonb_build_object('what', x.what, 'value', x.value, 'url', x.url, 'as_of', x.as_of) ORDER BY x.k)
      FROM (SELECT 1 AS k, r.label AS what,
                   CASE WHEN r.energy_cents_kwh IS NULL THEN 'hourly, see 0574' ELSE (r.energy_cents_kwh + r.fuel_adj_cents_kwh)::text || ' c/kWh' END
                     || CASE WHEN r.demand_charged THEN ' + demand charge' ELSE ', no demand charge' END AS value,
                   r.sources -> 0 ->> 'url' AS url, r.sources -> 0 ->> 'retrieved' AS as_of
              FROM public.ottoq_energy_rates r
            UNION ALL
            SELECT 2, p.price_code, format('%s / %s / %s %s', p.low, p.point, p.high, p.unit),
                   p.sources -> 0 ->> 'url', COALESCE(p.sources -> 0 ->> 'date', p.sources -> 0 ->> 'retrieved')
              FROM public.ottoq_margin_prices p
            UNION ALL
            SELECT 3, 'Charge and service times', 'calibrated to public data (0573)',
                   'docs/research/direct/2026-09-30-lane-a-service-time-calibration.md', '2026-09-30') x), '[]'::jsonb);

  IF sw.sweep_id IS NULL THEN
    RETURN jsonb_build_object('status', 'none', 'sweep', NULL, 'depot', v_depot_j, 'views', '[]'::jsonb,
                              'investor', NULL, 'guarantee', NULL, 'runs', '[]'::jsonb, 'sources', v_sources,
                              'notes', v_notes || jsonb_build_array('No value sweep is defined yet.'));
  END IF;
  v_hours := sw.ticks * sw.sim_min_per_tick / 60.0;
  IF v_hours < 23.9 OR v_hours > 24.1 THEN
    RETURN jsonb_build_object('status', 'none', 'sweep', NULL, 'depot', v_depot_j, 'views', '[]'::jsonb,
                              'investor', NULL, 'guarantee', NULL, 'runs', '[]'::jsonb, 'sources', v_sources,
                              'notes', v_notes || jsonb_build_array(format('%s runs %s-hour days; the Value tab reads 24-hour days only.',
                                                                           sw.sweep_code, round(v_hours, 1))));
  END IF;

  WITH rates AS (
    SELECT max(r.fixed_usd_month) FILTER (WHERE r.rate_code = 'nes_tgsa3')                          AS tgsa_fixed,
           max(r.fixed_usd_month) FILTER (WHERE r.rate_code = 'nes_gsa3')                           AS gsa_fixed,
           max(r.energy_cents_kwh + r.fuel_adj_cents_kwh) FILTER (WHERE r.rate_code = 'nes_gsa3')   AS gsa_c,
           max(r.fixed_usd_month) FILTER (WHERE r.rate_code = 'nes_evc')                            AS evc_fixed,
           max(r.energy_cents_kwh + r.fuel_adj_cents_kwh) FILTER (WHERE r.rate_code = 'nes_evc')    AS evc_c
      FROM public.ottoq_energy_rates r
  ), px AS (
    SELECT max(p.low)   FILTER (WHERE p.price_code = 'revenue_per_deployed_car_hour') AS rev_lo,
           max(p.point) FILTER (WHERE p.price_code = 'revenue_per_deployed_car_hour') AS rev_pt,
           max(p.high)  FILTER (WHERE p.price_code = 'revenue_per_deployed_car_hour') AS rev_hi,
           max(p.low)   FILTER (WHERE p.price_code = 'vehicle_capex')                 AS car_lo,
           max(p.point) FILTER (WHERE p.price_code = 'vehicle_capex')                 AS car_pt,
           max(p.high)  FILTER (WHERE p.price_code = 'vehicle_capex')                 AS car_hi,
           max(p.low)   FILTER (WHERE p.price_code = 'dcfc_350kw_installed')          AS dc_lo,
           max(p.point) FILTER (WHERE p.price_code = 'dcfc_350kw_installed')          AS dc_pt,
           max(p.high)  FILTER (WHERE p.price_code = 'dcfc_350kw_installed')          AS dc_hi
      FROM public.ottoq_margin_prices p
  ), arm AS (
    SELECT a.arm_id, a.seed, a.sim_run_id, a.ran_at, c.cell_code, c.seat,
           COALESCE((c.fixed_params ->> 'energy_orchestration_enabled')::numeric, 1) AS planner,
           a.scorecard AS sc, a.arm_metrics AS am
      FROM public.ottoq_throughput_sweep_arms a
      JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
     WHERE a.sweep_id = sw.sweep_id AND NOT a.replicate AND a.complete AND a.paid_shield AND a.ran_at >= v_floor
       AND c.seat IN ('otto_q', 'fifo')
  ), opn AS (   -- 0577: bill the peak after the opening only when every arm carries it
    -- bool_and skips NULLs, so a missing key must read as false, not as nothing
    SELECT COALESCE(bool_and(COALESCE(jsonb_typeof(arm.am #> ARRAY['peak_after_open', 'peak_30min_kw', c_open_min::text]) = 'number'
                                      AND jsonb_typeof(arm.am #> ARRAY['peak_after_open', 'demand_charge_usd_month', c_open_min::text]) = 'number',
                                      false)),
                    false) AS ok
      FROM arm
  ), m AS (
    SELECT arm.*,
           CASE WHEN seat = 'otto_q' AND planner >= 1 THEN 'otto_q'
                WHEN seat = 'fifo'   AND planner <  1 THEN 'plain'
                WHEN seat = 'otto_q' THEN 'otto_q_planner_off'
                ELSE 'fifo_planner_on' END                                                  AS role,
           (sc #>> '{fast_chargers,at_depot}')::numeric                                     AS chargers,
           (am ->> 'grid_import_kwh')::numeric                                              AS kwh_day,
           COALESCE((am ->> 'terminal_soc_usd')::numeric, 0)
             + COALESCE((am ->> 'bess_degradation_usd')::numeric, 0)                        AS batt_day,
           (am ->> 'energy_cost_usd')::numeric                                              AS tou_day,
           CASE WHEN opn.ok THEN (am #>> ARRAY['peak_after_open', 'demand_charge_usd_month', c_open_min::text])::numeric
                ELSE (am ->> 'demand_charge_usd_month')::numeric END                        AS demand_month,
           CASE WHEN opn.ok THEN (am #>> ARRAY['peak_after_open', 'peak_30min_kw', c_open_min::text])::numeric
                ELSE (am ->> 'peak_30min_kw')::numeric END                                  AS peak_kw,
           (am ->> 'peak_30min_kw')::numeric                                                AS peak_full,
           (sc #>> '{throughput,visits_served}')::numeric                                   AS served,
           (sc #>> '{timeliness,door_p50_min}')::numeric                                    AS door_p50,
           (sc #>> '{fast_chargers,busy_pct}')::numeric                                     AS busy,
           (am ->> 'demand_car_hours')::numeric                                             AS dem_h,
           (am ->> 'unmet_demand_car_hours')::numeric                                       AS unmet_h,
           (am ->> 'charge_wait_p50_min')::numeric                                          AS wait_p50,
           COALESCE((sc #>> '{rule9,departures}')::int, 0)                                  AS departures,
           GREATEST(0, COALESCE((sc #>> '{rule9,departures}')::int, 0)
                       - COALESCE((sc #>> '{rule9,left_below_target}')::int, 0)
                       - COALESCE((sc #>> '{rule9,left_with_needed_work_open}')::int, 0))  AS full_ok
      FROM arm, opn
  ), b AS (
    SELECT m.*,
           30 * (m.tou_day + m.batt_day) + m.demand_month + r.tgsa_fixed                    AS bill_tgsa,
           30 * (m.kwh_day * r.gsa_c / 100 + m.batt_day) + m.demand_month + r.gsa_fixed     AS bill_gsa,
           30 * (m.kwh_day * r.evc_c / 100 + m.batt_day) + r.evc_fixed                      AS bill_evc
      FROM m, rates r
  ), bb AS (
    SELECT b.*,
           LEAST(bill_tgsa, bill_gsa, bill_evc)                                             AS bill,
           CASE WHEN bill_tgsa <= LEAST(bill_gsa, bill_evc) THEN 'TGSA-3'
                WHEN bill_gsa <= bill_evc THEN 'GSA-3' ELSE 'EVC' END                       AS rate,
           CASE WHEN bill_evc < LEAST(bill_tgsa, bill_gsa) THEN 0 ELSE demand_month END     AS demand_paid,
           100 * LEAST(bill_tgsa, bill_gsa, bill_evc) / NULLIF(30 * kwh_day, 0)             AS cents_kwh,
           100 * (dem_h - unmet_h) / NULLIF(dem_h, 0)                                       AS met_pct,
           (dem_h - unmet_h) / NULLIF(v_fleet, 0)                                           AS met_h_per_car
      FROM b
  ), blocks AS (
    SELECT chargers, role, jsonb_build_object(
             'cell', min(cell_code), 'seeds', count(*),
             'power_bill_usd_month', round(avg(bill)),
             'power_rate', mode() WITHIN GROUP (ORDER BY rate),
             'effective_cents_per_kwh', round(avg(cents_kwh), 1),
             'peak_kw', round(avg(peak_kw)),
             'peak_kw_incl_opening', round(avg(peak_full)),
             'demand_charge_usd_month', round(avg(demand_paid)),
             'kwh_bought_day', round(avg(kwh_day)),
             'cars_served_day', round(avg(served), 1),
             'cars_per_fast_charger_day', round(avg(served / NULLIF(chargers, 0)), 1),
             'turnaround_p50_min', round(avg(door_p50)),
             'fast_charger_busy_pct', round(avg(busy), 1),
             'demand_met_pct', round(avg(met_pct), 1),
             'revenue_hours_per_car_day', round(avg(met_h_per_car), 2),
             'charge_wait_p50_min', round(avg(wait_p50)),
             'departures', sum(departures),
             'departures_full_and_serviced', sum(full_ok)) AS blk
      FROM bb GROUP BY chargers, role
  ), pair AS (
    SELECT q.chargers, q.seed,
           p.bill - q.bill                                    AS saved,
           100 * (p.bill - q.bill) / NULLIF(p.bill, 0)        AS saved_pct,
           p.peak_kw - q.peak_kw                              AS peak_cut,
           q.served - p.served                                AS served_d,
           q.door_p50 - p.door_p50                            AS door_d,
           q.met_h_per_car - p.met_h_per_car                  AS met_h_d
      FROM bb q JOIN bb p ON p.chargers = q.chargers AND p.seed = q.seed AND p.role = 'plain'
     WHERE q.role = 'otto_q'
  ), vs AS (
    SELECT pr.chargers, count(*) AS n, jsonb_build_object(
             'power_bill_saved_usd_month',      public.ottoq_value_range(array_agg(pr.saved), 0),
             'power_bill_saved_pct',            public.ottoq_value_range(array_agg(pr.saved_pct), 1),
             'peak_cut_kw',                     public.ottoq_value_range(array_agg(pr.peak_cut), 0),
             'cars_served_delta_day',           public.ottoq_value_range(array_agg(pr.served_d), 1),
             'turnaround_delta_min',            public.ottoq_value_range(array_agg(pr.door_d), 0),
             'revenue_hours_per_car_day_delta', public.ottoq_value_range(array_agg(pr.met_h_d), 2),
             'revenue_usd_per_car_day',         public.ottoq_value_range(array_agg(pr.met_h_d * x.rev_pt), 2),
             'revenue_usd_per_car_day_band',    jsonb_build_array(round(avg(pr.met_h_d) * x.rev_lo, 2),
                                                                  round(avg(pr.met_h_d) * x.rev_hi, 2))) AS v
      FROM pair pr, px x GROUP BY pr.chargers, x.rev_lo, x.rev_pt, x.rev_hi
  ), sp AS (
    SELECT q.chargers,
           round(avg(o.bill - q.bill) FILTER (WHERE o.role = 'otto_q_planner_off')) AS energy_planning,
           round(avg(o.bill - q.bill) FILTER (WHERE o.role = 'fifo_planner_on'))    AS charger_assignment
      FROM bb q JOIN bb o ON o.chargers = q.chargers AND o.seed = q.seed AND o.role IN ('otto_q_planner_off', 'fifo_planner_on')
     WHERE q.role = 'otto_q'
     GROUP BY q.chargers
  ), ch AS (
    SELECT DISTINCT chargers FROM bb WHERE chargers IS NOT NULL
  ), views AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'fast_chargers',      ch.chargers,
             'otto_q',             (SELECT blk FROM blocks WHERE blocks.chargers = ch.chargers AND role = 'otto_q'),
             'plain',              (SELECT blk FROM blocks WHERE blocks.chargers = ch.chargers AND role = 'plain'),
             'otto_q_planner_off', (SELECT blk FROM blocks WHERE blocks.chargers = ch.chargers AND role = 'otto_q_planner_off'),
             'fifo_planner_on',    (SELECT blk FROM blocks WHERE blocks.chargers = ch.chargers AND role = 'fifo_planner_on'),
             'vs_plain',           (SELECT v FROM vs WHERE vs.chargers = ch.chargers),
             'split',              (SELECT CASE WHEN sp.energy_planning IS NULL AND sp.charger_assignment IS NULL THEN NULL
                                                ELSE jsonb_build_object('energy_planning_usd_month', sp.energy_planning,
                                                                        'charger_assignment_usd_month', sp.charger_assignment) END
                                      FROM sp WHERE sp.chargers = ch.chargers)) ORDER BY ch.chargers), '[]'::jsonb) AS j
      FROM ch
  ), lohi AS (
    SELECT min(chargers) AS lo, max(chargers) AS hi FROM ch
  ), cmp AS (   -- OTTO-Q with the fewer chargers against the plain depot with the more, seed by seed
    SELECT count(*) AS n,
           bool_and(q.served >= p.served AND q.met_pct >= p.met_pct) AS every_day,
           avg(q.served) AS q_served, avg(p.served) AS p_served,
           -- 0581 (G306): each condition on its own, so a sentence that withholds the claim can say which one failed
           count(*) FILTER (WHERE q.served >= p.served)   AS served_days,
           count(*) FILTER (WHERE q.met_pct >= p.met_pct) AS met_days,
           avg(q.met_pct) AS q_met, avg(p.met_pct) AS p_met
      FROM lohi, bb q JOIN bb p ON p.seed = q.seed AND p.role = 'plain'
     WHERE q.role = 'otto_q' AND q.chargers = lohi.lo AND p.chargers = lohi.hi AND lohi.hi > lohi.lo
  ), fleet_eq AS (  -- at the fewer chargers: the demand OTTO-Q met beyond the plain depot, in cars
    SELECT avg(pr.met_h_d) * v_fleet / NULLIF((SELECT avg(p.met_h_per_car) FROM bb p, lohi
                                                WHERE p.role = 'plain' AND p.chargers = lohi.lo), 0) AS cars
      FROM pair pr, lohi WHERE pr.chargers = lohi.lo
  ), investor AS (
    SELECT CASE WHEN cmp.n = 0 THEN NULL ELSE jsonb_build_object(
             'chargers_statement',
               CASE WHEN cmp.every_day
                    THEN format('On every test day, OTTO-Q with %s fast chargers served at least as many cars, and met at least as much ride demand, as a plain depot with %s.', lohi.lo, lohi.hi)
                    -- 0581 (G306): name the condition that failed, in its own numbers. It used to give the cars served
                    -- whichever failed, so a day lost on ride demand read as a day lost on cars.
                    ELSE format('Not on every test day. Against a plain depot with %s fast chargers, OTTO-Q with %s %s %s %s.',
                                lohi.hi, lohi.lo,
                                CASE WHEN cmp.served_days = cmp.n
                                     THEN format('served at least as many cars (%s a day against %s)',
                                                 round(cmp.q_served, 1), round(cmp.p_served, 1))
                                     ELSE format('served fewer cars %s (%s a day against %s)',
                                                 CASE WHEN cmp.n = 1 THEN 'on the one test day'
                                                      ELSE format('on %s of %s test days', cmp.n - cmp.served_days, cmp.n) END,
                                                 round(cmp.q_served, 1), round(cmp.p_served, 1)) END,
                                CASE WHEN cmp.served_days = cmp.n OR cmp.met_days = cmp.n THEN 'but' ELSE 'and' END,
                                CASE WHEN cmp.met_days = cmp.n
                                     THEN format('met at least as much of the ride demand (%s%% against %s%%)',
                                                 round(cmp.q_met, 1), round(cmp.p_met, 1))
                                     ELSE format('met less of the ride demand %s (%s%% against %s%%)',
                                                 CASE WHEN cmp.n = 1 THEN 'on the one test day'
                                                      ELSE format('on %s of %s test days', cmp.n - cmp.met_days, cmp.n) END,
                                                 round(cmp.q_met, 1), round(cmp.p_met, 1)) END) END,
             'chargers_test', jsonb_build_object(
               'test_days', cmp.n,
               'cars_served_per_day', jsonb_build_object('otto_q', round(cmp.q_served, 1), 'plain', round(cmp.p_served, 1),
                                                         'days_at_least_as_many', cmp.served_days),
               'ride_demand_met_pct', jsonb_build_object('otto_q', round(cmp.q_met, 1), 'plain', round(cmp.p_met, 1),
                                                         'days_at_least_as_much', cmp.met_days)),
             'chargers_avoided',          CASE WHEN cmp.every_day THEN lohi.hi - lohi.lo END,
             'charger_capex_avoided_usd', CASE WHEN cmp.every_day THEN
                                            jsonb_build_array(round((lohi.hi - lohi.lo) * x.dc_lo), round((lohi.hi - lohi.lo) * x.dc_pt),
                                                              round((lohi.hi - lohi.lo) * x.dc_hi)) END,
             'fleet_equiv_cars',          round(fe.cars, 1),
             'fleet_capex_equiv_usd',     CASE WHEN fe.cars IS NULL THEN NULL ELSE
                                            jsonb_build_array(round(LEAST(fe.cars * x.car_lo, fe.cars * x.car_hi)),
                                                              round(fe.cars * x.car_pt),
                                                              round(GREATEST(fe.cars * x.car_lo, fe.cars * x.car_hi))) END) END AS j
      FROM cmp, lohi, fleet_eq fe, px x
  )
  SELECT jsonb_build_object(
    'status', CASE WHEN EXISTS (SELECT 1 FROM vs WHERE n > 0) THEN 'measured' ELSE 'measuring' END,
    'sweep', jsonb_build_object(
      'code', sw.sweep_code, 'title', sw.title,
      'arms_planned', (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c WHERE c.sweep_id = sw.sweep_id) * cardinality(sw.seeds),
      'arms_done', (SELECT count(*) FROM arm),
      'seeds_done', (SELECT count(*) FROM (SELECT seed FROM arm GROUP BY seed
                                            HAVING count(*) = (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c
                                                                WHERE c.sweep_id = sw.sweep_id)) s),
      'day_hours', round(v_hours, 1), 'step_min', sw.sim_min_per_tick,
      'peak_read_from_min', CASE WHEN (SELECT ok FROM opn) THEN c_open_min ELSE 0 END,
      'first_arm_at', (SELECT min(ran_at) FROM arm), 'last_arm_at', (SELECT max(ran_at) FROM arm)),
    'depot', v_depot_j,
    'views', (SELECT j FROM views),
    'investor', (SELECT j FROM investor),
    'guarantee', (SELECT CASE WHEN count(*) = 0 THEN NULL ELSE
                           jsonb_build_object('departures', sum(departures), 'full_and_serviced', sum(full_ok)) END
                    FROM bb WHERE seat = 'otto_q'),
    'runs', COALESCE((SELECT jsonb_agg(jsonb_build_object('cell', cell_code, 'seed', seed::text, 'arm_id', arm_id,
                                                          'sim_run_id', sim_run_id, 'ran_at', ran_at) ORDER BY arm_id)
                        FROM arm), '[]'::jsonb),
    'sources', v_sources,
    'notes', v_notes || CASE
      WHEN NOT EXISTS (SELECT 1 FROM arm) THEN '[]'::jsonb
      WHEN (SELECT ok FROM opn) THEN jsonb_build_array(format(
        'Peak demand is read from %s into each test day. A test day starts with every car already parked at the depot plugging in at once, which a depot running around the clock never does, and it takes about three hours to clear. The full-day peak is shown beside it.',
        CASE WHEN c_open_min % 60 = 0 THEN (c_open_min / 60)::text || CASE WHEN c_open_min = 60 THEN ' hour' ELSE ' hours' END
             ELSE c_open_min::text || ' minutes' END))
      ELSE jsonb_build_array('Peak demand counts the whole test day, including its first minutes, when every car already parked at the depot plugs in at once.') END)
    INTO v_result;
  RETURN v_result;
END
$fn$;

-- ── V1: every sweep reads as it did, but for the withholding sentence and the new chargers_test ──
DO $v1$
DECLARE r record; v_new jsonb; v_old jsonb; v_ni jsonb; v_oi jsonb; n int := 0;
BEGIN
  FOR r IN SELECT NULL::text AS code UNION ALL SELECT sweep_code FROM public.ottoq_throughput_sweeps LOOP
    v_new := public.ottoq_value_summary(r.code);
    v_old := pg_temp.ottoq_value_summary_0581_pre(r.code);
    v_ni  := CASE WHEN jsonb_typeof(v_new->'investor') = 'object' THEN v_new->'investor' END;
    v_oi  := CASE WHEN jsonb_typeof(v_old->'investor') = 'object' THEN v_old->'investor' END;
    IF (v_new - 'investor') IS DISTINCT FROM (v_old - 'investor')
       OR (v_ni IS NULL) <> (v_oi IS NULL)
       OR (v_ni - 'chargers_statement' - 'chargers_test') IS DISTINCT FROM (v_oi - 'chargers_statement') THEN
      RAISE EXCEPTION '0581 V1: the summary of sweep % moved beyond the withholding sentence', COALESCE(r.code, '(default)');
    END IF;
    IF (v_ni->>'chargers_statement') LIKE 'On every test day%'
       AND (v_ni->>'chargers_statement') IS DISTINCT FROM (v_oi->>'chargers_statement') THEN
      RAISE EXCEPTION '0581 V1: the claim itself moved for sweep %', COALESCE(r.code, '(default)');
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE '0581 V1: % summaries read the same but for the withholding sentence', n;
END $v1$;

-- ── V2: on the live sweep, a withheld claim names the test that failed ──
DO $v2$
DECLARE v jsonb := public.ottoq_value_summary(NULL)->'investor'; t jsonb;
BEGIN
  IF jsonb_typeof(v) IS DISTINCT FROM 'object' OR v->>'chargers_statement' LIKE 'On every test day%' THEN
    RAISE NOTICE '0581 V2: nothing withheld to read (%)', COALESCE(v->>'chargers_statement', 'no comparison yet');
    RETURN;
  END IF;
  t := v->'chargers_test';
  IF (t->'ride_demand_met_pct'->>'days_at_least_as_much')::int < (t->>'test_days')::int
     AND v->>'chargers_statement' NOT LIKE '%met less of the ride demand%' THEN
    RAISE EXCEPTION '0581 V2: ride demand failed and the sentence does not say so: %', v->>'chargers_statement';
  END IF;
  IF (t->'cars_served_per_day'->>'days_at_least_as_many')::int < (t->>'test_days')::int
     AND v->>'chargers_statement' NOT LIKE '%served fewer cars%' THEN
    RAISE EXCEPTION '0581 V2: cars served failed and the sentence does not say so: %', v->>'chargers_statement';
  END IF;
  RAISE NOTICE '0581 V2: %', v->>'chargers_statement';
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0581_the_value_tab_names_the_test_a_charger_claim_failed', false, false,
  'Read-only (G306). ottoq_value_summary''s withholding sentence names the test the charger claim failed, cars served or '
  'ride demand met, in that test''s numbers; night 2''s read as a shortfall in cars when OTTO-Q with 10 fast chargers '
  'had served more than a plain depot with 20 and failed on ride demand, 7.7% against 12.1%. Adds chargers_test to the '
  'investor block. Nothing the engine reads.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
