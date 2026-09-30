-- migration-version: 20260930115650
-- migration-name:    the_value_tab_reads_what_night_two_measured
--
-- 0576  **The twin's Value tab reads what night 2 measured, and nothing else.** One read-only contract,
--       `ottoq_value_summary(sweep)`, that turns a value sweep's evidence (0575) into the few numbers a customer and an
--       investor can read. One reference table, `ottoq_energy_rates`, holds the three Nashville rates a depot could take.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-09-29, 8:20 PM CT: "Try to focus and hone in on a few industry standard metrics that are palpable and
--   understandable by customers, and investors. Make the savings easy to understand and not just technical slop/jargon
--   ... And I guess this will only need to be visible in the twin." The margin ledger (0569/0571) prices every pair and
--   contrast; this contract picks the few that answer his three priorities, in the order he gave them. It computes
--   nothing the evidence does not hold.
--
-- ══ §2 WHAT IT RETURNS ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   For each charger count in the sweep, four arm blocks, each averaged over the seeds that finished:
--     otto_q               OTTO-Q, energy planner on (the engine as it runs)
--     plain                first come, first served, planner off: a plain depot
--     otto_q_planner_off   and fifo_planner_on, the two cells between them
--   and `vs_plain`: OTTO-Q minus the plain depot, seed by seed (common random numbers), as {low, mid, high} over seeds.
--   The measures are industry standard:
--     power bill ($/month), effective rate (c/kWh), peak demand (kW, the highest 30 minutes), demand charge ($/month)
--       Each arm's bill is its day times 30, on the CHEAPEST of NES's three rates it qualifies for:
--         TGSA-3 (time-of-use): the arm's own energy cost, priced every tick by 0574's windows, + its demand charge;
--         GSA-3 (flat): the arm's kWh at 4.785 c + the fuel adjustment, + the same demand charge;
--         EVC (EV-only): the arm's kWh at 21.773 c + the fuel adjustment, and NO demand charge.
--       All three add the battery's wear and its end-of-day refill (0439's terminal term), so no arm looks cheaper by
--       ending the day with an emptier battery. A plain depot with spiky charging may well be cheapest on EVC, which
--       keeps the comparison conservative.
--     cars fully serviced per day (0565's served visits: each left at its charge target with no needed work open),
--       cars per fast charger per day, median turnaround door to door, fast-charger utilization;
--     ride demand met (%), and revenue hours per car per day: car-hours of ride demand met over the fleet. Revenue is
--       priced on demand met only, never on cars out beyond what riders asked for (0569), at 0569's $16/$20/$24.
--   `split` says where the power-bill saving comes from: the planner (OTTO-Q against OTTO-Q with it off) and the
--   charger assignment (OTTO-Q against first come, first served with it on). The two need not add to the total.
--   `investor` is the capital lens, never added to the savings: chargers avoided only if OTTO-Q with the fewer chargers
--   served at least as many cars AND met at least as much demand as the plain depot with the more, on EVERY test day
--   (otherwise the sentence says so and no dollar figure is given), and the fleet equivalent of the demand met.
--   `guarantee`: departures from OTTO-Q's arms, and how many left at target with every needed service done (rule 9).
--   `status`: 'none' (no value sweep, or its days are not 24 hours), 'measuring' (no seed has both OTTO-Q and the
--   plain depot yet), 'measured'.
--
--   Only current evidence counts: primary arms that completed, paid the shield and ran at or after the dial floor.
--   A night measured before an engine change that restarts the floor (0573, 0574) is not mixed in.
--
--   Peak demand, and so the demand charge, is read from three hours into each test day when every arm carries 0577's
--   `peak_after_open`. A test day opens with every car the seed parks at the depot plugging in at once, which a depot
--   running around the clock never does. On night 1 that opening set the day's peak on 20 of 20 arms, and its tail
--   lasted about three hours (G300, db/checks/0413 §4). Each block also keeps
--   the full-day peak (`peak_kw_incl_opening`), `sweep.peak_read_from_min` says which was billed, and the notes say it in
--   words. If any arm lacks the profile, every arm is billed on its full-day peak: one basis per answer, never a mix.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: 0569's prices, 0568's sweep tables and 0572's fleet column exist. P2: not already applied. V1: the rates give the
--   documented all-in prices (TGSA-3 energy lives in 0574's windows; GSA-3 7.300 c; EVC 24.288 c). V2: the contract
--   answers on the live database with a well-formed object. The arithmetic is executed in
--   tests/test_throughput_sweep_sql.py on the stub engine's arms.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: a table no engine path reads and a read-only function.
--
-- ROLLBACK: DROP FUNCTION public.ottoq_value_summary(text); DROP FUNCTION public.ottoq_value_range(numeric[], integer);
--   DROP TABLE public.ottoq_energy_rates;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0576_the_value_tab_reads_what_night_two_measured'.

BEGIN;

-- ── P1: what it reads ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_throughput_sweep_arms') IS NULL OR to_regclass('public.ottoq_margin_prices') IS NULL THEN
    RAISE EXCEPTION '0576 P1: 0568''s sweep or 0569''s prices are missing';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_margin_prices
       WHERE price_code IN ('revenue_per_deployed_car_hour', 'vehicle_capex', 'dcfc_350kw_installed')) <> 3 THEN
    RAISE EXCEPTION '0576 P1: 0569''s three prices are not all present';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                  AND table_name = 'ottoq_throughput_sweeps' AND column_name = 'fleet_code') THEN
    RAISE EXCEPTION '0576 P1: 0572''s fleet_code is missing; apply 0572 first';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF to_regclass('public.ottoq_energy_rates') IS NOT NULL OR to_regproc('public.ottoq_value_summary') IS NOT NULL THEN
    RAISE EXCEPTION '0576 P2: already applied';
  END IF;
