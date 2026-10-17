-- migration-version: PENDING
-- migration-name:    forty_robotic_chargers_on_todays_service_through_shared_cabinets
--
-- 0727  **Forty robotic chargers on today's service, through shared cabinets.** The build-out a real conversion would
--       be: every L2 space a robotic fast charger, 2,400 kW of shared DC cabinets on today's 2,500 kW service, the power
--       divided by 0726's pool. One cell of it on each of tonight's two days, run right after the grid-grown 40.
--       Research wing, rule 10.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0724's dcfc40_grid_today keeps today's 1,800 kW of DC, which is today's ten chargers' cabinets (0567: 10 x 180 kW),
--   and it measures cars waiting to start (0451 §2). A site converted for 40 robotic chargers on a 2,500 kW service would
--   size its cabinets to the service, less what the building draws: Kempower's power unit is 200-600 kW in 50 kW
--   modules and serves 1-8 charging points per single or double cabinet (https://kempower.com/solution/kempower-power-unit/
--   and https://kempower.com/solution/distributed-charging-systems/, read 2026-10-17), so twelve 200 kW units (2,400 kW)
--   serve 40 points at three or four each. The site's own limit stays 2,500 kW, and 0726's pool keeps the fast charges
--   inside both: the cabinets' 2,400 and the grid's room after the building, the sun and the battery.
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Build-out `dcfc40_cab2400`: 0724's 30 conversions, dcfc_max_concurrent_kw 2,400, service_max_kw 2,500.
--   Cell `dcfc40_cab2400.shared`, OTTO-Q, dials deploy_peak_fraction 0.90 (as every cell), dc_power_sharing 1 (0726) and
--   enforce_site_charge_cap 0 (0286's switch: a shared cabinet divides its power instead of refusing a car), in both
--   dcfc40_normal_2026_10_17 (0725) and dcfc40_2026_10_17 (0724), as ord 3 of each: right after the grid-grown 40, so
--   tonight measures, on one seed of each day, 10 chargers, 40 with power to spare, and 40 on today's service. Every
--   later cell of each sweep moves down one ord, in its order; nothing that has run moves (the two ord-1 cells ran).
--   0725 V1 asserted the old order of its four cells; this file supersedes that assertion, with the reason above.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: 0726 is applied (the dial is catalogued and the charge step reads it); 0724 and 0725 are applied; the two sweeps
--   have no arm recorded for any cell that moves. P2: not already applied. V1: the build-out (40 posts, the 30 spaces,
--   2,400 / 2,500); each sweep's cells in their new order; every dial one the arm accepts.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows read only by the sweep runner.
--
-- ROLLBACK (before the new cells have run): DELETE FROM public.ottoq_throughput_sweep_cells
--    WHERE cell_code = 'dcfc40_cab2400.shared'; then restore each sweep's ord order from 0724 §2 and 0725 §2;
--   DELETE FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40_cab2400';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0727_forty_robotic_chargers_on_todays_service_through_shared_cabinets'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P1: 0724-0726 applied, and nothing that moves has run ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_sharing')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                     WHERE name = '0726_a_shared_power_cabinet_divides_its_power_and_the_twin_can_model_one')
     OR (SELECT prosrc FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)'::regprocedure)
        NOT LIKE '%dc_power_sharing%' THEN
    RAISE EXCEPTION '0727 P1: 0726 is not applied';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweeps
       WHERE sweep_code IN ('dcfc40_2026_10_17', 'dcfc40_normal_2026_10_17')) <> 2
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40') THEN
    RAISE EXCEPTION '0727 P1: 0724 and 0725 are not both applied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweep_cells c USING (cell_id)
              JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = c.sweep_id
             WHERE s.sweep_code IN ('dcfc40_2026_10_17', 'dcfc40_normal_2026_10_17') AND c.ord >= 3) THEN
    RAISE EXCEPTION '0727 P1: a cell at ord 3 or later has already run; its place cannot move';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40_cab2400')
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells WHERE cell_code = 'dcfc40_cab2400.shared') THEN
    RAISE EXCEPTION '0727 P2: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_site_buildouts
       (buildout_code, depot_id, title, dcfc_posts, convert_l2, dcfc_max_concurrent_kw, service_max_kw, basis)
