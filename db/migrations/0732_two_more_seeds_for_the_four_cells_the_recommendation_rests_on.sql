-- migration-version: PENDING
-- migration-name:    two_more_seeds_for_the_four_cells_the_recommendation_rests_on
--
-- 0732  **Two more seeds for the four cells the recommendation rests on.** db/checks/0451 §10 rests on four normal-day
--       arms, each a single seed: arm 83 (the depot as built, ten fast chargers), arm 86 (twenty), arm 84 (forty, grid
--       grown) and arm 85 (forty on today's service, held at its limit, 0729). This runs the same four cells on
--       value_2026_09_30's other two seeds, so every gap §10 quotes becomes three readings instead of one. Research wing,
--       rule 10: it measures, and a result is a recommendation.
--
-- ══ §1 WHY (db/checks/0451 §10 point 7) ════════════════════════════════════════════════════════════════════════════
--
--   Every figure in 0451 §3 is one seed, a single reading (G153). The repeats of arms 84 and 86 that 0725's sweep holds
--   run that same seed again, so they test whether a reading repeats from one night to the next, not how far it moves
--   from seed to seed. Each arm here starts from the same scenario and sim clock as its seed-1 partner and differs only
--   in the seed, so the three readings of a cell are three draws of the same day under the same build-out and dials.
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Sweep `seeds23_normal_2026_10_17`: normal_day from 6 AM CT, 144 ticks of 5 minutes, value_2026_09_30's seeds 2 and 3,
--   priority 16 (after 0731's bill-window sweep, the same priority and older, and before 0728's busy-day cells at 17),
--   arm budget 5,400 s, due now. Four cells, each its seed-1 partner's build-out and dials exactly:
--     ord 1  dcfc10.otto_q            dcfc10           deploy_peak_fraction 0.90                         (arm 83)
--     ord 2  dcfc20.otto_q            dcfc20           deploy_peak_fraction 0.90                         (arm 86)
--     ord 3  dcfc40.otto_q            dcfc40           deploy_peak_fraction 0.90                         (arm 84)
--     ord 4  dcfc40_cab2400.managed   dcfc40_cab2400   deploy_peak_fraction 0.90, dc_power_sharing 1,
--                                                      dc_power_managed 1, enforce_site_charge_cap 0     (arm 85)
--   The runner takes a sweep seed by seed and cell by cell, so a window that closes early still leaves seed 2 complete
--   across all four cells. Eight arms of about 31-38 minutes each (tonight's), after 0731's three: about 6.3 hours of a
--   7-hour window.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: the four build-outs, normal_day, value_2026_09_30's three seeds, and 0731's sweep exist; the four seed-1 cells
--   carry the dials §2 copies. P2: not already applied. V1: normal_day, two seeds (value_2026_09_30's second and third),
--   12 hours from the seed-1 arms' sim start, priority 16, the four cells in order, each cell's build-out and dials equal
--   to its seed-1 partner's, every dial one the arm accepts.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows in the sweep tables, read only by the sweep runner.
--
-- ROLLBACK (before the sweep has run): DELETE its cell and sweep rows; once it has run, its arms are evidence and stay.
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0732_two_more_seeds_for_the_four_cells_the_recommendation_rests_on'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P1: what the cells copy ──
DO $premises$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_site_buildouts
       WHERE buildout_code IN ('dcfc10', 'dcfc20', 'dcfc40', 'dcfc40_cab2400')) <> 4 THEN
    RAISE EXCEPTION '0732 P1: build-outs dcfc10, dcfc20, dcfc40 and dcfc40_cab2400 are not all present';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_scenarios WHERE scenario_code = 'normal_day' AND status = 'available') THEN
    RAISE EXCEPTION '0732 P1: normal_day is not an available scenario';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30'
                  AND cardinality(seeds) = 3) THEN
    RAISE EXCEPTION '0732 P1: value_2026_09_30 and its three seeds are missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'billwindow_normal_2026_10_17') THEN
    RAISE EXCEPTION '0732 P1: 0731 is not applied';
  END IF;
  -- the seed-1 cells this copies, by the sweeps that ran them
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE (s.sweep_code, c.cell_code, c.buildout_code, c.fixed_params) IN (
               ('dcfc40_normal_2026_10_17', 'dcfc10.otto_q', 'dcfc10', '{"deploy_peak_fraction": 0.90}'::jsonb),
               ('dcfc20_normal_2026_10_17', 'dcfc20.otto_q', 'dcfc20', '{"deploy_peak_fraction": 0.90}'::jsonb),
               ('dcfc40_power_normal_2026_10_17', 'dcfc40.otto_q', 'dcfc40', '{"deploy_peak_fraction": 0.90}'::jsonb),
               ('dcfc40_managed_normal_2026_10_17', 'dcfc40_cab2400.managed', 'dcfc40_cab2400',
                '{"deploy_peak_fraction": 0.90, "dc_power_sharing": 1, "dc_power_managed": 1, "enforce_site_charge_cap": 0}'::jsonb))
     ) <> 4 THEN
    RAISE EXCEPTION '0732 P1: the four seed-1 cells do not carry the build-outs and dials this copies';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'seeds23_normal_2026_10_17') THEN
    RAISE EXCEPTION '0732 P2: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes)
