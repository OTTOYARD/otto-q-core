-- migration-version: PENDING
-- migration-name:    a_margin_ledger_prices_what_the_twin_measured
--
-- 0569  **A margin ledger that prices what the twin measured, and nothing it did not.** Lane A, phase 3 (its database
--       half). Chase, 2026-09-29: "How can we show dollars saved or recouped due to better orchestration, margin gained
--       ... Not just that we can orchestrate, but HOW we save or leverage margin."
--
-- ══ §1 THE RULE ════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Every dollar is (a difference the twin measured between two runs of the same day) x (a price with a source and a
--   date). The difference comes from public.ottoq_throughput_sweep_pairs (0568): OTTO-Q minus FIFO or greedy on one seed,
--   one build-out and one set of dials, with world_identical saying whether both arms booted from one world. The price
--   comes from public.ottoq_margin_prices, which this file creates and fills from
--   docs/research/direct/2026-09-29-lane-a-margin-inputs.md. A price is a range (low, point, high), never a point alone,
--   and a customer's own number replaces it.
--
-- ══ §2 WHAT THIS BUILDS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_margin_prices    the prices, each with its basis, its sources (title, URL, date, retrieval date) and a
--                                 confidence. Three today:
--     revenue_per_deployed_car_hour  $16 / $20 / $24. Waymo's $350M annualized run rate (Bloomberg, reported December
--                                    2025) over ~2,500 vehicles is ~$384 per vehicle-day, spread over 24 (low) to 16
--                                    (high) in-service hours. Medium confidence: one operator, a second-hand run rate.
--     vehicle_capex                  $75,000 / $150,000 / $200,000 per robotaxi: converted I-PACE ~$150-200k, a purpose-
--                                    built successor ~$75-100k. Low confidence: secondary estimates.
--     dcfc_350kw_installed           $193,984 / $205,984 / $215,984 per charger: hardware $128-150k (point $140k) plus
--                                    $65,984 to install one per site, 2019 dollars, INL/RPT-22-68598 (August 2022). The
--                                    robotic arm is not included.
--   public.ottoq_margin_band(qty, low, point, high)
--                                 qty x a price range, rounded to whole dollars, low and high kept in order when qty is
--                                 negative (a baseline that beat OTTO-Q is a loss, and its range reads as one).
--   public.ottoq_margin_ledger    one row per OTTO-Q-against-baseline pair:
--     demand_met_car_hours_delta     the baseline's unmet demand minus OTTO-Q's (0530: each sim-minute, the dispatcher's
--                                    own target against the cars actually out, from the signed event stream). This is
--                                    what uptime is priced on, not deployed_car_hours_delta: a car out beyond what the
--                                    work side asked for earns nothing. The deployed delta is shown beside it.
--     demand_identical               both arms were asked for the same car-hours. A pair where they were not is shown
--                                    and never summarized.
--     uptime_usd_{low,point,high}    demand met x revenue per deployed car-hour: revenue recouped.
--     site_cost_usd_delta            the arms' own site cost, OTTO-Q minus baseline: the window's grid energy, one day's
--                                    share of the month's demand charge, battery wear and the battery's end state, all
--                                    from the depot's NES GSA-3 tariff (ottoq_dial_arm_metrics, 0439). Positive means
--                                    OTTO-Q spent more, which it may: every car it serves charges to 100% (rule 9).
--     cars_at_work_delta             demand met / the window's hours: the average number of extra cars doing the work
--                                    side's work through the window, out of the same fleet.
--     fleet_capex_equiv_usd_{low,point,high}
--                                    those cars x what a robotaxi costs: the same uptime seen as capital. It is the
--                                    OTHER lens on one number, so it is never added to uptime_usd. It is an equivalence,
--                                    not a quote: more cars under a baseline would queue at the same chargers.
--   public.ottoq_margin_summary   per sweep, build-out, dials and baseline, over the pairs that booted from one world and
--                                 were asked for the same demand: how many seeds, how many were set aside, and each
--                                 lever's mean and range.

