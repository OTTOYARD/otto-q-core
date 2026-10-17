-- migration-version: PENDING
-- migration-name:    forty_fast_chargers_on_a_normal_day_where_the_service_bays_are_not_the_wall
--
-- 0725  **Forty fast chargers on a normal day, where the service bays are not the wall.** 0724's question asked again on
--       the scenario whose maintenance runs at the need profile's own pace, so what more chargers buy is not hidden
--       behind two service bays. Research wing, rule 10: it measures, and a result is a recommendation.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0724's sweep runs on busy_day, and busy_day is a service stress test, not a charging one (ottoq_sim_scenarios, read
--   2026-10-17 06:41 UTC): `pm_interval_km_scale` 0.010 (maintenance a hundred times as often as the need profile's
--   6,500-9,500 km), compressed calibration, `dtc_rate_multiplier` 7.0 and an 85% soiled wear phase. Since 0715 no car
--   leaves with that work open (rule 9), and db/checks/0450 measured the result: on busy_day the two service bays become
--   the depot's wall (departures 162 -> 115 against the same boot draw before 0715; 87 maintenance jobs pending at the
--   stop). value_2026_09_30's own 24-hour arm on 20 fast chargers (arm 77, read 2026-10-17 06:38 UTC) met 129.3 of the
--   1,551 car-hours the work side asked for (unmet 91.7%) while its chargers were busy 51% of the time. A charger
--   comparison on busy_day therefore measures chargers behind a closed door. normal_day has neither the compression nor
--   the fault multiplier: dispatch at 1.0 and a 0.90 deployed target, the same 0.90 every cell fixes.
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Sweep `dcfc40_normal_2026_10_17`: normal_day from 6 AM CT for 12 hours at 5 sim-minutes a tick (144 ticks), the
--   first of value_2026_09_30's seeds only (one seed tonight; more seeds are a later file), no replicates, priority 19,
--   so the runner takes its four arms before 0724's remaining ones; an arm budget of 5,400 s, due now. Four cells, all
--   OTTO-Q at deploy_peak_fraction 0.90, on 0724's and 0567's build-outs:
--     ord 1  dcfc10.otto_q               the depot as built
--     ord 2  dcfc40.otto_q               every L2 converted, the grid grown
--     ord 3  dcfc40_grid_today.otto_q    every L2 converted, today's grid
--     ord 4  dcfc20.otto_q               0567's middle point
--   The power-limited cell carries 0724 §2's caveat unchanged: the twin defers a charge at admission and does not share
--   power between chargers, so it bounds a shared-cabinet site from below (db/checks/0451 §2).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: 0724 is applied (its build-outs exist), normal_day is an available scenario, and value_2026_09_30's seeds exist.
--   P2: not already applied. V1: the sweep is normal_day, one seed (value_2026_09_30's first), 12 hours, priority 19,
--   four cells in the order above, every dial one the arm accepts.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows in the sweep tables, read only by the sweep runner.
--
-- ROLLBACK (before the sweep has run): DELETE FROM public.ottoq_throughput_sweep_cells WHERE sweep_id =
--   (SELECT sweep_id FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_normal_2026_10_17');
--   DELETE FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_normal_2026_10_17';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0725_forty_fast_chargers_on_a_normal_day_where_the_service_bays_are_not_the_wall'.
--   Once it has run, its arms are evidence and stay; set the sweep's status to 'concluded' instead.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P1: 0724's build-outs, the scenario, night 2's seeds ──
DO $premises$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_site_buildouts
       WHERE buildout_code IN ('dcfc10', 'dcfc20', 'dcfc40', 'dcfc40_grid_today')) <> 4 THEN
    RAISE EXCEPTION '0725 P1: 0724''s build-outs (and 0567''s dcfc10/dcfc20) are not all present';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_scenarios WHERE scenario_code = 'normal_day' AND status = 'available') THEN
    RAISE EXCEPTION '0725 P1: normal_day is not an available scenario';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30'
                  AND cardinality(seeds) = 3) THEN
    RAISE EXCEPTION '0725 P1: value_2026_09_30 and its three seeds are missing';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_normal_2026_10_17') THEN
    RAISE EXCEPTION '0725 P2: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes)
SELECT 'dcfc40_normal_2026_10_17',
       'Every L2 space a robotic fast charger, on a normal day: 40 against 10 and 20, on a grid grown with them and on today''s',
       v.depot_id, 'normal_day', v.sim_start, 144, v.sim_min_per_tick, v.seeds[1:1], 0, 19, 5400, now(),
       '0725, 0724''s question on the scenario whose maintenance runs at the need profile''s pace (busy_day compresses it a '
       'hundredfold and the two service bays become the wall, db/checks/0450). normal_day from 6 AM CT for 12 hours at 5 '
       'sim-minutes a tick, value_2026_09_30''s first seed, deploy_peak_fraction 0.90.'
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, c.cell_code, c.ord, 'otto_q', c.buildout_code, '{"deploy_peak_fraction": 0.90}'::jsonb
  FROM public.ottoq_throughput_sweeps s,
       (VALUES ('dcfc10.otto_q',            1, 'dcfc10'),
               ('dcfc40.otto_q',            2, 'dcfc40'),
               ('dcfc40_grid_today.otto_q', 3, 'dcfc40_grid_today'),
               ('dcfc20.otto_q',            4, 'dcfc20'))
         AS c(cell_code, ord, buildout_code)
 WHERE s.sweep_code = 'dcfc40_normal_2026_10_17';

-- ── V1: the sweep is what §2 says, and the arm would accept every dial ──
DO $verify$
DECLARE v_bad text;
BEGIN
  IF (SELECT row(scenario, ticks * sim_min_per_tick, priority, cardinality(seeds))
        FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_normal_2026_10_17')
     IS DISTINCT FROM row('normal_day'::text, 720::numeric, 19, 1) THEN
    RAISE EXCEPTION '0725 V1: the sweep is not normal_day, 12 hours, priority 19, one seed';
  END IF;
  IF (SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_normal_2026_10_17')
     IS DISTINCT FROM (SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30') THEN
    RAISE EXCEPTION '0725 V1: the seed is not value_2026_09_30''s first';
  END IF;
  IF (SELECT string_agg(c.cell_code, ',' ORDER BY c.ord) FROM public.ottoq_throughput_sweep_cells c
        JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'dcfc40_normal_2026_10_17')
     IS DISTINCT FROM 'dcfc10.otto_q,dcfc40.otto_q,dcfc40_grid_today.otto_q,dcfc20.otto_q' THEN
    RAISE EXCEPTION '0725 V1: the four cells are not in the order §2 names';
  END IF;
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code = 'dcfc40_normal_2026_10_17'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0725 V1: dials the arm would refuse: %', v_bad;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0725_forty_fast_chargers_on_a_normal_day_where_the_service_bays_are_not_the_wall', false, false,
  'Rows only: sweep dcfc40_normal_2026_10_17 (normal_day, four cells at 10, 40 grown, 40 on today''s grid and 20 '
  'robotic fast chargers, one seed, 12-hour days). Read only by the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