SELECT 'seeds23_normal_2026_10_17',
       'Two more seeds for the four cells the recommendation rests on: ten, twenty, forty, and forty held at its limit',
       v.depot_id, 'normal_day', v.sim_start, 144, v.sim_min_per_tick, v.seeds[2:3], 0, 16, 5400, now(),
       '0732: arms 83 (dcfc10), 86 (dcfc20), 84 (dcfc40) and 85 (dcfc40_cab2400.managed) on value_2026_09_30''s second '
       'and third seeds, each cell its seed-1 partner''s build-out and dials, so db/checks/0451 §10''s gaps are three '
       'readings each. normal_day from 6 AM CT for 12 hours at 5 sim-minutes a tick.'
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, c.cell_code, c.ord, 'otto_q', c.buildout_code, c.fixed_params
  FROM public.ottoq_throughput_sweeps s,
       (VALUES ('dcfc10.otto_q', 1, 'dcfc10', '{"deploy_peak_fraction": 0.90}'::jsonb),
               ('dcfc20.otto_q', 2, 'dcfc20', '{"deploy_peak_fraction": 0.90}'::jsonb),
               ('dcfc40.otto_q', 3, 'dcfc40', '{"deploy_peak_fraction": 0.90}'::jsonb),
               ('dcfc40_cab2400.managed', 4, 'dcfc40_cab2400',
                '{"deploy_peak_fraction": 0.90, "dc_power_sharing": 1, "dc_power_managed": 1, "enforce_site_charge_cap": 0}'::jsonb))
         AS c(cell_code, ord, buildout_code, fixed_params)
 WHERE s.sweep_code = 'seeds23_normal_2026_10_17';

-- ── V1: the sweep is what §2 says, each cell is its seed-1 partner, and the arm would accept every dial ──
DO $verify$
DECLARE v_bad text;
BEGIN
  IF (SELECT row(scenario, ticks * sim_min_per_tick, priority, cardinality(seeds), depot_id)
        FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'seeds23_normal_2026_10_17')
     IS DISTINCT FROM row('normal_day'::text, 720::numeric, 16, 2, '11111111-1111-1111-1111-111111111111'::uuid) THEN
    RAISE EXCEPTION '0732 V1: the sweep is not normal_day, 12 hours, priority 16, two seeds, the twin depot';
  END IF;
  IF (SELECT seeds FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'seeds23_normal_2026_10_17')
     IS DISTINCT FROM (SELECT seeds[2:3] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30') THEN
    RAISE EXCEPTION '0732 V1: the seeds are not value_2026_09_30''s second and third';
  END IF;
  IF (SELECT sim_start FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'seeds23_normal_2026_10_17')
     IS DISTINCT FROM (SELECT sim_start FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_normal_2026_10_17') THEN
    RAISE EXCEPTION '0732 V1: the sim start is not the seed-1 arms''';
  END IF;
  IF (SELECT string_agg(c.cell_code, ',' ORDER BY c.ord) FROM public.ottoq_throughput_sweep_cells c
        JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'seeds23_normal_2026_10_17')
     IS DISTINCT FROM 'dcfc10.otto_q,dcfc20.otto_q,dcfc40.otto_q,dcfc40_cab2400.managed' THEN
    RAISE EXCEPTION '0732 V1: the four cells are not in the order §2 names';
  END IF;
  -- each new cell equals its seed-1 partner on build-out, seat and dials
  SELECT string_agg(n.cell_code, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells n JOIN public.ottoq_throughput_sweeps ns ON ns.sweep_id = n.sweep_id
   WHERE ns.sweep_code = 'seeds23_normal_2026_10_17'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells o JOIN public.ottoq_throughput_sweeps os ON os.sweep_id = o.sweep_id
                      WHERE os.sweep_code IN ('dcfc40_normal_2026_10_17', 'dcfc20_normal_2026_10_17',
                                              'dcfc40_power_normal_2026_10_17', 'dcfc40_managed_normal_2026_10_17')
                        AND o.cell_code = n.cell_code AND o.buildout_code = n.buildout_code AND o.seat = n.seat
                        AND o.fixed_params = n.fixed_params);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0732 V1: cells that are not their seed-1 partner: %', v_bad;
  END IF;
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code = 'seeds23_normal_2026_10_17'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0732 V1: dials the arm would refuse: %', v_bad;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0732_two_more_seeds_for_the_four_cells_the_recommendation_rests_on', false, false,
  'Rows only: sweep seeds23_normal_2026_10_17 (normal_day, value_2026_09_30''s seeds 2 and 3, four cells copying arms '
  '83, 86, 84 and 85, 12-hour days, priority 16). Read only by the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