END $once$;

CREATE TABLE public.ottoq_energy_rates (
  rate_code          text PRIMARY KEY CHECK (rate_code ~ '^[a-z0-9_]+$'),
  label              text NOT NULL,
  energy_cents_kwh   numeric CHECK (energy_cents_kwh >= 0),   -- NULL: priced hour by hour in ottoq_tariff_windows
  fuel_adj_cents_kwh numeric NOT NULL CHECK (fuel_adj_cents_kwh >= 0),
  demand_charged     boolean NOT NULL,
  fixed_usd_month    numeric NOT NULL CHECK (fixed_usd_month >= 0),
  sources            jsonb NOT NULL CHECK (jsonb_typeof(sources) = 'array' AND jsonb_array_length(sources) > 0),
  notes              text NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ottoq_energy_rates ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_energy_rates_read ON public.ottoq_energy_rates FOR SELECT TO authenticated, service_role USING (true);
REVOKE ALL ON public.ottoq_energy_rates FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_energy_rates TO authenticated, service_role;
COMMENT ON TABLE public.ottoq_energy_rates IS
'0576. The three Nashville Electric Service rates a depot of the twin''s size could take, each with its source: the Value tab bills every test day on the cheapest. Recorded from docs/research/direct/2026-09-30-lane-a-energy-price.md.';

INSERT INTO public.ottoq_energy_rates (rate_code, label, energy_cents_kwh, fuel_adj_cents_kwh, demand_charged, fixed_usd_month, sources, notes) VALUES
('nes_tgsa3', 'TGSA-3 (time-of-use)', NULL, 2.515, true, 1571.37,
 '[{"title": "NES Schedule TGSA, effective October 2024", "url": "https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/tgsa.pdf", "retrieved": "2026-09-30"},
   {"title": "NES rates page: fuel cost adjustment, September", "url": "https://www.nespower.com/rates/", "retrieved": "2026-09-30"}]',
 'Energy priced hour by hour by ottoq_tariff_windows (0574: summer 5.667 c on-peak 1-7 PM, 4.209 c off-peak; winter 5.204 / 4.539 c; transition 4.672 c; each + 2.515 c). Demand as GSA-3 (ottoq_depot_tariffs). Fixed: service charge $934.50 + TVA grid access $636.87 (over 150,000 kWh a month).'),
