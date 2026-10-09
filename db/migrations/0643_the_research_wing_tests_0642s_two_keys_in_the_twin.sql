-- migration-version: PENDING
-- migration-name:    the_research_wing_tests_0642s_two_keys_in_the_twin
--
-- 0643  **The research wing tests 0642's two keys in the twin, as paired runs.** (G384; research wing, rule 10.)
--        0642 put two keys into the kernel's own charge order: a car that has waited charge_wait_floor_min (90) goes
--        first, and the rest are ordered by minutes of charge (charge_order_minutes, 1). Both were measured only in the
--        check's replay of two runs and in one live run an operator stopped at 91 sim-minutes, inside the live twin's
--        noise floor (db/checks/0426 §2). The instrument that can tell is a paired test: two arms of one seed, the same
--        world byte for byte, and only the dial different. This registers one experiment per key. It changes nothing
--        outside the experiments' own arms: the shipped defaults stay, and a result is a recommendation a person ships
--        as a certified change (0540).
--
-- ══ §1 THE TWO EXPERIMENTS ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The floor. charge_wait_floor_min, control 0 (no floor) against treatment 90, with charge_order_minutes fixed at 1
--       in both arms. Primary: charge_wait_p95_floor_min, lower is better: the 95th percentile of each charge-owing
--       visit's wait for its first charger, a visit still waiting at the arm's end counted at its wait so far
--       (ottoq_kpi_charge_wait), which is the tail the floor exists to bound.
--   (b) The minutes. charge_order_minutes, control 0 (0545's ratio in battery points) against treatment 1, with
--       charge_wait_floor_min fixed at 90 in both arms. Primary: deployed_car_hours, higher is better: the minutes
--       order's promise is that a car whose charge is short goes out sooner.
--   Both as 0548's: busy_day at the twin depot, 90 ticks of 6 sim-minutes from 8:00 AM CT (to 5:00 PM, the operator
--   governor's day), looks at 6 and 12 pairs, alpha 0.05, the five KPIs held within 2% (guardrail alpha 0.2), and the
--   safety floor that no counted pair may leave more returns unserved. The harness quiesces the agent in both arms, so
--   the pairs measure the kernel's own order. Nothing here shortens a charge (rule 9): both keys only order the line.
--
-- ══ §2 WHEN ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The dial runner pairs one experiment at a time, only in its nightly window, only with no run live, and only after
--   the canon is recertified (0642 forces it); it takes the active experiment with the fewest pairs since the dial
--   floor. Each pair holds the world for its duration (G141), which the window exists for.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1 0642 applied; neither experiment exists. V1 both rows are active, their dials and fixed keys catalogued and in
--   range (ottoq_dial_pair refuses otherwise, at run time). V2 the two primary metrics are among the keys an arm's
--   metrics carry (ottoq_dial_arm_metrics, read from the latest pair in the ledger).
--
-- ROLLBACK: mark the two experiments created_by 'claude_code_2026_10_09' abandoned, with a verdict whose outcome is
--   'withdrawn' and the time it was concluded, so their pairs stay in the ledger as evidence; and take this file's row
--   out of ottoq_cert_lineage.

BEGIN;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0643_the_research_wing_tests_0642s_two_keys_in_the_twin') THEN
    RAISE EXCEPTION '0643 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0642_the_kernel_serves_a_long_wait_first_and_times_its_line_in_minutes') THEN
    RAISE EXCEPTION '0643 P1: 0642 is not applied; apply it first';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_dial_experiments
              WHERE param_key IN ('charge_wait_floor_min', 'charge_order_minutes') AND status = 'active') THEN
    RAISE EXCEPTION '0643 P1: an active experiment on one of these keys already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_dial_experiments
  (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
   primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct, min_effect_pct,
   guardrail_alpha, hypothesis, status, sim_min_per_tick, run_after)
