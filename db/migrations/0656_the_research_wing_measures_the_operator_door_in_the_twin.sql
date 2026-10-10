-- migration-version: PENDING
-- migration-name:    the_research_wing_measures_the_operator_door_in_the_twin
--
-- 0656  **The research wing measures what the operator door changes in the twin, as a paired run.** (Step 4 of the
--        twin data contract review; research wing, rule 10.) 0654 put the twin's two operators on every tick driver
--        behind twin_operator_door and said the flag would not be set anywhere until a paired run measured it (0654
--        §2). This registers that measurement as a dial experiment, so ottoq_dial_pair can run it: two arms of one
--        seed, the same world byte for byte, the agent quiesced, and only the flag different. It changes nothing
--        outside the experiment's own arms.
--
-- ══ §1 THE EXPERIMENT ════════════════════════════════════════════════════════════════════════════════════════════
--
--   twin_operator_door, control 0 (the walk carries out OTTO-Q's commands inside the next world tick, at that tick's
--   clock, and writes their outcome itself) against treatment 1 (the twin's operators read each directive through
--   the v2 door at the start of the next beat, the world carries it out then, at the run's clock, and the operators'
--   acks write the outcome). No fixed keys: both arms run the engine's shipped defaults. busy_day at the twin depot,
--   90 ticks of 6 sim-minutes from 8:00 AM CT, as 0643's. Primary: deployed_car_hours, higher.
--
--   This is a measurement, not a tuning. The flag is a switch in how the twin hears OTTO-Q, not a setting of the
--   engine's; it is set by a person as a certified change whatever the arms show, and no verdict on it is a
--   recommendation (0540). What the pair is for: that the treatment runs a whole day with no arm error, every
--   directive answered by its own operator (ottoq_assert_operator_isolation over the treatment arm reads 0), and by
--   how much carrying a directive out at the clock it was issued, rather than one tick later, moves what the twin
--   models, which is what a person reads before setting the flag. One seed is one reading, not a range (G153).
--
-- ══ §2 CHECKS ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1 0655 applied (the finalizer keeps an operator's answer, so the treatment arm's record survives its stop);
--   twin_operator_door catalogued 0..1 and set nowhere; no experiment on it. V1 the row is active and its dial in
--   range. V2 the primary metric is among the keys an arm's metrics carry.
--
-- ROLLBACK: mark the experiment created_by '0656' abandoned, with a verdict whose outcome is 'withdrawn' and the time
--   it was concluded, so its pairs stay in the ledger as evidence; and take this file's row out of ottoq_cert_lineage.

BEGIN;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0656_the_research_wing_measures_the_operator_door_in_the_twin') THEN
    RAISE EXCEPTION '0656 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0655_the_finalizer_leaves_a_directive_its_operator_answered_as_it_was_answered') THEN
    RAISE EXCEPTION '0656 P1: 0655 is not applied; apply it first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'twin_operator_door' AND default_value = 0 AND min_value = 0 AND max_value = 1) THEN
    RAISE EXCEPTION '0656 P1: twin_operator_door is not catalogued as 0..1 with default 0';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_operator_door') THEN
    RAISE EXCEPTION '0656 P1: twin_operator_door is set somewhere; this file assumes it is 0 everywhere';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_dial_experiments WHERE param_key = 'twin_operator_door') THEN
    RAISE EXCEPTION '0656 P1: an experiment on twin_operator_door already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_dial_experiments
  (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
   primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct, min_effect_pct,
   guardrail_alpha, hypothesis, status, sim_min_per_tick, run_after)
VALUES
 ('0656', '11111111-1111-1111-1111-111111111111', 'twin_operator_door', 0, 1,
  '{}'::jsonb, 'busy_day', 90, '2026-09-01T13:00:00+00:00', 'deployed_car_hours', 'higher',
  6, 12, 0.05, 2, 0.5, 0.2,
  'A measurement, not a tuning (0654 §2, 0656 §1). With twin_operator_door on, the twin''s two operators read each '
  'directive through the v2 door at the start of the next beat and the world carries it out at the run''s clock then, '
  'the clock it was issued at, where the walk carried it out inside the next world tick one tick later; the operators'' '
  'acks write the outcome. The pair shows the treatment runs a whole day with no arm error and every directive answered '
  'by its own operator, and how much carrying a directive out one tick sooner moves what the twin models. The flag is '
  'set by a person as a certified change; no verdict here is a recommendation. Nothing changes a charge target or a '
  'service (rule 9). Arms at 6 sim-minutes a tick from 8:00 AM CT for 90 ticks, the shipped defaults in both.',
  'active', 6, NULL);

-- ══ V1: the row is active and its dial in range ═══════════════════════════════════════════════════════════════════
DO $v1$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_dial_experiments e JOIN public.ottoq_policy_param_catalog c USING (param_key)
                  WHERE e.created_by = '0656' AND e.status = 'active' AND e.param_key = 'twin_operator_door'
                    AND e.control_value BETWEEN c.min_value AND c.max_value
                    AND e.treatment_value BETWEEN c.min_value AND c.max_value) THEN
    RAISE EXCEPTION '0656 V1: the experiment is not active with its arms inside the catalog''s range';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_scenarios s
                  WHERE s.scenario_code = 'busy_day' AND s.status = 'active'
                    AND s.depot_id = '11111111-1111-1111-1111-111111111111') THEN
    RAISE EXCEPTION '0656 V1: busy_day is not active on the twin depot (ottoq_dial_pair would refuse)';
  END IF;
  RAISE NOTICE '0656 V1: one experiment active (twin_operator_door 0 against 1, busy_day at the twin depot)';
END $v1$;

-- ══ V2: the primary metric is among an arm's metrics ══════════════════════════════════════════════════════════════
DO $v2$
DECLARE v_keys jsonb;
BEGIN
  SELECT l.metrics_a INTO v_keys FROM public.ottoq_dial_pair_ledger l WHERE l.metrics_a IS NOT NULL ORDER BY l.ran_at DESC LIMIT 1;
  IF v_keys IS NULL OR NOT (v_keys ? 'deployed_car_hours') THEN
    RAISE EXCEPTION '0656 V2: the latest pair''s arm metrics do not carry deployed_car_hours';
  END IF;
  RAISE NOTICE '0656 V2: an arm''s metrics carry the primary metric';
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0656_the_research_wing_measures_the_operator_door_in_the_twin', false, false,
  'Registers one dial experiment, twin_operator_door 0 against 1, busy_day at the twin depot, 90 ticks of 6 '
  'sim-minutes, the shipped defaults in both arms: the paired measurement 0654 §2 requires before the flag is set. No '
  'engine function, dial default or seat changes. FALSE/FALSE.',
  now());

COMMIT;