('nes_gsa3', 'GSA-3 (standard)', 4.785, 2.515, true, 2091.71,
 '[{"title": "NES Schedule GSA, Part 3, effective October 2024", "url": "https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/gsa-123.pdf", "retrieved": "2026-07-09"}]',
 'Flat energy. Demand $21.40/kW first 1,000 kW and $21.78 above (summer), $20.34 / $20.73 otherwise, on the highest 30 minutes of the month (ottoq_depot_tariffs). Fixed as recorded there.'),
('nes_evc', 'EVC (EV charging, no demand charge)', 21.773, 2.515, false, 100,
 '[{"title": "NES Schedule EVC, effective October 2024", "url": "https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/evc.pdf", "retrieved": "2026-09-30"}]',
 'Separately metered EV charging, 50-5,000 kW. The same price every hour, no demand charge; customer charge $100 a month.');

-- {low, mid, high} over the seeds: min, mean, max; NULL when there is nothing to range over
CREATE FUNCTION public.ottoq_value_range(p numeric[], p_digits integer DEFAULT 1)
 RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN count(x) = 0 THEN NULL ELSE
           jsonb_build_object('low', round(min(x), p_digits), 'mid', round(avg(x), p_digits), 'high', round(max(x), p_digits)) END
    FROM unnest(p) AS u(x)
$$;
REVOKE ALL ON FUNCTION public.ottoq_value_range(numeric[], integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_value_range(numeric[], integer) TO anon, authenticated, service_role;

CREATE FUNCTION public.ottoq_value_summary(p_sweep_code text DEFAULT NULL)
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
           avg(q.served) AS q_served, avg(p.served) AS p_served
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
                    ELSE format('Not on every test day: with %s fast chargers OTTO-Q served %s cars a day, against %s at a plain depot with %s.',
                                lohi.lo, round(cmp.q_served, 1), round(cmp.p_served, 1), lohi.hi) END,
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

COMMENT ON FUNCTION public.ottoq_value_summary(text) IS
'0576. The twin''s Value tab: a value sweep''s current evidence (0575) as the few numbers a customer and an investor can read. OTTO-Q against a plain depot (first come, first served, no energy planning), per charger count, seed by seed. Power bill on each arm''s cheapest NES rate (ottoq_energy_rates), revenue on demand met at 0569''s prices, capital only as a separate lens. Read-only.';
REVOKE ALL ON FUNCTION public.ottoq_value_summary(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_value_summary(text) TO anon, authenticated, service_role;

-- ── V1: the rates give the documented all-in prices ──
DO $v1$
BEGIN
  IF (SELECT energy_cents_kwh + fuel_adj_cents_kwh FROM public.ottoq_energy_rates WHERE rate_code = 'nes_gsa3') <> 7.300
     OR (SELECT energy_cents_kwh + fuel_adj_cents_kwh FROM public.ottoq_energy_rates WHERE rate_code = 'nes_evc') <> 24.288
     OR (SELECT demand_charged FROM public.ottoq_energy_rates WHERE rate_code = 'nes_evc')
     OR (SELECT energy_cents_kwh FROM public.ottoq_energy_rates WHERE rate_code = 'nes_tgsa3') IS NOT NULL THEN
    RAISE EXCEPTION '0576 V1: the rates are not the documented ones';
  END IF;
END $v1$;

-- ── V2: the contract answers with a well-formed object ──
DO $v2$
DECLARE j jsonb := public.ottoq_value_summary(NULL);
BEGIN
  IF j ->> 'status' NOT IN ('none', 'measuring', 'measured')
     OR jsonb_typeof(j -> 'views') <> 'array' OR jsonb_typeof(j -> 'sources') <> 'array'
     OR (j #>> '{depot,fleet}') IS NULL OR jsonb_array_length(j -> 'sources') < 7 THEN
    RAISE EXCEPTION '0576 V2: the contract answered %', left(j::text, 400);
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0576_the_value_tab_reads_what_night_two_measured', false, false,
  'A reference table of the three NES rates (ottoq_energy_rates) and read-only functions for the twin''s Value tab '
  '(ottoq_value_summary, ottoq_value_range). No engine path, sweep, recertification runner or determinism pair reads them.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
