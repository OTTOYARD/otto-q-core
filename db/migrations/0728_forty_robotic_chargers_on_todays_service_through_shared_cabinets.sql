-- migration-version: 20261017073142
-- migration-name:    forty_robotic_chargers_on_todays_service_through_shared_cabinets
--
-- 0728  **Forty robotic chargers on today's service, through shared cabinets.** The build-out a real conversion would
--       be: every L2 space a robotic fast charger, 2,400 kW of shared DC cabinets on today's 2,500 kW service, the power
--       divided by 0726's pool. Measured tonight on one seed of each day against the grid-grown forty, with and without
--       0727's metered site gate. Research wing, rule 10.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0724's dcfc40_grid_today keeps today's 1,800 kW of DC, which is today's ten chargers' cabinets (0567: 10 x 180 kW),
--   and it measures cars waiting to start (db/checks/0451 §2). A site converted for 40 robotic chargers on a 2,500 kW
--   service would size its cabinets to the service, less what the building draws: Kempower's power unit is 200-600 kW in
--   50 kW modules and serves 1-8 charging points per single or double cabinet
--   (https://kempower.com/solution/kempower-power-unit/ and https://kempower.com/solution/distributed-charging-systems/,
--   read 2026-10-17), so twelve 200 kW units (2,400 kW) serve 40 points at three or four each. The site's own limit
--   stays 2,500 kW, and 0726's pool keeps the fast charges inside both: the cabinets' 2,400 and the grid's room after the
--   building, the sun and the battery.
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Build-out `dcfc40_cab2400`: 0724's 30 conversions, dcfc_max_concurrent_kw 2,400, service_max_kw 2,500.
--   Two sweeps, the first seed of value_2026_09_30 only, 12-hour days from 6 AM CT at 5 sim-minutes a tick (as 0724 and
--   0725), an arm budget of 5,400 s, due now, normal_day first: priority 16 for it and 17 for busy_day (both ahead of
--   0725's 19 and 0724's 20; distinct, because two sweeps inserted in one transaction share created_at, and the runner
--   would then break the tie on random sweep ids):
--     dcfc40_power_normal_2026_10_17  (normal_day)  and  dcfc40_power_busy_2026_10_17  (busy_day), three cells each:
--       ord 1  dcfc40.otto_q          every L2 converted, the grid grown (0724): power to spare, the reference
--       ord 2  dcfc40_cab2400.shared  today's service, 2,400 kW of shared cabinets: dc_power_sharing 1 and
--                                     enforce_site_charge_cap 0 (0286's switch: a shared cabinet divides its power
--                                     instead of refusing a car)
--       ord 3  dcfc40_cab2400.gated   the same hardware with the site gate kept and reading the meter:
--                                     dc_power_sharing 1, site_cap_gate_metered 1 (0727), enforce_site_charge_cap at its
--                                     default 1. The form an as-built conversion would take, because production runs
--                                     at the twin depot (8 production_live sessions there) and the gate is production's
--                                     guard on its service.
--     every cell OTTO-Q at deploy_peak_fraction 0.90. So tonight's window measures, on one seed of each day, 10 chargers
--     (0724 arm 82 and 0725's arm), 40 with power to spare, 40 on today's service, and 40 on today's service with its
--     gate. 0725's dcfc40.otto_q and 0724's seed-1 dcfc40.otto_q repeat this file's ord 1 on a later night: identical
--     configurations in different sweeps, a free cross-run reproducibility datum for the sweep arm (G140's question).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: 0726 and 0727 are applied (their dials are catalogued and their bodies carry them); 0724 and 0725 are applied.
--   P2: not already applied. V1: the build-out (40 posts, the 30 spaces, 2,400 / 2,500); each sweep's scenario, seed,
--   length, priority and three cells in order; every dial one the arm accepts.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows read only by the sweep runner.
--
-- ROLLBACK (before the sweeps have run): DELETE FROM public.ottoq_throughput_sweep_cells WHERE sweep_id IN
--   (SELECT sweep_id FROM public.ottoq_throughput_sweeps WHERE sweep_code IN ('dcfc40_power_normal_2026_10_17',
--   'dcfc40_power_busy_2026_10_17')); DELETE FROM public.ottoq_throughput_sweeps WHERE sweep_code IN (the same two);
--   DELETE FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40_cab2400';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0728_forty_robotic_chargers_on_todays_service_through_shared_cabinets'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P1: 0724-0727 applied ──
DO $premises$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key IN ('dc_power_sharing', 'site_cap_gate_metered', 'enforce_site_charge_cap')) <> 3
     OR (SELECT count(*) FROM public.ottoq_cert_lineage
          WHERE name IN ('0726_a_shared_power_cabinet_divides_its_power_and_the_twin_can_model_one',
                         '0727_the_site_power_gate_can_read_the_meter_instead_of_guessing')) <> 2
     OR (SELECT prosrc FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)'::regprocedure)
        NOT LIKE '%dc_power_sharing%'
     OR (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure)
        NOT LIKE '%site_cap_gate_metered%' THEN
    RAISE EXCEPTION '0728 P1: 0726 and 0727 are not both applied';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweeps
       WHERE sweep_code IN ('dcfc40_2026_10_17', 'dcfc40_normal_2026_10_17', 'value_2026_09_30')) <> 3
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40') THEN
    RAISE EXCEPTION '0728 P1: 0724 and 0725 (and night 2''s seeds) are not all present';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40_cab2400')
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps
                 WHERE sweep_code IN ('dcfc40_power_normal_2026_10_17', 'dcfc40_power_busy_2026_10_17')) THEN
    RAISE EXCEPTION '0728 P2: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_site_buildouts
       (buildout_code, depot_id, title, dcfc_posts, convert_l2, dcfc_max_concurrent_kw, service_max_kw, basis)
