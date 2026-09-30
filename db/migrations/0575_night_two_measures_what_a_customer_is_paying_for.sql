-- migration-version: 20260930115452
-- migration-name:    night_two_measures_what_a_customer_is_paying_for
--
-- 0575  **Night 2 measures the three things a customer is paying for, on the calibrated twin.** One overnight sweep of
--       24-hour days: OTTO-Q against first-come-first-served, each with OTTO-Q's energy planning on and off, at 10 and
--       20 robotic fast chargers. Research wing, rule 10: it measures, and a result is a recommendation.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-09-29, 8:20 PM CT: "I more so care about energy savings (through Bess, solar, and forward
--   planning/scheduling) and less charging stations and footprint for maximum cars to be able to receive full services
--   throughout the day WHILE avoiding massive downtime and revenue lost, and then finally, vehicle revenue and uptime".
--   Three questions, and each needs a comparison that changes one thing:
--     - the power bill: the same depot with OTTO-Q's energy planning on and off. Off is `energy_orchestration_enabled`
--       = 0, the engine's own switch: the planner never runs, so each car charges at full power when it plugs in and the
--       battery is not dispatched (the industry's "unmanaged charging"). On is the planner the twin runs today
--       (`energy_reserve_shave` = 1 at the depot since 2026-09-26, with the day plan).
--     - chargers and footprint: OTTO-Q's charger assignment against first-come-first-served (seat `fifo`), at 10 and 20
--       chargers, with the same energy planning in both.
--     - uptime and revenue: the same arms. Demand met, and time cars wait.
--   Crossing the two gives four cells per charger count, so the Value tab can also say what OTTO-Q is worth against a
--   plain depot with neither: first-come-first-served with the planner off.
--   24-hour days, not night 1's 12, so the overnight full-service cars, off-peak hours and the whole day's demand peak
--   are inside the day.
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Sweep `value_2026_09_30`: busy_day from 6 AM CT for 24 hours at 5 sim-minutes a tick (288 ticks), night 1's first
--   three seeds (common random numbers with night 1), priority 50 (before night 2's charge-order sweep at 100), due at
--   11 PM CT on 2026-09-30. Eight cells, every one at `deploy_peak_fraction` 0.90 as night 1:
--     dcfcN.otto_q              OTTO-Q, planner on        treatment of dcfcN.otto_q.energy_off
--     dcfcN.otto_q.energy_off   OTTO-Q, planner off       control
--     dcfcN.fifo                first-come, planner on    treatment of dcfcN.fifo.energy_off
--     dcfcN.fifo.energy_off     first-come, planner off   control (the plain depot)
--   for N = 10 and 20. So 0571's contrasts hold the energy comparison under each seat, and 0568's pairs hold the seat
--   comparison under each energy setting. The runner goes seed by seed, so a night that ends early leaves whole seeds.
--   Within a seed the four HEADLINE cells run first: OTTO-Q (ord 1, 3) and the plain depot (ord 2, 4) at 10 and at 20
--   chargers. The four split cells follow (ord 5-8). Night 1 measured about 20 minutes per 12-hour arm, with tick cost
--   rising through the day (db/checks/0413 §7). A 24-hour arm is estimated at 50-80 minutes, so one night fits about
--   6-8 of the 24 arms. This order puts OTTO-Q against the plain depot at both charger counts into the first night.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: 0571 (control cells) is applied, and so are 0573 (charge times) and 0574 (the price of power). Night 2 must
--   measure the calibrated twin, and a sweep defined before them would run on whatever engine exists at 11 PM. Night 1
--   and its seeds exist, and `energy_orchestration_enabled` is catalogued 0..1. P2: not already applied. V1: eight cells,
--   four contrasts on the right controls, night 1's first three seeds, 288 ticks, and every dial one the arm accepts.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows in the sweep tables, read only by the sweep runner.
--
-- ROLLBACK (before the sweep has run): DELETE FROM public.ottoq_throughput_sweep_cells WHERE sweep_id =
--   (SELECT sweep_id FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30') AND control_cell_code IS NOT NULL;
--   then the same without the last condition; DELETE FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0575_night_two_measures_what_a_customer_is_paying_for'.
--   Once it has run, its arms are evidence and stay; set the sweep's status to 'concluded' instead.

BEGIN;

-- ── P1: the machinery, the calibration, night 1, the switch ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                  AND table_name = 'ottoq_throughput_sweep_cells' AND column_name = 'control_cell_code') THEN
    RAISE EXCEPTION '0575 P1: 0571''s control cells are missing; apply 0571 first';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_cert_lineage
       WHERE name IN ('0573_every_charge_and_service_takes_the_time_public_data_says',
                      '0574_the_twin_prices_power_at_nashvilles_published_rate')) <> 2 THEN
    RAISE EXCEPTION '0575 P1: 0573 and 0574 are not both applied; night 2 must measure the calibrated twin';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'frontier_2026_09_29'
                  AND cardinality(seeds) >= 3) THEN
    RAISE EXCEPTION '0575 P1: night 1 (frontier_2026_09_29) and its seeds are missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'energy_orchestration_enabled'
                  AND min_value <= 0 AND max_value >= 1) THEN
    RAISE EXCEPTION '0575 P1: energy_orchestration_enabled is not catalogued 0..1';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30') THEN
    RAISE EXCEPTION '0575 P2: value_2026_09_30 already exists';
  END IF;