-- ══ §3 WHAT IT DOES NOT CLAIM ══════════════════════════════════════════════════════════════════════════════════════
--
--   * Chargers avoided is not a column. It is a cross-cell reading (OTTO-Q on 10 chargers against a baseline on 20), made
--     from public.ottoq_throughput_frontier with dcfc_350kw_installed, and stated as a reading, not as a sum.
--   * Nothing is annualized here. The window is the sweep's (night 1: 6 AM-6 PM CT). A reader who multiplies by 365
--     assumes every day is that day, and says so.
--   * Labor (touches avoided), land and late-car penalties are not priced: no source yet for the first two, and no public
--     penalty schedule exists (docs/research/answers/R-10 §Q4).
--
-- ══ §4 WHEN TO APPLY ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Any time. One reference table, one arithmetic function and two read-only views over 0568's evidence; nothing in the
--   engine, the sweep or the determinism pair reads them. forces_recert and forces_dial_restart FALSE.
--
-- ROLLBACK: DROP VIEW public.ottoq_margin_summary, public.ottoq_margin_ledger;
--   DROP FUNCTION public.ottoq_margin_band(numeric, numeric, numeric, numeric); DROP TABLE public.ottoq_margin_prices;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0569_a_margin_ledger_prices_what_the_twin_measured'.

BEGIN;

-- ── P1: the pairs this prices, with the columns it reads ──
DO $premises$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(t || '.' || c, ', ') INTO v_missing
    FROM (VALUES ('ottoq_throughput_sweep_pairs', 'sweep_code'), ('ottoq_throughput_sweep_pairs', 'buildout_code'),
                 ('ottoq_throughput_sweep_pairs', 'fixed_params'), ('ottoq_throughput_sweep_pairs', 'seed'),
                 ('ottoq_throughput_sweep_pairs', 'baseline'), ('ottoq_throughput_sweep_pairs', 'world_identical'),
                 ('ottoq_throughput_sweep_pairs', 'deployed_car_hours_delta'),
                 ('ottoq_throughput_sweep_pairs', 'site_cost_usd_delta'), ('ottoq_throughput_sweep_pairs', 'served_delta'),
                 ('ottoq_throughput_sweep_pairs', 'otto_q_run'), ('ottoq_throughput_sweep_pairs', 'baseline_run'),
                 ('ottoq_throughput_sweep_pairs', 'on_time_pct_delta'),
                 ('ottoq_throughput_sweep_arms', 'sim_run_id'), ('ottoq_throughput_sweep_arms', 'replicate'),
                 ('ottoq_throughput_sweep_arms', 'scorecard'), ('ottoq_throughput_sweep_arms', 'arm_metrics')) AS need(t, c)
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = need.t AND column_name = need.c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0569 P1: the ledger reads columns that do not exist: %', v_missing;
  END IF;
  -- site_cost_usd_per_day is priced from the depot's own tariff (0439), and demand and unmet demand come from 0530: the
  -- ledger passes them through and never re-prices or re-measures them
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)')
                    AND prosrc ~ 'site_cost_usd_per_day' AND prosrc ~ '''unmet_demand_car_hours'''
                    AND prosrc ~ '''demand_car_hours''') THEN
    RAISE EXCEPTION '0569 P1: ottoq_dial_arm_metrics no longer reports site_cost_usd_per_day, demand_car_hours and unmet_demand_car_hours';
  END IF;
END $premises$;

-- ── P2: not applied already ──
DO $fresh$
BEGIN
  IF to_regclass('public.ottoq_margin_prices') IS NOT NULL THEN
    RAISE EXCEPTION '0569 P2: the margin ledger already exists; this file has already been applied';
  END IF;
END $fresh$;