SELECT 'dcfc40_cab2400', b.depot_id, '40 robotic fast chargers on today''s service through 2,400 kW of shared cabinets',
       40, b.convert_l2, 2400, 2500,
       (b.basis - 'note' - 'enforced' - 'added_by')
         || jsonb_build_object(
              'note', 'twelve 200 kW shared cabinets (2,400 kW) for 40 points on the 2,500 kW service; run with '
                      'dc_power_sharing 1 and enforce_site_charge_cap 0 (0726, 0727)',
              'cabinet_source', jsonb_build_object(
                  'url', 'https://kempower.com/solution/kempower-power-unit/', 'read', '2026-10-17',
                  'publisher', 'Kempower',
                  'claims', 'single cabinet 200 kW, double 400 kW, triple 450 or 600 kW, in 50 kW modules; single and '
                            'double cabinets serve 1-8 charging points, triple up to 12; power shared dynamically across '
                            'every connected satellite'),
              'enforced', 'with dc_power_sharing 1 the twin divides min(2,400, grid room) between the fast charges '
                          '(0726); with it 0 this build-out behaves as 0724''s grid cells do (0451 §2)',
              'added_by', '0727')
  FROM public.ottoq_site_buildouts b WHERE b.buildout_code = 'dcfc40';

-- each sweep's ord 3 and later move down one, highest first (sweep_id, ord is unique)
DO $reorder$
DECLARE c record;
BEGIN
  FOR c IN SELECT cl.cell_id, cl.ord FROM public.ottoq_throughput_sweep_cells cl
             JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = cl.sweep_id
            WHERE s.sweep_code IN ('dcfc40_2026_10_17', 'dcfc40_normal_2026_10_17') AND cl.ord >= 3
            ORDER BY cl.ord DESC LOOP
    UPDATE public.ottoq_throughput_sweep_cells SET ord = c.ord + 1 WHERE cell_id = c.cell_id;
  END LOOP;
END $reorder$;

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40_cab2400.shared', 3, 'otto_q', 'dcfc40_cab2400',
       '{"deploy_peak_fraction": 0.90, "dc_power_sharing": 1, "enforce_site_charge_cap": 0}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code IN ('dcfc40_2026_10_17', 'dcfc40_normal_2026_10_17');

-- ── V1 ──
DO $verify$
DECLARE v_bad text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts b JOIN public.ottoq_site_buildouts d ON d.buildout_code = 'dcfc40'
                  WHERE b.buildout_code = 'dcfc40_cab2400' AND b.dcfc_posts = 40 AND b.convert_l2 = d.convert_l2
                    AND b.dcfc_max_concurrent_kw = 2400 AND b.service_max_kw = 2500) THEN
    RAISE EXCEPTION '0727 V1: dcfc40_cab2400 is not 40 posts on dcfc40''s spaces at 2,400 / 2,500';
  END IF;
  IF (SELECT string_agg(c.cell_code, ',' ORDER BY c.ord) FROM public.ottoq_throughput_sweep_cells c
        JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'dcfc40_normal_2026_10_17')
     IS DISTINCT FROM 'dcfc10.otto_q,dcfc40.otto_q,dcfc40_cab2400.shared,dcfc40_grid_today.otto_q,dcfc20.otto_q' THEN
    RAISE EXCEPTION '0727 V1: the normal-day sweep''s order is not the one §2 names';
  END IF;
  IF (SELECT string_agg(c.cell_code, ',' ORDER BY c.ord) FROM public.ottoq_throughput_sweep_cells c
        JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'dcfc40_2026_10_17')
     IS DISTINCT FROM 'dcfc10.otto_q,dcfc40.otto_q,dcfc40_cab2400.shared,dcfc40_grid_today.otto_q,dcfc20.otto_q,'
                      'dcfc40_grid_dcfc20.otto_q,dcfc40.fifo,dcfc40_grid_today.fifo' THEN
    RAISE EXCEPTION '0727 V1: the busy-day sweep''s order is not the one §2 names';
  END IF;
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code IN ('dcfc40_2026_10_17', 'dcfc40_normal_2026_10_17')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0727 V1: dials the arm would refuse: %', v_bad;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0727_forty_robotic_chargers_on_todays_service_through_shared_cabinets', false, false,
  'Rows only: build-out dcfc40_cab2400 (40 robotic fast chargers, 2,400 kW of shared cabinets, 2,500 kW service) and '
  'cell dcfc40_cab2400.shared (dc_power_sharing 1, enforce_site_charge_cap 0) at ord 3 of 0724''s and 0725''s sweeps, '
  'later cells moved down one. Read only by the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
