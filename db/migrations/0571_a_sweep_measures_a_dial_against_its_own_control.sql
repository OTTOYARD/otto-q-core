-- migration-version: PENDING
-- migration-name:    a_sweep_measures_a_dial_against_its_own_control
--
-- 0571  **A sweep measures a dial against its own control, the margin ledger prices it, and night 2 measures G297's.**
--       Lane A, the second night. 0568's pairs compare OTTO-Q with a baseline seat on the same dials; a research dial
--       (0570's `charge_batch_order`) is OTTO-Q against OTTO-Q, so it needs a control cell of its own.
--
-- ══ §1 WHAT THIS BUILDS ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_throughput_sweep_cells.control_cell_code`: a treatment cell names its control, a cell of the same sweep
--       with the same seat and build-out that is not itself a treatment. A trigger refuses anything else, so a contrast
--       can only ever differ by its dials.
--   (b) `public.ottoq_throughput_sweep_contrasts`: per treatment cell and seed, treatment minus control on the same
--       columns 0568's pairs carry (served, on time, door-to-door, deployed car-hours, site cost), with world_identical
--       from the two arms' boot image and calibration. The same arms count as in the pairs: current, complete, shield
--       paid, not a replicate.
--   (c) `public.ottoq_margin_ledger` prices contrasts too. It gains one column at the end, `comparison`: 'seat' for
--       0568's pairs (the rows it held before, unchanged) and 'dial' for a contrast, where `baseline` is the control
--       cell's code and `otto_q_run` / `baseline_run` are the treatment's and the control's runs. The arithmetic is 0569's,
--       unchanged: uptime on demand met, the band in order, NULL never read as zero. `ottoq_margin_summary` groups the
--       new rows by their control cell without change.
--   (d) `public.ottoq_throughput_cross_sweep_twins`: two primary arms of DIFFERENT sweeps that ran one cell definition
--       (scenario, depot, start, step, ticks, seat, build-out, dials) on one seed, and whether their boot image and every
--       atom agree. Night 2's control cells repeat night 1's OTTO-Q cells on night 1's seeds, so this is the
--       cross-night, cross-transaction determinism G140 asked for, and the real-engine check of 0570's claim that its
--       default changes nothing.
--   (e) Night 2, `charge_order_2026_09_30`: busy_day at the twin, 12 h from 6 AM CT at 5 sim-minutes a tick,
--       deploy_peak_fraction 0.90, night 1's five seeds, no replicate, due 04:00 UTC 2026-10-01 (11 PM CT Sep 30).
--       Four cells, seed by seed: dcfc10.otto_q, dcfc10.otto_q.batch_order (control dcfc10.otto_q), dcfc20.otto_q,
--       dcfc20.otto_q.batch_order (control dcfc20.otto_q). Twenty arms; about 2.5 hours at the smoke arm's pace.
--       If night 1 is not finished by then, it finishes first (same priority, created earlier).
--
-- ══ §2 WHAT IT DOES NOT CLAIM ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Five seeds are a signal, not a distribution, and nothing here decides whether the dial ships. A win is a
--   recommendation (0540, rule 10); shipping 0570's order is a certified change a person makes.
--
-- ══ §3 WHEN TO APPLY ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   After 0570 (P1 requires its dial to be catalogued, or night 2's arms would be refused), and before 11 PM CT on
--   Sep 30. One column, one trigger, three views and one sweep; nothing in the engine or the determinism pair reads
--   them. forces_recert and forces_dial_restart FALSE.
--
-- ROLLBACK: DELETE night 2's cells and sweep (no arms yet, or they are evidence and stay); DROP VIEW
--   public.ottoq_throughput_cross_sweep_twins; restore ottoq_margin_ledger from 0569's text; DROP VIEW
--   public.ottoq_throughput_sweep_contrasts; DROP TRIGGER trg_ottoq_throughput_sweep_cells_control ON
--   public.ottoq_throughput_sweep_cells; DROP FUNCTION public.ottoq_throughput_sweep_cells_control();
--   ALTER TABLE public.ottoq_throughput_sweep_cells DROP COLUMN control_cell_code; DELETE the lineage row.

BEGIN;

-- ── P1: 0568's sweep and 0569's ledger are as this reads them, and 0570's dial is catalogued ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_throughput_sweep_cells') IS NULL OR to_regclass('public.ottoq_margin_ledger') IS NULL
     OR to_regclass('public.ottoq_margin_summary') IS NULL OR to_regprocedure('public.ottoq_margin_band(numeric,numeric,numeric,numeric)') IS NULL THEN
    RAISE EXCEPTION '0571 P1: 0568''s sweep or 0569''s ledger is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_batch_order'
                    AND min_value = 0 AND max_value = 1) THEN
    RAISE EXCEPTION '0571 P1: charge_batch_order is not catalogued; apply 0570 first, or night 2''s arms are refused';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'frontier_2026_09_29'
                    AND cardinality(seeds) = 5) THEN
    RAISE EXCEPTION '0571 P1: night 1 (frontier_2026_09_29) and its five seeds are missing';
  END IF;
  -- the ledger this replaces is 0569's: the replacement keeps every column in place and appends one
  IF (SELECT string_agg(attname, ',' ORDER BY attnum) FROM pg_attribute
       WHERE attrelid = 'public.ottoq_margin_ledger'::regclass AND attnum > 0 AND NOT attisdropped)
     <> 'sweep_code,buildout_code,fixed_params,seed,baseline,world_identical,demand_identical,window_h,demand_car_hours,'
        'served_delta,on_time_pct_delta,deployed_car_hours_delta,demand_met_car_hours_delta,uptime_usd_low,'
        'uptime_usd_point,uptime_usd_high,site_cost_usd_delta,cars_at_work_delta,fleet_capex_equiv_usd_low,'
        'fleet_capex_equiv_usd_point,fleet_capex_equiv_usd_high,otto_q_run,baseline_run' THEN
    RAISE EXCEPTION '0571 P1: ottoq_margin_ledger is not 0569''s';
  END IF;
END $premises$;

-- ── P2: not applied already ──
DO $fresh$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                AND table_name = 'ottoq_throughput_sweep_cells' AND column_name = 'control_cell_code') THEN
    RAISE EXCEPTION '0571 P2: control_cell_code already exists; this file has already been applied';
  END IF;
END $fresh$;

-- ── (a) a treatment names its control ──
ALTER TABLE public.ottoq_throughput_sweep_cells
  ADD COLUMN control_cell_code text,
  ADD CONSTRAINT ottoq_throughput_sweep_cells_control_fk
      FOREIGN KEY (sweep_id, control_cell_code) REFERENCES public.ottoq_throughput_sweep_cells (sweep_id, cell_code),
  ADD CONSTRAINT ottoq_throughput_sweep_cells_control_not_self CHECK (control_cell_code IS DISTINCT FROM cell_code);
COMMENT ON COLUMN public.ottoq_throughput_sweep_cells.control_cell_code IS
'0571. The cell this one is measured against (ottoq_throughput_sweep_contrasts): same sweep, same seat, same build-out, not itself a treatment. NULL for a cell that is not a treatment.';

CREATE FUNCTION public.ottoq_throughput_sweep_cells_control()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_catalog AS $fn$
DECLARE
  k public.ottoq_throughput_sweep_cells%ROWTYPE;
BEGIN
  IF NEW.control_cell_code IS NULL THEN
    RETURN NEW;                     -- not a treatment: nothing to check
  END IF;
  SELECT * INTO k FROM public.ottoq_throughput_sweep_cells
   WHERE sweep_id = NEW.sweep_id AND cell_code = NEW.control_cell_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'sweep cell %: control % is not a cell of the same sweep', NEW.cell_code, NEW.control_cell_code;
  END IF;
  IF k.seat <> NEW.seat OR k.buildout_code <> NEW.buildout_code THEN
    RAISE EXCEPTION 'sweep cell %: a contrast differs only by its dials, but control % is seat % on %, not seat % on %',
      NEW.cell_code, k.cell_code, k.seat, k.buildout_code, NEW.seat, NEW.buildout_code;
  END IF;
  IF k.control_cell_code IS NOT NULL THEN
    RAISE EXCEPTION 'sweep cell %: control % is itself a treatment', NEW.cell_code, k.cell_code;
  END IF;
  IF k.fixed_params = NEW.fixed_params THEN
    RAISE EXCEPTION 'sweep cell %: it has the same dials as its control %, so there is nothing to contrast', NEW.cell_code, k.cell_code;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c
              WHERE c.sweep_id = NEW.sweep_id AND c.control_cell_code = NEW.cell_code) THEN
    RAISE EXCEPTION 'sweep cell %: it is another cell''s control, so it cannot be a treatment', NEW.cell_code;
  END IF;
  RETURN NEW;
END $fn$;
CREATE TRIGGER trg_ottoq_throughput_sweep_cells_control
  BEFORE INSERT OR UPDATE ON public.ottoq_throughput_sweep_cells
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_throughput_sweep_cells_control();

-- ── (b) the contrasts ──
CREATE VIEW public.ottoq_throughput_sweep_contrasts
WITH (security_invoker = true) AS
WITH cur AS (
  SELECT a.*, c.cell_code, c.seat, c.buildout_code, c.fixed_params, c.control_cell_code, s.sweep_code
    FROM public.ottoq_throughput_sweep_arms a
    JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE NOT a.replicate AND a.ran_at >= public.ottoq_dial_pair_floor() AND a.complete AND a.paid_shield
)
SELECT t.sweep_code, t.cell_code AS treatment_cell, k.cell_code AS control_cell, t.buildout_code, t.seat,
       t.fixed_params AS treatment_params, k.fixed_params AS control_params, t.seed,
       t.boot_md5 = k.boot_md5 AND t.h_cal IS NOT DISTINCT FROM k.h_cal                   AS world_identical,
       (t.scorecard #>> '{throughput,visits_served}')::numeric
         - (k.scorecard #>> '{throughput,visits_served}')::numeric                        AS served_delta,
       (t.scorecard #>> '{timeliness,on_time_pct}')::numeric
         - (k.scorecard #>> '{timeliness,on_time_pct}')::numeric                          AS on_time_pct_delta,
       (t.scorecard #>> '{timeliness,door_p50_min}')::numeric
         - (k.scorecard #>> '{timeliness,door_p50_min}')::numeric                         AS door_p50_delta_min,
       (t.arm_metrics ->> 'deployed_car_hours')::numeric
         - (k.arm_metrics ->> 'deployed_car_hours')::numeric                              AS deployed_car_hours_delta,
       (t.arm_metrics ->> 'site_cost_usd_per_day')::numeric
         - (k.arm_metrics ->> 'site_cost_usd_per_day')::numeric                           AS site_cost_usd_delta,
       t.sim_run_id AS treatment_run, k.sim_run_id AS control_run
  FROM cur t
  JOIN cur k ON k.sweep_id = t.sweep_id AND k.cell_code = t.control_cell_code AND k.seed = t.seed
 WHERE t.control_cell_code IS NOT NULL;
COMMENT ON VIEW public.ottoq_throughput_sweep_contrasts IS
'0571. A treatment cell against its control cell on the same seed (common random numbers): the same seat and build-out, different dials. Deltas are treatment minus control; world_identical says whether both arms booted from one world. Current valid arms only, as 0568''s pairs.';

-- ── (c) the ledger prices contrasts too; every row it held before is unchanged ──
CREATE OR REPLACE VIEW public.ottoq_margin_ledger
WITH (security_invoker = true) AS
WITH pr AS (
  SELECT max(low)   FILTER (WHERE price_code = 'revenue_per_deployed_car_hour') AS rev_lo,
         max(point) FILTER (WHERE price_code = 'revenue_per_deployed_car_hour') AS rev_pt,
         max(high)  FILTER (WHERE price_code = 'revenue_per_deployed_car_hour') AS rev_hi,
         max(low)   FILTER (WHERE price_code = 'vehicle_capex')                 AS cap_lo,
         max(point) FILTER (WHERE price_code = 'vehicle_capex')                 AS cap_pt,
         max(high)  FILTER (WHERE price_code = 'vehicle_capex')                 AS cap_hi
    FROM public.ottoq_margin_prices
), cmp AS (
  SELECT 'seat'::text AS comparison, x.sweep_code, x.buildout_code, x.fixed_params, x.seed, x.baseline, x.world_identical,
         x.served_delta, x.on_time_pct_delta, x.deployed_car_hours_delta, x.site_cost_usd_delta, x.otto_q_run, x.baseline_run
    FROM public.ottoq_throughput_sweep_pairs x
  UNION ALL
  SELECT 'dial', c.sweep_code, c.buildout_code, c.treatment_params, c.seed, c.control_cell, c.world_identical,
         c.served_delta, c.on_time_pct_delta, c.deployed_car_hours_delta, c.site_cost_usd_delta, c.treatment_run, c.control_run
    FROM public.ottoq_throughput_sweep_contrasts c
), p AS (
  SELECT x.*,
         (qa.scorecard #>> '{run,horizon_h}')::numeric                                  AS window_h,
         (qa.arm_metrics ->> 'demand_car_hours')::numeric                               AS demand_car_hours,
         COALESCE((qa.arm_metrics ->> 'demand_car_hours')::numeric
                    = (ba.arm_metrics ->> 'demand_car_hours')::numeric, false)          AS demand_identical,
         (ba.arm_metrics ->> 'unmet_demand_car_hours')::numeric
           - (qa.arm_metrics ->> 'unmet_demand_car_hours')::numeric                     AS demand_met_car_hours_delta
    FROM cmp x
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
       otto_q_run, baseline_run, comparison
  FROM m;
COMMENT ON VIEW public.ottoq_margin_ledger IS
'0569, 0571. One row per comparison: OTTO-Q against a baseline seat on the same dials (comparison ''seat'', 0568''s pairs) or a treatment cell against its control cell (comparison ''dial'', 0571''s contrasts; baseline is the control cell''s code, otto_q_run the treatment''s run). Each measured difference x a sourced price (ottoq_margin_prices), as a range. Uptime is priced on demand met (the baseline''s unmet car-hours minus OTTO-Q''s, 0530), never on cars out beyond what the work side asked for. uptime_usd is revenue recouped; fleet_capex_equiv_usd is the OTHER lens on the same uptime and is never added to it; site_cost_usd_delta is the arms'' own tariff-priced cost. Per the sweep''s window, never annualized here.';

-- ── (d) the same cell definition on the same seed in two sweeps ──
CREATE VIEW public.ottoq_throughput_cross_sweep_twins
WITH (security_invoker = true) AS
WITH cur AS (
  SELECT a.arm_id, a.seed, a.ran_at, a.boot_md5, a.atoms, a.sweep_id, s.sweep_code, s.depot_id, s.scenario, s.sim_start,
         s.sim_min_per_tick, s.ticks, c.cell_code, c.seat, c.buildout_code, c.fixed_params
    FROM public.ottoq_throughput_sweep_arms a
    JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE NOT a.replicate AND a.complete AND a.ran_at >= public.ottoq_dial_pair_floor()
)
SELECT e.sweep_code AS earlier_sweep, e.cell_code AS earlier_cell, l.sweep_code AS later_sweep, l.cell_code AS later_cell,
       l.seed, e.arm_id AS earlier_arm, l.arm_id AS later_arm, e.ran_at AS earlier_ran_at, l.ran_at AS later_ran_at,
       l.boot_md5 = e.boot_md5 AND l.atoms = e.atoms                                         AS identical,
       (SELECT COALESCE(jsonb_agg(k ORDER BY k), '[]'::jsonb)
          FROM jsonb_object_keys(COALESCE(e.atoms, '{}'::jsonb) || COALESCE(l.atoms, '{}'::jsonb)) AS k
         WHERE (e.atoms -> k) IS DISTINCT FROM (l.atoms -> k))                               AS moved
  FROM cur e
  JOIN cur l ON l.sweep_id <> e.sweep_id AND l.ran_at > e.ran_at AND l.seed = e.seed AND l.depot_id = e.depot_id
            AND l.scenario = e.scenario AND l.sim_start = e.sim_start AND l.sim_min_per_tick = e.sim_min_per_tick
            AND l.ticks = e.ticks AND l.seat = e.seat AND l.buildout_code = e.buildout_code
            AND l.fixed_params = e.fixed_params;
COMMENT ON VIEW public.ottoq_throughput_cross_sweep_twins IS
'0571. Two primary arms of different sweeps that ran one cell definition on one seed: identical when the boot image and every atom (ottoq_ab_arm_atoms) agree. Different sweeps, nights and transactions: cross-transaction determinism (G140), and a real-engine check that an engine change classified as default-neutral moved nothing.';

REVOKE ALL ON public.ottoq_throughput_sweep_contrasts, public.ottoq_throughput_cross_sweep_twins
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_throughput_sweep_contrasts, public.ottoq_throughput_cross_sweep_twins
  TO authenticated, service_role;
REVOKE ALL ON public.ottoq_margin_ledger FROM PUBLIC, anon;
GRANT SELECT ON public.ottoq_margin_ledger TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_throughput_sweep_cells_control() FROM PUBLIC, anon, authenticated;

-- ── (e) night 2 ──
WITH sw AS (
  INSERT INTO public.ottoq_throughput_sweeps
         (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority, run_after, notes)
  SELECT 'charge_order_2026_09_30',
         'G297: the batch optimizer in the charge cursor''s order, against OTTO-Q as it is',
         f.depot_id, f.scenario, f.sim_start, f.ticks, f.sim_min_per_tick, f.seeds, 0, 100, '2026-10-01 04:00:00+00',
         'Night 2 (0571). Each treatment is OTTO-Q with charge_batch_order = 1 (0570) against OTTO-Q at the default, on '
         'night 1''s seeds and build-outs. The controls repeat night 1''s OTTO-Q cells, so ottoq_throughput_cross_sweep_twins '
         'also checks, on the real engine, that 0570''s default changed nothing.'
    FROM public.ottoq_throughput_sweeps f WHERE f.sweep_code = 'frontier_2026_09_29'
  RETURNING sweep_id
)
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT sw.sweep_id, c.cell_code, c.ord, 'otto_q', c.buildout_code, c.fixed_params
  FROM sw, (VALUES ('dcfc10.otto_q', 1, 'dcfc10', '{"deploy_peak_fraction": 0.90}'::jsonb),
                   ('dcfc20.otto_q', 3, 'dcfc20', '{"deploy_peak_fraction": 0.90}'::jsonb)) AS c(cell_code, ord, buildout_code, fixed_params);
-- the treatments go in after their controls exist, so the trigger can check them
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params, control_cell_code)
SELECT s.sweep_id, c.cell_code, c.ord, 'otto_q', c.buildout_code, c.fixed_params, c.control
  FROM public.ottoq_throughput_sweeps s,
       (VALUES ('dcfc10.otto_q.batch_order', 2, 'dcfc10', '{"deploy_peak_fraction": 0.90, "charge_batch_order": 1}'::jsonb, 'dcfc10.otto_q'),
               ('dcfc20.otto_q.batch_order', 4, 'dcfc20', '{"deploy_peak_fraction": 0.90, "charge_batch_order": 1}'::jsonb, 'dcfc20.otto_q'))
         AS c(cell_code, ord, buildout_code, fixed_params, control)
 WHERE s.sweep_code = 'charge_order_2026_09_30';

-- ── V1: night 2 is what it says, its dials would pass the arm, and the ledger kept its rows ──
DO $verify$
DECLARE
  v_bad text;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'charge_order_2026_09_30') <> 4
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
          WHERE s.sweep_code = 'charge_order_2026_09_30' AND c.control_cell_code IS NOT NULL) <> 2
     OR (SELECT seeds FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'charge_order_2026_09_30')
        IS DISTINCT FROM (SELECT seeds FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'frontier_2026_09_29') THEN
    RAISE EXCEPTION '0571 V1: night 2 is not four cells, two contrasts, on night 1''s seeds';
  END IF;
  -- every dial of every night-2 cell is catalogued and in range: the arm's own validation (0568)
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code = 'charge_order_2026_09_30'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0571 V1: night-2 dials the arm would refuse: %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_margin_ledger WHERE comparison IS DISTINCT FROM 'seat'
                                                        AND comparison IS DISTINCT FROM 'dial') THEN
    RAISE EXCEPTION '0571 V1: a ledger row has no comparison';
  END IF;
  IF has_table_privilege('anon', 'public.ottoq_throughput_sweep_contrasts', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.ottoq_margin_ledger', 'SELECT') THEN
    RAISE EXCEPTION '0571 V1: grants are not as declared';
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0571_a_sweep_measures_a_dial_against_its_own_control', false, false,
  'A control column and its trigger on the sweep''s cells, two read views (contrasts, cross-sweep twins), the margin ledger '
  'extended to price contrasts, and night 2''s sweep. Nothing in the engine, the recertification runner or the '
  'determinism pair reads them.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