SELECT 'dcfc40_cab2400', b.depot_id, '40 robotic fast chargers on today''s service through 2,400 kW of shared cabinets',
       40, b.convert_l2, 2400, 2500,
       (b.basis - 'note' - 'enforced' - 'added_by')
         || jsonb_build_object(
              'note', 'twelve 200 kW shared cabinets (2,400 kW) for 40 points on the 2,500 kW service; run with '
                      'dc_power_sharing 1 (0726), with the site gate off or reading the meter (0727)',
              'cabinet_source', jsonb_build_object(
                  'url', 'https://kempower.com/solution/kempower-power-unit/', 'read', '2026-10-17',
                  'publisher', 'Kempower',
                  'claims', 'single cabinet 200 kW, double 400 kW, triple 450 or 600 kW, in 50 kW modules; single and '
                            'double cabinets serve 1-8 charging points, triple up to 12; power shared dynamically across '
                            'every connected satellite'),
              'enforced', 'with dc_power_sharing 1 the twin divides min(2,400, grid room) between the fast charges '
                          '(0726); with it 0 this build-out behaves as 0724''s grid cells do (db/checks/0451 §2)',
              'added_by', '0728')
  FROM public.ottoq_site_buildouts b WHERE b.buildout_code = 'dcfc40';

INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes)
SELECT x.code, x.title, v.depot_id, x.scenario, v.sim_start, 144, v.sim_min_per_tick, v.seeds[1:1], 0, x.prio, 5400,
       now(),
       '0728: 40 robotic fast chargers with power to spare, on today''s service through 2,400 kW of shared cabinets '
       '(dc_power_sharing, 0726), and the same with the site gate reading the meter (0727). 12-hour days from 6 AM CT, '
       'value_2026_09_30''s first seed, deploy_peak_fraction 0.90.'
  FROM public.ottoq_throughput_sweeps v,
       (VALUES ('dcfc40_power_normal_2026_10_17', 'normal_day', 16,
                'Forty robotic chargers, normal day: power to spare, today''s service through shared cabinets, and the same with its gate'),
               ('dcfc40_power_busy_2026_10_17', 'busy_day', 17,
                'Forty robotic chargers, busy day: power to spare, today''s service through shared cabinets, and the same with its gate'))
         AS x(code, scenario, prio, title)
 WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, c.cell_code, c.ord, 'otto_q', c.buildout_code, c.fixed_params
  FROM public.ottoq_throughput_sweeps s,
       (VALUES ('dcfc40.otto_q', 1, 'dcfc40', '{"deploy_peak_fraction": 0.90}'::jsonb),
               ('dcfc40_cab2400.shared', 2, 'dcfc40_cab2400',
                '{"deploy_peak_fraction": 0.90, "dc_power_sharing": 1, "enforce_site_charge_cap": 0}'::jsonb),
               ('dcfc40_cab2400.gated', 3, 'dcfc40_cab2400',
                '{"deploy_peak_fraction": 0.90, "dc_power_sharing": 1, "site_cap_gate_metered": 1}'::jsonb))
         AS c(cell_code, ord, buildout_code, fixed_params)
 WHERE s.sweep_code IN ('dcfc40_power_normal_2026_10_17', 'dcfc40_power_busy_2026_10_17');