-- ── 1. the prices ──
CREATE TABLE public.ottoq_margin_prices (
  price_code  text PRIMARY KEY CHECK (price_code ~ '^[a-z0-9_]+$'),
  unit        text NOT NULL,
  low         numeric NOT NULL,
  point       numeric NOT NULL,
  high        numeric NOT NULL,
  lever       text NOT NULL,
  basis       text NOT NULL,
  sources     jsonb NOT NULL CHECK (jsonb_typeof(sources) = 'array' AND jsonb_array_length(sources) > 0),
  confidence  text NOT NULL CHECK (confidence IN ('low', 'medium', 'high')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (low <= point AND point <= high)
);
ALTER TABLE public.ottoq_margin_prices ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_margin_prices_read ON public.ottoq_margin_prices FOR SELECT TO authenticated, service_role USING (true);
REVOKE ALL ON public.ottoq_margin_prices FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_margin_prices TO authenticated, service_role;
COMMENT ON TABLE public.ottoq_margin_prices IS
'0569. The prices the margin ledger multiplies measured differences by: a range (low, point, high), its basis, its sources (title, URL, date, retrieved) and a confidence. Recorded from docs/research/direct/2026-09-29-lane-a-margin-inputs.md. A customer''s own number replaces a row; the measured difference never changes with it.';

INSERT INTO public.ottoq_margin_prices (price_code, unit, low, point, high, lever, basis, sources, confidence) VALUES
('revenue_per_deployed_car_hour', 'usd_per_car_hour', 16, 20, 24, 'uptime',
 'Waymo''s annualized revenue run rate of $350M over ~2,500 vehicles = ~$140,000 per vehicle-year = ~$384 per vehicle-day; spread over 24 in-service hours (low, $16) to 16 (high, $24).',
 jsonb_build_array(jsonb_build_object(
   'title', 'Waymo''s 2025 Year in Review: The Year Robotaxis Scaled', 'publisher', 'The Driverless Digest (Daniel Abreu Marques)',
   'url', 'https://www.thedriverlessdigest.com/p/waymos-2025-year-in-review-the-year', 'dated', '2025-12-31', 'retrieved', '2026-09-29',
   'quote', '$350 million annualized run rate as of December 2025, reported by Bloomberg; ~2,500 vehicles (November 2025); 450,000+ weekly paid rides (2025-12-08)')),
 'medium'),
('vehicle_capex', 'usd_per_vehicle', 75000, 150000, 200000, 'fleet_capex_equivalent',
 'A converted Jaguar I-PACE robotaxi is estimated at ~$150,000-$200,000; a purpose-built successor at ~$75,000-$100,000. Estimates, not company-published.',
 jsonb_build_array(
   jsonb_build_object('title', 'Bearly AI on X (Waymo Ojai)', 'url', 'https://x.com/bearlyai/status/2060776487159275809',
                      'dated', '2026', 'retrieved', '2026-09-29',
                      'quote', 'The current fleet costs $200k per vehicle to adapt a Jaguar I-PACE ... each vehicle costs at least half as much ($75k-$100k)'),
   jsonb_build_object('title', 'The First Mass-Produced Robotaxi Is Here', 'publisher', 'Chris Paxton (It Can Think)',
                      'url', 'https://itcanthink.substack.com/p/the-first-mass-produced-robotaxi', 'retrieved', '2026-09-29',
                      'quote', 'the Waymo Jaguar iPace is believed to cost around $150,000 per car')),
 'low'),
('dcfc_350kw_installed', 'usd_per_charger', 193984, 205984, 215984, 'charger_capex',
 '350 kW DCFC hardware $128,000-$150,000 (point $140,000) plus $65,984 to install one per site (labor $27,840, materials $37,700, permit $290, taxes $154); 2019 dollars; less per unit when several share a site. The robotic arm is not included.',
 jsonb_build_array(jsonb_build_object(
   'title', 'Breakdown of Electric Vehicle Supply Equipment Installation Costs (INL/RPT-22-68598)',
   'publisher', 'Idaho National Laboratory (Schey, Chu, Smart)', 'url', 'https://inldigitallibrary.inl.gov/sites/sti/sti/Sort_63124.pdf',
   'dated', '2022-08', 'retrieved', '2026-09-29',
   'quote', 'Table 3 (Nicholas, 2019): 350 kW $140,000; RMI range $128,000 to $150,000. Table 5, 1 DCFC per site, 350 kW: total $65,984')),
 'medium');

-- ── 2. the arithmetic, once: a quantity x a price range ──
CREATE FUNCTION public.ottoq_margin_band(p_qty numeric, p_low numeric, p_point numeric, p_high numeric)
RETURNS numeric[] LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = pg_catalog AS $fn$
  -- [low, point, high] in whole dollars. When the quantity is negative the low price gives the high end, so the bounds
  -- are taken as the least and greatest of the two products rather than in price order.
  SELECT CASE WHEN p_qty IS NULL OR p_low IS NULL OR p_point IS NULL OR p_high IS NULL THEN NULL
              ELSE ARRAY[round(LEAST(p_qty * p_low, p_qty * p_high), 0), round(p_qty * p_point, 0),
                         round(GREATEST(p_qty * p_low, p_qty * p_high), 0)] END
$fn$;
COMMENT ON FUNCTION public.ottoq_margin_band(numeric, numeric, numeric, numeric) IS
'0569. A quantity x a price range as [low, point, high] in whole dollars, in order when the quantity is negative. NULL in, NULL out: a missing measurement or price is never read as zero.';

-- ── 3. the ledger: one row per OTTO-Q-against-baseline pair ──
CREATE VIEW public.ottoq_margin_ledger
WITH (security_invoker = true) AS
WITH pr AS (
  SELECT max(low)   FILTER (WHERE price_code = 'revenue_per_deployed_car_hour') AS rev_lo,
         max(point) FILTER (WHERE price_code = 'revenue_per_deployed_car_hour') AS rev_pt,
         max(high)  FILTER (WHERE price_code = 'revenue_per_deployed_car_hour') AS rev_hi,
         max(low)   FILTER (WHERE price_code = 'vehicle_capex')                 AS cap_lo,
         max(point) FILTER (WHERE price_code = 'vehicle_capex')                 AS cap_pt,
         max(high)  FILTER (WHERE price_code = 'vehicle_capex')                 AS cap_hi
    FROM public.ottoq_margin_prices
), p AS (
  SELECT x.*,
         (qa.scorecard #>> '{run,horizon_h}')::numeric                                  AS window_h,
         (qa.arm_metrics ->> 'demand_car_hours')::numeric                               AS demand_car_hours,
         COALESCE((qa.arm_metrics ->> 'demand_car_hours')::numeric
                    = (ba.arm_metrics ->> 'demand_car_hours')::numeric, false)          AS demand_identical,
         (ba.arm_metrics ->> 'unmet_demand_car_hours')::numeric
           - (qa.arm_metrics ->> 'unmet_demand_car_hours')::numeric                     AS demand_met_car_hours_delta
    FROM public.ottoq_throughput_sweep_pairs x
    JOIN public.ottoq_throughput_sweep_arms qa ON qa.sim_run_id = x.otto_q_run   AND NOT qa.replicate
    JOIN public.ottoq_throughput_sweep_arms ba ON ba.sim_run_id = x.baseline_run AND NOT ba.replicate
), m AS (
  SELECT p.*,
         p.demand_met_car_hours_delta / NULLIF(p.window_h, 0)                                            AS cars,
         public.ottoq_margin_band(p.demand_met_car_hours_delta, pr.rev_lo, pr.rev_pt, pr.rev_hi)         AS up,
         public.ottoq_margin_band(p.demand_met_car_hours_delta / NULLIF(p.window_h, 0),
                                  pr.cap_lo, pr.cap_pt, pr.cap_hi)                                       AS cap
    FROM p CROSS JOIN pr
)
SELECT sweep_code, buildout_code, fixed_params, seed, baseline, world_identical, demand_identical, window_h,
       demand_car_hours, served_delta, on_time_pct_delta, deployed_car_hours_delta, demand_met_car_hours_delta,
       up[1] AS uptime_usd_low, up[2] AS uptime_usd_point, up[3] AS uptime_usd_high,
       round(site_cost_usd_delta, 2) AS site_cost_usd_delta,
       round(cars, 2) AS cars_at_work_delta,
       cap[1] AS fleet_capex_equiv_usd_low, cap[2] AS fleet_capex_equiv_usd_point, cap[3] AS fleet_capex_equiv_usd_high,
       otto_q_run, baseline_run
  FROM m;
COMMENT ON VIEW public.ottoq_margin_ledger IS
'0569. One row per OTTO-Q-against-baseline pair (0568): each measured difference x a sourced price (ottoq_margin_prices), as a range. Uptime is priced on demand met (the baseline''s unmet car-hours minus OTTO-Q''s, 0530), never on cars out beyond what the work side asked for. uptime_usd is revenue recouped; fleet_capex_equiv_usd is the OTHER lens on the same uptime and is never added to it; site_cost_usd_delta is the arms'' own tariff-priced cost, OTTO-Q minus baseline. Per the sweep''s window, never annualized here.';

CREATE VIEW public.ottoq_margin_summary
WITH (security_invoker = true) AS
WITH l AS (
  SELECT *, (world_identical AND demand_identical) AS clean FROM public.ottoq_margin_ledger
)
SELECT sweep_code, buildout_code, fixed_params, baseline, max(window_h) AS window_h,
       count(*) FILTER (WHERE clean)                   AS seeds,
       count(*) FILTER (WHERE NOT clean)               AS seeds_set_aside,
       jsonb_build_object('mean', round(avg(served_delta) FILTER (WHERE clean), 1),
                          'min', min(served_delta) FILTER (WHERE clean), 'max', max(served_delta) FILTER (WHERE clean))
                                                       AS served_delta,
       jsonb_build_object('mean', round(avg(demand_met_car_hours_delta) FILTER (WHERE clean), 1),
                          'min', min(demand_met_car_hours_delta) FILTER (WHERE clean),
                          'max', max(demand_met_car_hours_delta) FILTER (WHERE clean))
                                                       AS demand_met_car_hours_delta,
       jsonb_build_object('mean_point', round(avg(uptime_usd_point) FILTER (WHERE clean), 0),
                          'min_low', min(uptime_usd_low) FILTER (WHERE clean),
                          'max_high', max(uptime_usd_high) FILTER (WHERE clean))
                                                       AS uptime_usd,
       jsonb_build_object('mean', round(avg(site_cost_usd_delta) FILTER (WHERE clean), 2),
                          'min', min(site_cost_usd_delta) FILTER (WHERE clean),
                          'max', max(site_cost_usd_delta) FILTER (WHERE clean))
                                                       AS site_cost_usd_delta,
       jsonb_build_object('mean', round(avg(cars_at_work_delta) FILTER (WHERE clean), 2),
                          'min', min(cars_at_work_delta) FILTER (WHERE clean),
                          'max', max(cars_at_work_delta) FILTER (WHERE clean))
                                                       AS cars_at_work_delta,
       jsonb_build_object('mean_point', round(avg(fleet_capex_equiv_usd_point) FILTER (WHERE clean), 0),
                          'min_low', min(fleet_capex_equiv_usd_low) FILTER (WHERE clean),
                          'max_high', max(fleet_capex_equiv_usd_high) FILTER (WHERE clean))
                                                       AS fleet_capex_equiv_usd
  FROM l
 GROUP BY sweep_code, buildout_code, fixed_params, baseline;
COMMENT ON VIEW public.ottoq_margin_summary IS
'0569. The margin ledger per sweep, build-out, dials and baseline, over the pairs that booted from one world and were asked for the same demand: how many seeds, how many were set aside, and each lever as a mean and a range over seeds. Five seeds are a signal, not a distribution; the range says so.';

REVOKE ALL ON public.ottoq_margin_ledger, public.ottoq_margin_summary FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_margin_ledger, public.ottoq_margin_summary TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_margin_band(numeric, numeric, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_margin_band(numeric, numeric, numeric, numeric) TO authenticated, service_role;

-- ── V1: the prices carry their sources, and the ledger's arithmetic is what it says on a known pair ──
DO $verify$
DECLARE
  v_row jsonb;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_margin_prices) <> 3
     OR EXISTS (SELECT 1 FROM public.ottoq_margin_prices, jsonb_array_elements(sources) s
                 WHERE COALESCE(s->>'url', '') !~ '^https://' OR COALESCE(s->>'retrieved', '') = '') THEN
    RAISE EXCEPTION '0569 V1: a price lacks a source URL or a retrieval date';
  END IF;
  -- the arithmetic the views use, on one synthetic pair each way: 6 car-hours of demand met over a 12-hour window at
  -- $16/$20/$24 and $75k/$150k/$200k; then the same pair with the baseline ahead, whose range must read as a loss
  SELECT jsonb_build_object(
           'up',   public.ottoq_margin_band(6, pr.low, pr.point, pr.high),
           'cap',  public.ottoq_margin_band(6 / 12.0, c.low, c.point, c.high),
           'down', public.ottoq_margin_band(-6, pr.low, pr.point, pr.high),
           'none', public.ottoq_margin_band(NULL, pr.low, pr.point, pr.high))
    INTO v_row
    FROM public.ottoq_margin_prices pr, public.ottoq_margin_prices c
   WHERE pr.price_code = 'revenue_per_deployed_car_hour' AND c.price_code = 'vehicle_capex';
  IF v_row <> '{"up": [96, 120, 144], "cap": [37500, 75000, 100000], "down": [-144, -120, -96], "none": null}'::jsonb THEN
    RAISE EXCEPTION '0569 V1: the price arithmetic reads %', v_row;
  END IF;
  IF has_table_privilege('anon', 'public.ottoq_margin_ledger', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.ottoq_margin_summary', 'SELECT')
     OR has_function_privilege('anon', 'public.ottoq_margin_band(numeric,numeric,numeric,numeric)', 'EXECUTE') THEN
    RAISE EXCEPTION '0569 V1: grants are not as declared';
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0569_a_margin_ledger_prices_what_the_twin_measured', false, false,
  'One reference table of sourced prices, one arithmetic function and two read-only views over 0568''s evidence. Nothing in the engine, the sweep, the recertification runner or the determinism pair reads them.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