END $once$;

WITH sw AS (
  INSERT INTO public.ottoq_throughput_sweeps
         (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority, run_after, notes)
  SELECT 'value_2026_09_30',
         'Value, night 2: OTTO-Q against first-come-first-served, with OTTO-Q''s energy planning on and off, 24-hour days at 10 and 20 robotic fast chargers',
         f.depot_id, f.scenario, f.sim_start, 288, f.sim_min_per_tick, f.seeds[1:3], 0, 50, '2026-10-01 04:00:00+00',
         'Night 2 (0575), on the calibrated twin (0573 charge and service times, 0574 NES TGSA-3 prices). busy_day from '
         '6 AM CT for 24 hours at 5 sim-minutes a tick, night 1''s first three seeds, deploy_peak_fraction 0.90. Energy '
         'off is energy_orchestration_enabled = 0: no planner, full power on plug-in, battery not dispatched. The seat '
         'fifo replaces OTTO-Q''s charger assignment only.'
    FROM public.ottoq_throughput_sweeps f WHERE f.sweep_code = 'frontier_2026_09_29'
  RETURNING sweep_id
)
-- the controls first, so the trigger can check each treatment against its control
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT sw.sweep_id, c.cell_code, c.ord, c.seat, c.buildout_code, c.fixed_params
  FROM sw, (VALUES
    ('dcfc10.otto_q.energy_off', 5, 'otto_q', 'dcfc10', '{"deploy_peak_fraction": 0.90, "energy_orchestration_enabled": 0}'::jsonb),
    ('dcfc10.fifo.energy_off',   2, 'fifo',   'dcfc10', '{"deploy_peak_fraction": 0.90, "energy_orchestration_enabled": 0}'::jsonb),
    ('dcfc20.otto_q.energy_off', 7, 'otto_q', 'dcfc20', '{"deploy_peak_fraction": 0.90, "energy_orchestration_enabled": 0}'::jsonb),
    ('dcfc20.fifo.energy_off',   4, 'fifo',   'dcfc20', '{"deploy_peak_fraction": 0.90, "energy_orchestration_enabled": 0}'::jsonb))
    AS c(cell_code, ord, seat, buildout_code, fixed_params);

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params, control_cell_code)
SELECT s.sweep_id, c.cell_code, c.ord, c.seat, c.buildout_code, c.fixed_params, c.control
  FROM public.ottoq_throughput_sweeps s,
       (VALUES ('dcfc10.otto_q', 1, 'otto_q', 'dcfc10', '{"deploy_peak_fraction": 0.90}'::jsonb, 'dcfc10.otto_q.energy_off'),
               ('dcfc10.fifo',   6, 'fifo',   'dcfc10', '{"deploy_peak_fraction": 0.90}'::jsonb, 'dcfc10.fifo.energy_off'),
               ('dcfc20.otto_q', 3, 'otto_q', 'dcfc20', '{"deploy_peak_fraction": 0.90}'::jsonb, 'dcfc20.otto_q.energy_off'),
               ('dcfc20.fifo',   8, 'fifo',   'dcfc20', '{"deploy_peak_fraction": 0.90}'::jsonb, 'dcfc20.fifo.energy_off'))
         AS c(cell_code, ord, seat, buildout_code, fixed_params, control)
 WHERE s.sweep_code = 'value_2026_09_30';

-- ── V1: night 2 is what §2 says, and the arm would accept every dial ──
DO $verify$
DECLARE v_bad text;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'value_2026_09_30') <> 8 THEN
    RAISE EXCEPTION '0575 V1: value_2026_09_30 does not have eight cells';
  END IF;
  -- each treatment names the energy-off cell of its own seat and build-out
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'value_2026_09_30' AND c.control_cell_code = c.cell_code || '.energy_off'
         AND c.fixed_params = '{"deploy_peak_fraction": 0.90}'::jsonb) <> 4 THEN
    RAISE EXCEPTION '0575 V1: the four energy contrasts are not each on their own seat''s energy-off cell';
  END IF;
  -- the headline first: OTTO-Q and the plain depot at 10 and 20 chargers are ords 1-4
  IF (SELECT string_agg(c.cell_code, ',' ORDER BY c.ord) FROM public.ottoq_throughput_sweep_cells c
        JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'value_2026_09_30' AND c.ord <= 4)
     IS DISTINCT FROM 'dcfc10.otto_q,dcfc10.fifo.energy_off,dcfc20.otto_q,dcfc20.fifo.energy_off' THEN
    RAISE EXCEPTION '0575 V1: the four headline cells do not run first';
  END IF;
  IF (SELECT seeds FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30')
       IS DISTINCT FROM (SELECT seeds[1:3] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'frontier_2026_09_29')
     OR (SELECT ticks * sim_min_per_tick FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30') <> 1440 THEN
    RAISE EXCEPTION '0575 V1: night 2 is not night 1''s first three seeds over 24 hours';
  END IF;
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code = 'value_2026_09_30'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0575 V1: dials the arm would refuse: %', v_bad;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0575_night_two_measures_what_a_customer_is_paying_for', false, false,
  'Rows only: sweep value_2026_09_30 and its eight cells (OTTO-Q and first-come-first-served, each with the energy '
  'planner on and off, at 10 and 20 robotic fast chargers; 24-hour days on night 1''s first three seeds). Read only by '
  'the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