VALUES
 ('claude_code_2026_10_09', '11111111-1111-1111-1111-111111111111', 'charge_wait_floor_min', 0, 90,
  '{"charge_order_minutes": 1}'::jsonb, 'busy_day', 90, '2026-09-01T13:00:00+00:00', 'charge_wait_p95_floor_min', 'lower',
  6, 12, 0.05, 2, 0.5, 0.2,
  'G384 (0642; db/checks/0424 §4, 0426 §2): with a 90-minute floor in the kernel''s own charge order, a car that has '
  'waited 90 minutes goes ahead of every car that has not, the longest wait first, so the tail of the wait for a '
  'charger is shorter than with no floor (the 95th percentile, a visit still waiting counted at its wait so far), '
  'without leaving any return unserved or moving the five KPIs more than 2% the wrong way. On b2efcc07 the 13 boot cars '
  'under 45% waited a mean 98 minutes for a charger and 3 were never seated. No charge is shortened (rule 9). Arms at 6 '
  'sim-minutes a tick from 8:00 AM CT for 90 ticks, charge_order_minutes 1 in both.',
  'active', 6, NULL),
 ('claude_code_2026_10_09', '11111111-1111-1111-1111-111111111111', 'charge_order_minutes', 0, 1,
  '{"charge_wait_floor_min": 90}'::jsonb, 'busy_day', 90, '2026-09-01T13:00:00+00:00', 'deployed_car_hours', 'higher',
  6, 12, 0.05, 2, 0.5, 0.2,
  'G384 (0642 §1): ordering the kernel''s charge line by minutes of charge on the depot''s learned clock, (minutes '
  'waited + minutes of charge) / minutes of charge, instead of 0545''s ratio in battery points, sends a car whose '
  'charge is short out sooner and raises deployed car-hours, without leaving any return unserved or moving the five '
  'KPIs more than 2% the wrong way. In the check''s replay of b2efcc07 it put 41 of 962 due cars on time against 12, '
  'and 33 of 720 against 25 on 64251eb8. No charge is shortened (rule 9). Arms at 6 sim-minutes a tick from 8:00 AM '
  'CT for 90 ticks, charge_wait_floor_min 90 in both.',
  'active', 6, NULL);

-- ══ V1: both rows are active, their keys catalogued and in range ════════════════════════════════════════════════════
DO $v1$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT e.experiment_id, e.param_key, e.control_value, e.treatment_value, e.fixed_params
             FROM public.ottoq_dial_experiments e
            WHERE e.created_by = 'claude_code_2026_10_09' AND e.status = 'active'
  LOOP
    v_n := v_n + 1;
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog c WHERE c.param_key = r.param_key
                     AND r.control_value BETWEEN c.min_value AND c.max_value
                     AND r.treatment_value BETWEEN c.min_value AND c.max_value) THEN
      RAISE EXCEPTION '0643 V1: % is uncatalogued or an arm is outside its range', r.param_key;
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_each_text(r.fixed_params) f
                WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog c WHERE c.param_key = f.key
                                    AND f.value::numeric BETWEEN c.min_value AND c.max_value)) THEN
      RAISE EXCEPTION '0643 V1: a fixed key of the % experiment is uncatalogued or outside its range', r.param_key;
    END IF;
  END LOOP;
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0643 V1: % active experiments registered, not 2', v_n;
  END IF;
  RAISE NOTICE '0643 V1: two experiments active (charge_wait_floor_min 0 against 90; charge_order_minutes 0 against 1)';
END $v1$;

-- ══ V2: the primary metrics are among an arm's metrics ═════════════════════════════════════════════════════════════
DO $v2$
DECLARE v_keys jsonb;
BEGIN
  SELECT l.metrics_a INTO v_keys FROM public.ottoq_dial_pair_ledger l WHERE l.metrics_a IS NOT NULL ORDER BY l.ran_at DESC LIMIT 1;
  IF v_keys IS NULL THEN
    RAISE NOTICE '0643 V2: no pair in the ledger yet to read an arm''s metrics from';
    RETURN;
  END IF;
  IF NOT (v_keys ? 'charge_wait_p95_floor_min' AND v_keys ? 'deployed_car_hours') THEN
    RAISE EXCEPTION '0643 V2: an arm''s metrics do not carry charge_wait_p95_floor_min and deployed_car_hours';
  END IF;
  RAISE NOTICE '0643 V2: an arm''s metrics carry both primary metrics';
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0643_the_research_wing_tests_0642s_two_keys_in_the_twin', false, false,
  'Registers two dial experiments on 0642''s keys (charge_wait_floor_min 0 against 90; charge_order_minutes 0 against '
  '1), busy_day at the twin depot, 90 ticks of 6 sim-minutes, as 0548''s. No engine function, dial default or seat '
  'changes. FALSE/FALSE.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
