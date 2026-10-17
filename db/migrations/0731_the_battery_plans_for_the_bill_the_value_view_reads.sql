-- migration-version: PENDING
-- migration-name:    the_battery_plans_for_the_bill_the_value_view_reads
--
-- 0731  **The battery plans for the bill the value view reads.** Three paired cells on the seed and day that arms 83,
--       84 and 0729's managed arm ran on, each with `bess_plan_bill_from_min` 180, so the battery's day plan counts the
--       same half hours the value view bills (G447). Research wing, rule 10: it measures, and a result is a
--       recommendation.
--
-- ══ §1 WHY (G447, db/checks/0451 §11) ═════════════════════════════════════════════════════════════════════════════════
--
--   ottoq_bess_day_plan shaves to a level no lower than the billed peak so far, counted from bess_plan_bill_from_min
--   minutes into the run (default 0, set by no sweep cell). ottoq_value_summary bills from 180 minutes in. On arm 84 the
--   opening set the plan's billed peak at 2,370 kW, and the battery held all afternoon at 90-91% while the half hours
--   the value view bills peaked at 1,006.8 kW. Every arm on record ran at 0, so comparisons between cells stand; what a
--   battery is worth to each build-out, on the bill the value view reads, is not yet measured.
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Sweep `billwindow_normal_2026_10_17`: normal_day from 6 AM CT, 144 ticks of 5 minutes, value_2026_09_30's first
--   seed, priority 16 (after 0728's dcfc40_power_normal, whose cells are the same priority and older), arm budget 5,400
--   s, due now. Three cells, each its partner's dials plus bess_plan_bill_from_min 180:
--     ord 1  dcfc10.otto_q.bill180             against arm 83
--     ord 2  dcfc40.otto_q.bill180             against arm 84
--     ord 3  dcfc40_cab2400.managed.bill180    against 0729's dcfc40_cab2400.managed
--   Each pair differs in that one dial. A pair's gap is a single reading on one seed (G153), and the replicate 0728
--   notes is the first measure of how far one reading can move.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: the build-outs, normal_day, value_2026_09_30's seeds, 0729's sweep and the dial exist. P2: not already applied.
--   V1: normal_day, one seed (value_2026_09_30's first), 12 hours, priority 16, the three cells in order, each setting
--   bess_plan_bill_from_min 180, every dial one the arm accepts.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows in the sweep tables, read only by the sweep runner.
--
-- ROLLBACK (before the sweep has run): DELETE its cell and sweep rows; once it has run, its arms are evidence and stay.
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0731_the_battery_plans_for_the_bill_the_value_view_reads'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P1: what the cells name ──
DO $premises$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_site_buildouts WHERE buildout_code IN ('dcfc10', 'dcfc40', 'dcfc40_cab2400')) <> 3 THEN
    RAISE EXCEPTION '0731 P1: build-outs dcfc10, dcfc40 and dcfc40_cab2400 are not all present';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_scenarios WHERE scenario_code = 'normal_day' AND status = 'available') THEN
    RAISE EXCEPTION '0731 P1: normal_day is not an available scenario';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30'
                  AND cardinality(seeds) = 3) THEN
    RAISE EXCEPTION '0731 P1: value_2026_09_30 and its three seeds are missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_managed_normal_2026_10_17')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bess_plan_bill_from_min'
                     AND max_value >= 180) THEN
    RAISE EXCEPTION '0731 P1: 0729 is not applied, or bess_plan_bill_from_min cannot be 180';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'billwindow_normal_2026_10_17') THEN
    RAISE EXCEPTION '0731 P2: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes)
SELECT 'billwindow_normal_2026_10_17',
       'The battery plans for the bill the value view reads: ten, forty, and forty behind a site controller',
       v.depot_id, 'normal_day', v.sim_start, 144, v.sim_min_per_tick, v.seeds[1:1], 0, 16, 5400, now(),
       '0731 (G447): arms 83 and 84 and 0729''s managed cell again, each with bess_plan_bill_from_min 180 so the battery''s '
       'day plan counts the half hours ottoq_value_summary bills. normal_day from 6 AM CT for 12 hours at 5 sim-minutes a '
       'tick, value_2026_09_30''s first seed.'
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, c.cell_code, c.ord, 'otto_q', c.buildout_code, c.fixed_params
  FROM public.ottoq_throughput_sweeps s,
       (VALUES ('dcfc10.otto_q.bill180', 1, 'dcfc10',
                '{"deploy_peak_fraction": 0.90, "bess_plan_bill_from_min": 180}'::jsonb),
               ('dcfc40.otto_q.bill180', 2, 'dcfc40',
                '{"deploy_peak_fraction": 0.90, "bess_plan_bill_from_min": 180}'::jsonb),
               ('dcfc40_cab2400.managed.bill180', 3, 'dcfc40_cab2400',
                '{"deploy_peak_fraction": 0.90, "dc_power_sharing": 1, "dc_power_managed": 1, "enforce_site_charge_cap": 0, "bess_plan_bill_from_min": 180}'::jsonb))
         AS c(cell_code, ord, buildout_code, fixed_params)
 WHERE s.sweep_code = 'billwindow_normal_2026_10_17';

-- ── V1: the sweep is what §2 says, and the arm would accept every dial ──
DO $verify$
DECLARE v_bad text;
BEGIN
  IF (SELECT row(scenario, ticks * sim_min_per_tick, priority, cardinality(seeds))
        FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'billwindow_normal_2026_10_17')
     IS DISTINCT FROM row('normal_day'::text, 720::numeric, 16, 1) THEN
    RAISE EXCEPTION '0731 V1: the sweep is not normal_day, 12 hours, priority 16, one seed';
  END IF;
  IF (SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'billwindow_normal_2026_10_17')
     IS DISTINCT FROM (SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30') THEN
    RAISE EXCEPTION '0731 V1: the seed is not value_2026_09_30''s first';
  END IF;
  IF (SELECT string_agg(c.cell_code, ',' ORDER BY c.ord) FROM public.ottoq_throughput_sweep_cells c
        JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'billwindow_normal_2026_10_17')
     IS DISTINCT FROM 'dcfc10.otto_q.bill180,dcfc40.otto_q.bill180,dcfc40_cab2400.managed.bill180' THEN
    RAISE EXCEPTION '0731 V1: the three cells are not in the order §2 names';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
              WHERE s.sweep_code = 'billwindow_normal_2026_10_17'
                AND (c.fixed_params ->> 'bess_plan_bill_from_min') IS DISTINCT FROM '180') THEN
    RAISE EXCEPTION '0731 V1: a cell does not set bess_plan_bill_from_min 180';
  END IF;
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code = 'billwindow_normal_2026_10_17'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0731 V1: dials the arm would refuse: %', v_bad;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0731_the_battery_plans_for_the_bill_the_value_view_reads', false, false,
  'Rows only: sweep billwindow_normal_2026_10_17 (normal_day, three cells pairing arms 83 and 84 and 0729''s managed '
  'cell with bess_plan_bill_from_min 180, one seed, 12-hour days, priority 16). Read only by the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
