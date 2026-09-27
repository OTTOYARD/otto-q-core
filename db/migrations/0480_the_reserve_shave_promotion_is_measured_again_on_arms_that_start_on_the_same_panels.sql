-- migration-version: 20260926115449
-- migration-name:    the_reserve_shave_promotion_is_measured_again_on_arms_that_start_on_the_same_panels
--
-- 0480  **The reserve-shave promotion is measured again, on arms that start on the same panels.** `db/checks/0361`
--       §8. FINDINGS G211, G214.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Experiment b66fa99c (energy_reserve_shave 0 vs 1 on the twin depot, primary site cost per day, lower is better)
--   concluded treatment_wins with 6 of 6 pairs, p = 0.0156 against a per-look alpha of 0.025, and was promoted. G214
--   then showed that the arms of a pair did not start on the same solar panels: the canopy soiling was depot state
--   every run shared. Of the six pairs, three started clean and all three favour the treatment, two started with the
--   treatment's panels dirtier and it won both, and one started with them cleaner. That sixth pair is the one the
--   p-value needed: five of five is p = 0.031. The effect looks real, but the verdict's arithmetic passed on a pair the
--   confound favoured. 0479 scopes the soiling to the run, so every arm now starts at 0.85.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Registers a replication: the same dial, values, scenario, ticks, start, fixed parameters, primary, guardrails,
--   looks and alphas as b66fa99c, under a new experiment id and therefore new seeds (ottoq_dial_experiment_seed is
--   keyed by the id). The dial runner (cron 755) runs it in its next window, 3:00-6:00 AM CT.
--
--   The depot's incumbent is already 1, the treatment. So a replicated win changes nothing: the promoter refuses it
--   as incumbent_moved and records the verdict, which is the point, a clean measurement of the promoted value. A
--   replication that does not win is the signal to reconsider promotion 11, by a human, with this verdict beside it.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   One row in ottoq_dial_experiments. No function changes.

BEGIN;

-- ── P2: 0479 is in, the original concluded, and nothing else is measuring this dial at this depot ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_sim_canopy_soiling')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                     WHERE name = '0479_the_solar_canopies_soiling_was_shared_by_every_run_so_an_arm_inherited_the_panels_the_last_run_left') THEN
    RAISE EXCEPTION '0480 P2: 0479 is not applied, so the arms would still inherit each other''s panels';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_dial_experiments
                  WHERE experiment_id = 'b66fa99c-4239-4f3b-a0a6-6dd37e77af68' AND status = 'concluded') THEN
    RAISE EXCEPTION '0480 P2: b66fa99c is not the concluded experiment this file replicates';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_dial_experiments
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND param_key = 'energy_reserve_shave' AND status = 'active') THEN
    RAISE EXCEPTION '0480 P2: an active experiment already measures energy_reserve_shave at the twin depot';
  END IF;
END $premises$;

INSERT INTO public.ottoq_dial_experiments
  (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
   primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct, min_effect_pct,
   guardrail_alpha, hypothesis)
SELECT '0480', e.depot_id, e.param_key, e.control_value, e.treatment_value, e.fixed_params, e.scenario, e.ticks, e.sim_start,
       e.primary_metric, e.primary_better, e.first_look_pairs, e.final_look_pairs, e.alpha, e.guardrail_margin_pct,
       e.min_effect_pct, e.guardrail_alpha,
       'Replication of b66fa99c on arms that start on the same solar panels (G214, fixed by 0479): with the day plan '
       'on, the reserve-shaving battery lowers the realised daily site cost against the fixed-factor demand target, by '
       'at least 0.5%, within the same guardrails. b66fa99c''s sixth pair started the treatment on cleaner panels, and '
       'its p = 0.0156 needed that pair. The incumbent is already the treatment, so a win is recorded, not promoted.'
  FROM public.ottoq_dial_experiments e
 WHERE e.experiment_id = 'b66fa99c-4239-4f3b-a0a6-6dd37e77af68';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE r record; o record;
BEGIN
  SELECT * INTO o FROM public.ottoq_dial_experiments WHERE experiment_id = 'b66fa99c-4239-4f3b-a0a6-6dd37e77af68';
  SELECT * INTO r FROM public.ottoq_dial_experiments WHERE created_by = '0480';
  -- V1: exactly one replication, active, identical in design to the original, with a new id.
  IF (SELECT count(*) FROM public.ottoq_dial_experiments WHERE created_by = '0480') <> 1
     OR r.status <> 'active' OR r.experiment_id = o.experiment_id
     OR (r.depot_id, r.param_key, r.control_value, r.treatment_value, r.fixed_params, r.scenario, r.ticks, r.sim_start,
         r.primary_metric, r.primary_better, r.first_look_pairs, r.final_look_pairs, r.alpha, r.guardrail_margin_pct,
         r.min_effect_pct, r.guardrail_alpha)
        IS DISTINCT FROM
        (o.depot_id, o.param_key, o.control_value, o.treatment_value, o.fixed_params, o.scenario, o.ticks, o.sim_start,
         o.primary_metric, o.primary_better, o.first_look_pairs, o.final_look_pairs, o.alpha, o.guardrail_margin_pct,
         o.min_effect_pct, o.guardrail_alpha) THEN
    RAISE EXCEPTION '0480 V1: the replication is not the original''s design under a new id';
  END IF;
  -- V2: its seeds are new.
  IF public.ottoq_dial_experiment_seed(r.experiment_id, 1) = public.ottoq_dial_experiment_seed(o.experiment_id, 1) THEN
    RAISE EXCEPTION '0480 V2: the replication would draw the original''s seeds';
  END IF;
END $verify$;

-- Rollback: UPDATE public.ottoq_dial_experiments SET status = 'abandoned', concluded_at = now() WHERE created_by = '0480'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0480_the_reserve_shave_promotion_is_measured_again_on_arms_that_start_on_the_same_panels', false,
  'Data only: one dial experiment registered, replicating b66fa99c after 0479. No function changes.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