-- ── V1 ──
DO $verify$
DECLARE v_bad text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts b JOIN public.ottoq_site_buildouts d ON d.buildout_code = 'dcfc40'
                  WHERE b.buildout_code = 'dcfc40_cab2400' AND b.dcfc_posts = 40 AND b.convert_l2 = d.convert_l2
                    AND b.dcfc_max_concurrent_kw = 2400 AND b.service_max_kw = 2500) THEN
    RAISE EXCEPTION '0728 V1: dcfc40_cab2400 is not 40 posts on dcfc40''s spaces at 2,400 / 2,500';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweeps s
       WHERE s.sweep_code IN ('dcfc40_power_normal_2026_10_17', 'dcfc40_power_busy_2026_10_17')
         AND s.priority = CASE WHEN s.sweep_code LIKE '%normal%' THEN 16 ELSE 17 END
         AND cardinality(s.seeds) = 1 AND s.ticks * s.sim_min_per_tick = 720
         AND s.seeds[1] = (SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30')
         AND s.scenario = CASE WHEN s.sweep_code LIKE '%normal%' THEN 'normal_day' ELSE 'busy_day' END) <> 2 THEN
    RAISE EXCEPTION '0728 V1: the two sweeps are not the scenario, seed, length and priority §2 names';
  END IF;
  IF (SELECT count(DISTINCT x.cells) FROM (
        SELECT string_agg(c.cell_code, ',' ORDER BY c.ord) AS cells FROM public.ottoq_throughput_sweep_cells c
          JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
         WHERE s.sweep_code IN ('dcfc40_power_normal_2026_10_17', 'dcfc40_power_busy_2026_10_17') GROUP BY s.sweep_id) x) <> 1
     OR (SELECT string_agg(c.cell_code, ',' ORDER BY c.ord) FROM public.ottoq_throughput_sweep_cells c
           JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'dcfc40_power_normal_2026_10_17')
        IS DISTINCT FROM 'dcfc40.otto_q,dcfc40_cab2400.shared,dcfc40_cab2400.gated' THEN
    RAISE EXCEPTION '0728 V1: the cells are not the three §2 names, in order, in both sweeps';
  END IF;
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code IN ('dcfc40_power_normal_2026_10_17', 'dcfc40_power_busy_2026_10_17')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0728 V1: dials the arm would refuse: %', v_bad;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0728_forty_robotic_chargers_on_todays_service_through_shared_cabinets', false, false,
  'Rows only: build-out dcfc40_cab2400 (40 robotic fast chargers, 2,400 kW of shared cabinets, 2,500 kW service) and '
  'two one-seed sweeps at priorities 16 and 17 (normal_day, then busy_day): the grid-grown 40, the shared 40 with the gate off, and '
  'the shared 40 with the gate reading the meter. Read only by the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 07:31:42 UTC (2:31 AM CT), ledger version 20261017073142 ═════════════════════════════════════
--
--   Through apply_migration, after 0726 (07:26:52) and 0727 (07:29:28), with the sweep runner paused and nothing in
--   flight. Executable part 8,292 characters, md5 98c08bf1ae36888fe79f8bdecf87db6c, equal to the ledger's statements[1]
--   read back. Dry-run first in a rolled-back transaction against the catalog 0726 and 0727 had just made (APPLYING.md
--   3b(ii): its P1 reads both): every block passed; read back, the build-out at 40 posts on dcfc40's 30 converted L2
--   spaces, 2,400 / 2,500 kW, with its cabinet source; both sweeps active at 16 and 17; six cells. Before the apply the
--   dials were checked at the scope an arm writes them: ottoq_decide_tick reads enforce_site_charge_cap and
--   site_cap_gate_metered through ottoq_policy_get(p_sim_run_id, ...), and the charge step reads dc_power_sharing the
--   same way, so a cell's run-scoped value is the one each reads. The runner was re-enabled at 07:31:57 UTC
--   (throughput_sweep_runner_enabled 1, research_wing:resume_after_0726_0728).
--
--   One overlap, kept on purpose: dcfc40_normal_2026_10_17 (0725, priority 19) also holds dcfc40.otto_q on normal_day at
--   the same seed, so when the runner reaches it, it runs this file's first cell again. Two one-transaction arms of one
--   cell on one engine are a replicate: if they agree byte for byte the comparison carries no run-to-run noise, and if
--   they do not, their gap is the noise floor every paired claim from these sweeps must clear.
