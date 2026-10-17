-- migration-version: PENDING
-- migration-name:    the_same_morning_at_half_the_tick_to_measure_what_the_tick_costs
--
-- 0734  **The same morning at half the tick, to measure what the tick costs.** The depot as built (dcfc10) on the normal
--       day's first six hours, run twice on the same seed: once at 5 sim-minutes a tick, as every sweep has run, and
--       once at 2.5. Research wing, rule 10: it measures, and a result is a recommendation.
--
-- ══ §1 WHY (G449, db/checks/0451 §12) ═════════════════════════════════════════════════════════════════════════════════
--
--   Every sweep on record ran at 5 sim-minutes a tick (15 sweeps, 87 arms), and at that tick a fast-charger handover
--   takes two ticks however short the physical work. On arm 83 (dcfc10, normal day, seed 1), 67 fast-charger handovers
--   had a car waiting for a fast charger; 58 took exactly 10 minutes and none took fewer, and they left 13.5
--   charger-hours idle against 82.7 hours of charging. Traced on one: the arm's demate is due 2 minutes after the charge
--   ends, the next tick clears it and frees the stall, and the next car is started a tick after that. A robotic handover
--   (unlatch, drive off, drive in, mate) is a few minutes of physical work, and production ticks every 120 seconds. If
--   the 5-minute tick inflates the handover, it penalizes a depot with a queue (the depot as built) and not one without
--   (forty fast chargers, 41% busy), so it would overstate what the extra posts buy (0451 §10 points 1-2).
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Two sweeps, one cell each, dcfc10.otto_q at deploy_peak_fraction 0.90 (arm 83's cell), normal_day from 6 AM CT,
--   value_2026_09_30's first seed, priority 15 (after 0733's arm), arm budget 5,400 s, due now:
--     tick5_morning_2026_10_17    72 ticks of 5 sim-minutes   (6 hours)
--     tick25_morning_2026_10_17  144 ticks of 2.5 sim-minutes (6 hours)
--   The pair differs only in the tick, so the gap between them is what the 5-minute tick costs this depot over its
--   busiest six hours: fast-charger handovers with a car waiting, idle charger-hours, cars served and car-hours met.
--   About 12 and 35 minutes of wall time (144-tick normal-day arms took 1,860-2,288 s).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: dcfc10, normal_day, value_2026_09_30's seeds and 0733's sweep exist; arm 83's cell carries the dial copied. P2:
--   not already applied. V1: both sweeps 6 hours of normal_day from value_2026_09_30's sim start on its first seed,
--   priority 15, ticks 72 x 5 and 144 x 2.5, one cell each equal to arm 83's cell, every dial one the arm accepts; and
--   the arm's clock formula (time_scale = 2 x sim_min_per_tick on a 30-second interval) gives 2.5 minutes exactly.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows in the sweep tables, read only by the sweep runner.
--
-- ROLLBACK (before the sweeps have run): DELETE their cell and sweep rows; once run, their arms are evidence and stay.
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0734_the_same_morning_at_half_the_tick_to_measure_what_the_tick_costs'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P1: what the cells copy ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc10') THEN
    RAISE EXCEPTION '0734 P1: build-out dcfc10 is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_scenarios WHERE scenario_code = 'normal_day' AND status = 'available') THEN
    RAISE EXCEPTION '0734 P1: normal_day is not an available scenario';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30'
                  AND cardinality(seeds) = 3) THEN
    RAISE EXCEPTION '0734 P1: value_2026_09_30 and its three seeds are missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'firstreading_normal_2026_10_17') THEN
    RAISE EXCEPTION '0734 P1: 0733 is not applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc40_normal_2026_10_17' AND c.cell_code = 'dcfc10.otto_q'
                    AND c.buildout_code = 'dcfc10' AND c.fixed_params = '{"deploy_peak_fraction": 0.90}'::jsonb) THEN
    RAISE EXCEPTION '0734 P1: arm 83''s cell does not carry the build-out and dial this copies';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps
              WHERE sweep_code IN ('tick5_morning_2026_10_17', 'tick25_morning_2026_10_17')) THEN
    RAISE EXCEPTION '0734 P2: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes)
SELECT t.sweep_code, t.title, v.depot_id, 'normal_day', v.sim_start, t.ticks, t.smpt, v.seeds[1:1], 0, 15, 5400, now(),
       '0734 (G449): the depot as built (dcfc10.otto_q, arm 83''s cell) over the normal day''s first six hours on '
       'value_2026_09_30''s first seed, run at 5 and at 2.5 sim-minutes a tick, so the pair''s gap is what the 5-minute '
       'tick costs a depot with a queue.'
  FROM public.ottoq_throughput_sweeps v,
       (VALUES ('tick5_morning_2026_10_17', 'The depot as built over the normal morning at 5 sim-minutes a tick', 72, 5::numeric, 1),
               ('tick25_morning_2026_10_17', 'The depot as built over the normal morning at 2.5 sim-minutes a tick', 144, 2.5::numeric, 2))
         AS t(sweep_code, title, ticks, smpt, ord)
 WHERE v.sweep_code = 'value_2026_09_30'
 ORDER BY t.ord;

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc10.otto_q', 1, 'otto_q', 'dcfc10', '{"deploy_peak_fraction": 0.90}'::jsonb
  FROM public.ottoq_throughput_sweeps s
 WHERE s.sweep_code IN ('tick5_morning_2026_10_17', 'tick25_morning_2026_10_17');

-- ── V1: two six-hour mornings that differ only in the tick ──
DO $verify$
DECLARE v_bad text;
BEGIN
  IF (SELECT string_agg(s.sweep_code || ':' || s.ticks || 'x' || s.sim_min_per_tick || '=' || (s.ticks * s.sim_min_per_tick)
                        || ':' || s.priority || ':' || cardinality(s.seeds), ',' ORDER BY s.sweep_code)
        FROM public.ottoq_throughput_sweeps s
       WHERE s.sweep_code IN ('tick5_morning_2026_10_17', 'tick25_morning_2026_10_17') AND s.scenario = 'normal_day')
     IS DISTINCT FROM 'tick25_morning_2026_10_17:144x2.5=360.0:15:1,tick5_morning_2026_10_17:72x5=360:15:1' THEN
    RAISE EXCEPTION '0734 V1: the two sweeps are not 144 x 2.5 and 72 x 5 sim-minutes of normal_day at priority 15, one seed';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps s, public.ottoq_throughput_sweeps v
              WHERE s.sweep_code IN ('tick5_morning_2026_10_17', 'tick25_morning_2026_10_17') AND v.sweep_code = 'value_2026_09_30'
                AND (s.seeds[1] IS DISTINCT FROM v.seeds[1] OR s.sim_start IS DISTINCT FROM v.sim_start
                     OR s.depot_id IS DISTINCT FROM v.depot_id)) THEN
    RAISE EXCEPTION '0734 V1: a sweep is not on value_2026_09_30''s first seed, sim start and depot';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code IN ('tick5_morning_2026_10_17', 'tick25_morning_2026_10_17')
         AND c.cell_code = 'dcfc10.otto_q' AND c.buildout_code = 'dcfc10' AND c.seat = 'otto_q'
         AND c.fixed_params = '{"deploy_peak_fraction": 0.90}'::jsonb) <> 2
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
          WHERE s.sweep_code IN ('tick5_morning_2026_10_17', 'tick25_morning_2026_10_17')) <> 2 THEN
    RAISE EXCEPTION '0734 V1: the sweeps do not hold exactly arm 83''s cell, once each';
  END IF;
  -- the arm sets time_scale = 2 * sim_min_per_tick on a 30-second interval (ottoq_throughput_sweep_arm)
  IF (SELECT 30 * 2 * s.sim_min_per_tick FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'tick25_morning_2026_10_17')
     IS DISTINCT FROM 150::numeric THEN
    RAISE EXCEPTION '0734 V1: the 2.5-minute sweep would not advance 150 sim-seconds a tick';
  END IF;
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code IN ('tick5_morning_2026_10_17', 'tick25_morning_2026_10_17')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0734 V1: dials the arm would refuse: %', v_bad;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0734_the_same_morning_at_half_the_tick_to_measure_what_the_tick_costs', false, false,
  'Rows only: sweeps tick5_morning_2026_10_17 (72 x 5 sim-minutes) and tick25_morning_2026_10_17 (144 x 2.5), each '
  'arm 83''s cell (dcfc10.otto_q) on normal_day''s first six hours, value_2026_09_30''s first seed, priority 15. Read '
  'only by the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
