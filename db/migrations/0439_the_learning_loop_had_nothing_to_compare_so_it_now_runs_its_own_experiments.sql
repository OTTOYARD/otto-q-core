-- migration-version: 20260923020808
-- migration-name:    the_learning_loop_had_nothing_to_compare_so_it_now_runs_its_own_experiments
--
-- 0439  **The learning loop had nothing to compare, so it now runs its own experiments.** The dial promoter
--       ranks dial values by the reward of runs that happened to use them. No cell on the twin depot has ever
--       held two different settings of a promotable dial, so it has had nothing to rank. Where it will
--       eventually see contrast, it will see the agent's own trajectory, which is confounded by construction. This
--       adds designed experiments: common-random-numbers pairs, one dial apart, scored by an exact test with
--       planned looks, guardrails and a safety floor, and promoted only through the setter. FINDINGS G161.
--
-- ══ §1 WHAT IS WRONG (G161, measured 2026-09-23 01:10 UTC, twin depot) ═══════════════════════════════════════
--
--   (a) NO CONTRAST. `ottoq_run_dial_ledger` holds 172 rows in 35 cells keyed (engine_hash, scenario,
--       sim_min_per_tick). 12 cells clear the promoter's floors (>= 6 runs, >= 3 seeds). **0 of those 12 contain
--       two different sets of agent-writable dials.** They are certification arms, and every certification arm
--       reads the same dials. `ottoq_dial_promotion_ledger` holds 0 rows, and nothing calls
--       `ottoq_promote_dials`.
--   (b) THE CELLS POOL HORIZONS. `busy_day` at 30 sim-min per tick pools 12-, 24- and 48-tick arms. Its 3 seeds
--       come from 3 different horizons, and a per-day KPI from a 12-tick arm is not comparable with one from a
--       48-tick arm.
--   (c) THE AGENTIC RUNS ARE ONE-RUN CELLS. `sim_min_per_tick` is derived from the wall clock (0.300..., 1.546...,
--       0.104...), so no two demo runs share a cell. Seven cells hold exactly one run.
--   (d) EVEN WITH CONTRAST, THE RULE WOULD PROMOTE NOISE. The promoter takes the argmax over a cell, with
--       min-max-normalised reward and no test. The agent's dials are chosen in response to conditions:
--       `energy_reserve_shave` goes on when the battery is full, and the demand factors move when load moves.
--       So "the runs where the agent chose X did better" measures the conditions as much as X. And G153 applies
--       in full: a deterministic re-run of the same seed is repetition, not replication.
--
-- ══ §2 WHAT THIS DOES ═════════════════════════════════════════════════════════════════════════════════════════
--
--   1. `public.ottoq_dial_experiments`: one row names one dial, a control and a treatment value, the dials held
--      fixed on BOTH arms, the scenario, horizon and sim start, a primary metric and its direction, and the two
--      look sizes, alpha, a guardrail margin and a minimum practical effect. Only an operator or a migration
--      creates one; no agent path writes it. At most one experiment per (depot, dial) is active.
--   2. `public.ottoq_dial_pair(experiment, seed)`: two arms, same seed, same boot world, back to back in one
--      transaction, exactly as `ottoq_determinism_pair` runs them. That includes 0421's GUC reset before each
--      arm's fleet reset, so arm B's reset is never filed as arm A's evidence (db/checks/0329). Each arm runs the
--      deterministic core with cuOpt and the agent quiesced, exactly as `ottoq_ab_pair` does, because the agent
--      writes dials, including this one, and is not deterministic. The ONLY run-scoped difference between the
--      arms is the experiment's dial. Both arms are scored into `ottoq_ab_runs` (policy otto_q, one group per
--      pair). One ledger row holds both metric vectors, the atoms that moved, and three validity checks:
--      complete, same world (boot image, calibration and battery charge), and both arms paid the shield.
--      REFUSES a seed already paired on this engine hash, because under determinism it is not new evidence.
--      REFUSES while a run is live or the recertification runner holds its lock; it takes that same lock, so a
--      dial pair and a determinism pair can never share the world.
--   3. `public.ottoq_dial_arm_metrics(run, depot, soc_start)` computes each arm's vector:
--      - the five 2.9 KPIs as the reward reads them, and unserved returns;
--      - shield evaluations, failures and safety-critical failures, the last split by what the engine did with
--        them (0430's `effect`): `refused` (the unsafe action did not happen) and unprevented (everything else);
--      - the A/B score's operational figures;
--      - REALISED ENERGY COST: TOU energy, the NCP_30min peak priced on the depot's own tariff and amortised over
--        the plan's 30 days, battery wear, and the battery's terminal state valued at the cost of refilling it
--        (cheapest TOU rate / round trip). Without that last term a policy that simply ends the day with an
--        empty battery would look cheaper.
--   4. `public.ottoq_dial_experiment_verdict(experiment)`: the decision rule (§3). Pure read.
--   5. `public.ottoq_promote_dial_experiment(experiment, dry_run)`: concludes a decided experiment. A winning
--      treatment is written at DEPOT scope through `ottoq_policy_set`, as the existing promoter writes: actor
--      `ottoq_prime:promoter`, catalog clamp, agent_writable gate, and the AI.001 probe at policy_write. It then
--      writes an `ottoq_cert_lineage` row with forces_recert TRUE. Certification arms read depot scope, so a
--      promoted dial changes what the canon certifies, and the canon must re-certify under it. It refuses:
--      - if `dial_promotion_enabled` is off (gate 1, unchanged);
--      - if the incumbent is no longer the control the experiment beat;
--      - if the catalog's drift cap would promote a value the experiment never tested.
--      A dial that is not agent_writable is RECOMMENDED, never written; an operator applies it. Every outcome,
--      including every non-win, is recorded in `ottoq_dial_promotion_ledger`, which gains `experiment_id` and
--      `evidence`.
--   6. `public.ottoq_dial_experiment_runner()` plus a pg_cron job every 10 minutes. Each firing runs AT MOST ONE
--      pair, and only when all of these hold:
--      - `dial_experiment_runner_enabled` is on (default 0);
--      - no run is live;
--      - no enabled canon column is below the recert floor (certification has priority);
--      - it wins the recertification runner's lock.
--      It serves the active experiment with the fewest pairs on this engine, from that experiment's own
--      deterministic seed sequence, and concludes the experiment once its verdict is terminal.
--   7. `ottoq_run_reward_ledger` stops scoring designed-experiment arms. The observational promoter's cells
--      should be observational: a treatment arm there would be ranked unpaired, with no test, as one more run.
--   8. The first experiment, created ACTIVE and run by nobody until the runner is switched on:
--      - dial `energy_reserve_shave`, control 0 (the fixed-factor demand target certification arms use),
--        treatment 1 (the reserve target);
--      - `bess_day_plan_enabled = 1` held on both arms, so treatment means 0435's day plan;
--      - busy_day, 48 ticks = 24 sim-hours from 04:00 CT on 2026-09-01, a summer-tariff day;
--      - primary metric: realised site cost per day, lower better.
--
-- ══ §3 THE DECISION RULE ═════════════════════════════════════════════════════════════════════════════════════
--
--   - COUNTED PAIRS: on the CURRENT `ottoq_engine_hash()`, complete, same world, both arms paid the shield, and
--     the primary metric present on both arms. Pairs from an older engine are reported as stale and never pooled.
--     The engine they measured is not the one that would be promoted.
--   - TEST: the exact sign test (binomial, p = 1/2) on the primary metric. Ties are dropped, as the test
--     requires. It needs no distributional assumption, and with common random numbers every non-tie is caused by
--     the dial in that world.
--   - TWO PLANNED LOOKS, at the first 6 counted pairs and at the first 12, each tested at alpha/2 (Bonferroni).
--     Looking twice therefore cannot push the chance of a false promotion above alpha. At alpha = 0.05 the first
--     look decides only on 6 of 6 (p = 0.0156); 5 of 6 is p = 0.109. That is why the first look must be at least 6:
--     five unanimous pairs give p = 0.031, which is above 0.025.
--   - PRACTICAL EFFECT: a significant win must also improve the primary metric by at least `min_effect_pct` on
--     average (default 0.5%). A treatment that wins every pair by a cent is significant and not worth a change.
--   - GUARDRAILS: over the look's pairs, each of the five KPIs must not get worse by more than
--     `guardrail_margin_pct` (default 2%) on average. The direction of each KPI is the sign of its weight in the
--     active `ottoq_reward_weights`, which is where the repo already writes down "better".
--   - SAFETY, checked on every counted pair at every look, and able to stop the experiment early:
--     - no pair may leave more returns unserved under the treatment. Measured 2026-09-23: every 24- and 48-tick
--       busy_day certification arm on the twin serves every return, so one more is a signal, not noise;
--     - the treatment may not total more UNPREVENTED safety-critical failures than the control: failures whose
--       0430 `effect` is anything but `refused`, i.e. unsafe actions that went ahead.
--     Vehicle-first stays inviolable, exactly as the existing promoter's gate 6.
--   - SHIELD RELIANCE is a guardrail, not a stop. A safety-critical failure at an enforcing checkpoint is a
--     REFUSAL: the unsafe action did not happen. Measured 2026-09-23, every safety-critical failure on the last
--     certification arms (EN.003.bess_limits at bess_dispatch, 1-2 per arm) and all 204 on run 7a42982a
--     (EN.001.grid_capacity_ceiling during its two DR calls) read `refused`. Counting refusals as a safety stop
--     would halt an energy experiment on the very dispatch pattern it exists to change, about half the time,
--     on noise. So refusals block a WIN instead (`guardrail_breach`) when the treatment has more of them in
--     significantly many pairs: a one-sided sign test at `guardrail_alpha` (default 0.20). That is deliberately
--     more sensitive than the primary's per-look alpha: a missed degradation costs more than a missed win. The
--     existing promoter's gate 7 ("never trade safety for score") is the same principle on observational data.
--   - OUTCOMES. Terminal: treatment_wins, control_holds, guardrail_breach, safety_regression, no_effect (every
--     arm byte-identical, so the dial is inert in this world), negligible_effect, inconclusive (final look,
--     undecided). Otherwise: collecting.
--
-- ══ §4 forces_recert FALSE ═══════════════════════════════════════════════════════════════════════════════════
--
--   - No engine function changes. Every object is new, except the reward view, one nullable column pair on
--     the promotion ledger, and two catalog rows.
--   - The reward view feeds only `ottoq_promote_dials`, which has no caller. No atom reads it.
--   - The runner is off and nothing runs at apply. A pair only READS the engine, through the same entry points
--     the determinism pair uses.
--   - Promotion is where cert-visible behaviour can change, so the promoter writes its own forces_recert lineage
--     row when it enacts. The classification travels with the change, not with this file.
--
-- ══ §5 WHAT THIS DOES NOT DO ═════════════════════════════════════════════════════════════════════════════════
--
--   - One dial per experiment. Interactions (factorial designs) are not modelled. Two experiments on different
--     dials may run in turn, and each measures its dial with the other at the incumbent.
--   - It learns the DETERMINISTIC engine's response to a dial, not the agent's. The agent is quiesced on both
--     arms. Whether the agent should HOLD a lever is a separate question; a winning lever is what makes it worth
--     asking (0438 §4).
--   - It does not fix `ottoq_ab_pair`, which lacks 0421's GUC reset and so files arm 2's fleet reset as arm 1's
--     evidence after arm 1 is scored. That is the 0329 defect in a sibling harness, recorded as G176. This file
--     changes no existing function.
--   - 48 ticks of 30 sim-minutes is coarser than a demo run's 1-3 minutes. Both arms share it, and the energy
--     layer plans in 30-minute steps, but the realised peak of a 30-minute tick is one sample. The experiment
--     measures the dial on this harness, not on a demo.
--
-- ══ §6 ASSUMPTIONS ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   - ASSUMPTION: the monthly demand charge is spread over the 30 days that 0435's `bess_plan_demand_amortization_days`
--     declares, i.e. the simulated day stands for every day of its billing month. That is the plan's own assumption,
--     so the experiment grades the plan on the objective it optimises, with the realised load rather than the
--     forecast.
--   - ASSUMPTION: export earns nothing (NES GSA-3 carries no export credit in `ottoq_depot_tariffs`).
--   - Requires 0435 (the day plan and its dials). P1 refuses to apply before it.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0439 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0439 P0: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0439 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: what this builds on exists, in the shape read on 2026-09-23; what it creates does not ──
DO $$
DECLARE v_def text; v_n int;
BEGIN
  IF to_regprocedure('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)') IS NULL THEN
    RAISE EXCEPTION '0439 P1: public.ottoq_bess_day_plan is absent -- apply 0435 first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bess_day_plan_enabled') THEN
    RAISE EXCEPTION '0439 P1: bess_day_plan_enabled is not catalogued -- apply 0435 first';
  END IF;
  IF to_regprocedure('public.ottoq_ab_write_score(uuid,uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.ottoq_ab_arm_atoms(uuid,uuid)') IS NULL
     OR to_regprocedure('public.ottoq_kpi_five(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_run_reward_terms(jsonb)') IS NULL
     OR to_regprocedure('public.ottoq_boot_state_fingerprint(uuid,uuid)') IS NULL
     OR to_regprocedure('public.ottoq_tick_invariance_reset_fleet(uuid,bigint,timestamp with time zone)') IS NULL
     OR to_regprocedure('twin.ottoq_sim_start_run(text,timestamp with time zone,numeric,bigint,text)') IS NULL
     OR to_regprocedure('twin.ottoq_sim_prime_deployment(uuid,timestamp with time zone,numeric)') IS NULL
     OR to_regprocedure('public.ottoq_sim_advance_tick(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_sim_stop_and_reset(uuid,text)') IS NULL
     OR to_regprocedure('public.ottoq_engine_hash()') IS NULL
     OR to_regprocedure('public.ottoq_policy_set(text,uuid,text,numeric,text)') IS NULL
     OR to_regprocedure('public.ottoq_dial_clamp(text,numeric,text)') IS NULL
     OR to_regprocedure('public.ottoq_is_agent_actor(text,text[])') IS NULL THEN
    RAISE EXCEPTION '0439 P1: an entry point the pair is built on is missing';
  END IF;
  -- the pair's arm protocol is copied from these two; if either moved, re-read before applying
  SELECT md5(prosrc) INTO v_def FROM pg_proc WHERE oid = 'public.ottoq_ab_pair(bigint,integer,text,uuid,timestamp with time zone,integer,text,text)'::regprocedure;
  IF v_def <> 'a02d660122e25f46e649ce334f93c223' THEN RAISE EXCEPTION '0439 P1: ottoq_ab_pair md5 is % (quiesce protocol moved?)', v_def; END IF;
  SELECT md5(prosrc) INTO v_def FROM pg_proc WHERE oid = 'public.ottoq_determinism_pair(bigint,integer,text,uuid,timestamp with time zone,integer)'::regprocedure;
  IF v_def <> '7c953e488ae659077609d7f8086a3bc6' THEN RAISE EXCEPTION '0439 P1: ottoq_determinism_pair md5 is % (arm protocol moved?)', v_def; END IF;
  -- the reward view as read; its one splice anchor must be unique
  v_def := pg_get_viewdef('public.ottoq_run_reward_ledger'::regclass, true);
  IF md5(v_def) <> '741ce532715a25072d391a1840375b6d' THEN RAISE EXCEPTION '0439 P1: ottoq_run_reward_ledger md5 is %', md5(v_def); END IF;
  v_n := (length(v_def) - length(replace(v_def, E'           FROM ottoq_run_dial_ledger d\n        ), cell AS (', '')))
         / length(E'           FROM ottoq_run_dial_ledger d\n        ), cell AS (');
  IF v_n <> 1 THEN RAISE EXCEPTION '0439 P1: reward view anchor matched % times', v_n; END IF;
  IF to_regclass('public.ottoq_dial_experiments') IS NOT NULL OR to_regclass('public.ottoq_dial_pair_ledger') IS NOT NULL
     OR to_regprocedure('public.ottoq_dial_pair(uuid,bigint,integer)') IS NOT NULL THEN
    RAISE EXCEPTION '0439 P1: the experiment objects already exist';
  END IF;
END $$;

-- ── P2: the premises the design rests on, re-proved at apply time ──
DO $$
DECLARE v_src text;
BEGIN
  -- the recertification runner's lock is the one the pair and the runner share
  SELECT command INTO v_src FROM cron.job WHERE jobname = 'ottoq-recert-runner';
  IF v_src IS NULL OR position('pg_try_advisory_xact_lock(hashtext(''ottoq_recert_runner'')::bigint)' IN v_src) = 0 THEN
    RAISE EXCEPTION '0439 P2: the recert runner no longer takes the ottoq_recert_runner lock -- the pair would not exclude it';
  END IF;
  -- the promoter's actor is judged as an agent by the setter (agent_writable gate + agent envelope)
  IF NOT public.ottoq_is_agent_actor('ottoq_prime:promoter') THEN
    RAISE EXCEPTION '0439 P2: ottoq_prime:promoter is no longer an agent actor -- the setter would stop gating promotions';
  END IF;
  -- the first experiment's dial is promotable and two-valued as designed
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'energy_reserve_shave' AND agent_writable AND min_value = 0 AND max_value = 1) THEN
    RAISE EXCEPTION '0439 P2: energy_reserve_shave is no longer an agent-writable 0..1 switch';
  END IF;
  -- no depot or global row holds it on (the control must be the incumbent, and 0435 P3 relies on the same)
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params
              WHERE param_key = 'energy_reserve_shave' AND scope_type IN ('depot','global') AND param_value >= 0.5) THEN
    RAISE EXCEPTION '0439 P2: energy_reserve_shave is already on at depot/global scope -- the control is not the incumbent';
  END IF;
  -- the scenario is bound to the twin depot (0175: the pair and the scenario must name the same world)
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_scenarios WHERE scenario_code = 'busy_day' AND status = 'active'
                    AND depot_id = '11111111-1111-1111-1111-111111111111') THEN
    RAISE EXCEPTION '0439 P2: busy_day is not an active scenario on the twin depot';
  END IF;
  -- the tariff the cost metric prices against is present for September
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_depot_tariffs WHERE depot_id = '11111111-1111-1111-1111-111111111111'
                    AND active AND 9 = ANY (season_months) AND demand_first_block_usd_kw IS NOT NULL) THEN
    RAISE EXCEPTION '0439 P2: no active September demand tariff for the twin depot';
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0439_pre', 'view', 'public', 'ottoq_run_reward_ledger',
       pg_get_viewdef('public.ottoq_run_reward_ledger'::regclass, true),
       md5(pg_get_viewdef('public.ottoq_run_reward_ledger'::regclass, true));

-- ── (1) THE EXPERIMENT REGISTRY ──
CREATE TABLE public.ottoq_dial_experiments (
  experiment_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at           timestamptz NOT NULL DEFAULT now(),
  created_by           text NOT NULL,
  depot_id             uuid NOT NULL,
  param_key            text NOT NULL REFERENCES public.ottoq_policy_param_catalog (param_key),
  control_value        numeric NOT NULL,
  treatment_value      numeric NOT NULL,
  fixed_params         jsonb NOT NULL DEFAULT '{}'::jsonb,
  scenario             text NOT NULL,
  ticks                integer NOT NULL,
  sim_start            timestamptz NOT NULL,
  primary_metric       text NOT NULL,
  primary_better       text NOT NULL,
  first_look_pairs     integer NOT NULL DEFAULT 6,
  final_look_pairs     integer NOT NULL DEFAULT 12,
  alpha                numeric NOT NULL DEFAULT 0.05,
  guardrail_margin_pct numeric NOT NULL DEFAULT 2,
  min_effect_pct       numeric NOT NULL DEFAULT 0.5,
  guardrail_alpha      numeric NOT NULL DEFAULT 0.20,
  hypothesis           text NOT NULL,
  status               text NOT NULL DEFAULT 'active',
  concluded_at         timestamptz,
  verdict              jsonb,
  CONSTRAINT ottoq_dial_experiments_values_differ CHECK (treatment_value <> control_value),
  CONSTRAINT ottoq_dial_experiments_status        CHECK (status IN ('active','concluded','abandoned')),
  CONSTRAINT ottoq_dial_experiments_better        CHECK (primary_better IN ('lower','higher')),
  -- 6 is the smallest n at which a unanimous sign test clears alpha/2 = 0.025 (1/64); see header §3
  CONSTRAINT ottoq_dial_experiments_looks         CHECK (first_look_pairs >= 6 AND final_look_pairs >= first_look_pairs
                                                          AND final_look_pairs <= 40),
  CONSTRAINT ottoq_dial_experiments_alpha         CHECK (alpha > 0 AND alpha <= 0.10),
  CONSTRAINT ottoq_dial_experiments_margins       CHECK (guardrail_margin_pct >= 0 AND min_effect_pct >= 0
                                                          AND guardrail_alpha > 0 AND guardrail_alpha <= 0.5),
  CONSTRAINT ottoq_dial_experiments_ticks         CHECK (ticks BETWEEN 12 AND 96),
  CONSTRAINT ottoq_dial_experiments_fixed         CHECK (jsonb_typeof(fixed_params) = 'object' AND NOT fixed_params ? param_key),
  -- the harness's own keys define the arm; an experiment on one of them would edit the instrument
  CONSTRAINT ottoq_dial_experiments_not_harness   CHECK (param_key NOT IN ('cuopt_propose_enabled','cuopt_first_refusal_max_defers',
                                                                          'orchestrator_agent_enabled','proposer_seat'))
);
CREATE UNIQUE INDEX ottoq_dial_experiments_one_active
    ON public.ottoq_dial_experiments (depot_id, param_key) WHERE status = 'active';
COMMENT ON TABLE public.ottoq_dial_experiments IS
  '0439 (G161): designed dial experiments. One dial, a control and a treatment, dials held fixed on both arms, and '
  'the decision rule''s parameters. Created by an operator or a migration; no agent path writes it. Read by '
  'ottoq_dial_pair / ottoq_dial_experiment_verdict / ottoq_promote_dial_experiment / ottoq_dial_experiment_runner.';

-- ── (2) THE PAIR LEDGER (evidence: it outlives the arms it describes) ──
CREATE TABLE public.ottoq_dial_pair_ledger (
  pair_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  experiment_id    uuid NOT NULL REFERENCES public.ottoq_dial_experiments (experiment_id),
  seed             bigint NOT NULL,
  engine_hash      text NOT NULL,
  ran_at           timestamptz NOT NULL DEFAULT now(),
  run_a            uuid NOT NULL,          -- control arm; deliberately NO foreign key (0340's reasoning)
  run_b            uuid NOT NULL,          -- treatment arm
  ab_group_id      uuid NOT NULL,
  complete         boolean NOT NULL,
  world_identical  boolean NOT NULL,
  both_paid_shield boolean NOT NULL,
  differs          boolean NOT NULL,
  moved            jsonb NOT NULL,
  metrics_a        jsonb NOT NULL,
  metrics_b        jsonb NOT NULL,
  delta            jsonb NOT NULL,
  wall_s           numeric,
  CONSTRAINT ottoq_dial_pair_ledger_one_seed_per_engine UNIQUE (experiment_id, seed, engine_hash)
);
CREATE INDEX ottoq_dial_pair_ledger_runs ON public.ottoq_dial_pair_ledger (run_a, run_b);
COMMENT ON TABLE public.ottoq_dial_pair_ledger IS
  '0439 (G161): one row per CRN dial pair. Evidence, not engine: it must survive ottoq_purge_prior_runs, so it '
  'carries no foreign key to ottoq_sim_runs (0340). UNIQUE (experiment, seed, engine_hash) because a '
  'deterministic re-run of a seed is repetition, not replication (G153).';

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_dial_pair_ledger', 'run_a', 'evidence',
        '0439: the control arm of a designed dial pair. Evidence: the verdict is computed from this ledger after the '
        'arm itself is purged. No FK to ottoq_sim_runs, deliberately, as 0340 established.'),
       ('public', 'ottoq_dial_pair_ledger', 'run_b', 'evidence',
        '0439: the treatment arm of a designed dial pair. As run_a.');

ALTER TABLE public.ottoq_dial_promotion_ledger
  ADD COLUMN experiment_id uuid,
  ADD COLUMN evidence jsonb;
COMMENT ON COLUMN public.ottoq_dial_promotion_ledger.experiment_id IS
  '0439: set when the row was written by ottoq_promote_dial_experiment (a designed experiment), NULL for the '
  'observational promoter ottoq_promote_dials.';

REVOKE ALL ON TABLE public.ottoq_dial_experiments, public.ottoq_dial_pair_ledger FROM anon, authenticated;
GRANT SELECT ON TABLE public.ottoq_dial_experiments, public.ottoq_dial_pair_ledger TO authenticated;
GRANT ALL ON TABLE public.ottoq_dial_experiments, public.ottoq_dial_pair_ledger TO service_role;

-- ── (3) HELPERS: the seed sequence and the binomial tail ──
CREATE OR REPLACE FUNCTION public.ottoq_dial_experiment_seed(p_experiment_id uuid, p_k integer)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
  /* 0439: the k-th seed of an experiment. A pure hash of (experiment, k), 60 bits so it is always a positive
     bigint, so the sequence is the same on every call, on every backend, forever. */
  SELECT ('x' || substr(md5(p_experiment_id::text || ':' || p_k::text), 1, 15))::bit(60)::bigint
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_binom_upper_tail(p_n integer, p_k integer)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
  /* 0439: P(X >= k) for X ~ Binomial(n, 1/2), exactly. The sign test's p-value for k successes of n
     non-tied pairs. Exact numeric factorials; n is at most 40 by the experiments table's CHECK. */
  SELECT CASE WHEN p_k <= 0 THEN 1::numeric
              WHEN p_k > p_n THEN 0::numeric
              ELSE (SELECT sum(factorial(p_n) / (factorial(i) * factorial(p_n - i)))
                      FROM generate_series(p_k, p_n) AS i) / power(2::numeric, p_n) END
$function$;

-- ── (4) ONE ARM'S METRIC VECTOR ──
CREATE OR REPLACE FUNCTION public.ottoq_dial_arm_metrics(p_run uuid, p_depot uuid, p_soc_start_kwh numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0439: what an arm cost and what it produced, read BEFORE its teardown. Energy is integrated over the arm's own
   snapshots, time-weighted; the peak is the NES NCP_30min basis (highest 30-consecutive-minute mean of grid
   import); the demand charge is the depot's own tariff for the sim month, amortised over the day plan's
   bess_plan_demand_amortization_days; battery wear is discharged kWh x bess_plan_degradation_usd_kwh; and the
   battery's end state is charged back at what refilling it would cost (cheapest rate the arm saw / round trip),
   so a policy that simply ends the day emptier cannot look cheaper for it. c_tz is the same constant 0435 uses. */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  r ottoq_sim_runs%ROWTYPE; v_ab ottoq_ab_runs%ROWTYPE;
  v_kpi jsonb; v_terms jsonb; v_month int;
  v_grid_kwh numeric; v_cost numeric; v_peak30 numeric; v_dis numeric; v_chg numeric; v_min_rate numeric; v_samples int;
  v_block numeric; v_r1 numeric; v_r2 numeric; v_demand numeric;
  v_amort numeric; v_deg numeric; v_rt_raw numeric; v_rt numeric; v_soc_end numeric; v_terminal numeric;
  v_evals bigint; v_fail bigint; v_crit bigint; v_crit_ref bigint; v_crit_unp bigint; v_dr int; v_defer bigint;
BEGIN
  SELECT * INTO r FROM ottoq_sim_runs WHERE sim_run_id = p_run;
  IF NOT FOUND THEN RAISE EXCEPTION 'ottoq_dial_arm_metrics: run % not found', p_run; END IF;

  v_kpi   := public.ottoq_kpi_five(p_run);
  v_terms := public.ottoq_run_reward_terms(v_kpi);

  WITH s AS (
    SELECT e.timestamp AS t, GREATEST(COALESCE(e.grid_import_kw, 0), 0) AS g, COALESCE(e.bess_output_kw, 0) AS b,
           e.current_rate_per_kwh AS rate,
           EXTRACT(EPOCH FROM (lead(e.timestamp) OVER (ORDER BY e.timestamp) - e.timestamp)) / 3600.0 AS dt
      FROM site_energy_snapshots e
     WHERE e.sim_run_id = p_run AND e.depot_id = p_depot
  ), s2 AS (
    -- the last sample has no successor; it holds for the arm's mean interval. Gaps beyond an hour are capped.
    SELECT t, g, b, rate, LEAST(COALESCE(dt, (SELECT avg(dt) FROM s WHERE dt IS NOT NULL), 0), 1.0) AS dt FROM s
  ), w AS (
    SELECT avg(g) OVER (ORDER BY t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30 FROM s2
  )
  SELECT count(*), sum(g * dt), sum(g * dt * rate), (SELECT max(g30) FROM w),
         sum(GREATEST(b, 0) * dt), sum(GREATEST(-b, 0) * dt), min(rate)
    INTO v_samples, v_grid_kwh, v_cost, v_peak30, v_dis, v_chg, v_min_rate
    FROM s2;

  v_month := EXTRACT(MONTH FROM (r.sim_clock_start AT TIME ZONE c_tz))::int;
  SELECT t.block_kw, t.demand_first_block_usd_kw, t.demand_excess_usd_kw INTO v_block, v_r1, v_r2
    FROM ottoq_depot_tariffs t
   WHERE t.depot_id = p_depot AND t.active AND v_month = ANY (t.season_months)
   ORDER BY t.effective_from DESC LIMIT 1;
  v_demand := CASE WHEN v_r1 IS NULL OR v_peak30 IS NULL THEN NULL
                   ELSE v_r1 * LEAST(v_peak30, COALESCE(v_block, v_peak30))
                        + COALESCE(v_r2, v_r1) * GREATEST(0, v_peak30 - COALESCE(v_block, v_peak30)) END;

  v_amort := GREATEST(1, COALESCE(public.ottoq_policy_get(p_run, 'bess_plan_demand_amortization_days', 30), 30));
  v_deg   := GREATEST(0, COALESCE(public.ottoq_policy_get(p_run, 'bess_plan_degradation_usd_kwh', 0.02), 0.02));
  SELECT avg(b.roundtrip_efficiency_pct), sum(b.current_soc_kwh) INTO v_rt_raw, v_soc_end
    FROM ottoq_bess_units b WHERE b.depot_id = p_depot;
  -- G172: the column holds a fraction (0.96) under a percent's name; read either, exactly as 0435 does
  v_rt := LEAST(1.0, GREATEST(0.5, CASE WHEN v_rt_raw IS NULL THEN 0.96 WHEN v_rt_raw <= 1 THEN v_rt_raw ELSE v_rt_raw / 100 END));
  v_terminal := CASE WHEN p_soc_start_kwh IS NULL OR v_soc_end IS NULL OR v_min_rate IS NULL THEN NULL
                     ELSE (p_soc_start_kwh - v_soc_end) * v_min_rate / v_rt END;

  SELECT count(*), count(*) FILTER (WHERE NOT passed), count(*) FILTER (WHERE NOT passed AND severity = 'safety_critical')
    INTO v_evals, v_fail, v_crit
    FROM ottoq_rule_evaluations WHERE sim_run_id = p_run;
  -- 0430: what the shield recommended beside what the engine did. A safety-critical failure the engine REFUSED
  -- did not happen; any other effect (recorded_only, an advisory posture, an unresolvable one) may have.
  SELECT count(*) FILTER (WHERE e.effect = 'refused'), count(*) FILTER (WHERE e.effect IS DISTINCT FROM 'refused')
    INTO v_crit_ref, v_crit_unp
    FROM public.ottoq_rule_evaluation_effect e
   WHERE e.sim_run_id = p_run AND NOT e.passed AND e.severity = 'safety_critical';
  SELECT count(*) INTO v_dr FROM ottoq_dr_calls WHERE sim_run_id = p_run;
  SELECT count(*) INTO v_defer FROM ottoq_decisions
   WHERE sim_run_id = p_run AND action_context = 'stall_assignment' AND outcome_status = 'deferred_site_power_cap';
  SELECT * INTO v_ab FROM ottoq_ab_runs WHERE sim_run_id = p_run ORDER BY scored_at DESC LIMIT 1;

  RETURN jsonb_build_object(
    -- the five 2.9 KPIs exactly as the reward reads them (per-day KPIs at their maximum day), and the safety floor
    'asset_hours_available_per_day',         v_terms->'asset_hours_available_per_day',
    'service_point_turns_per_point_per_day', v_terms->'service_point_turns_per_point_per_day',
    'peak_site_kw',                          v_terms->'peak_site_kw',
    'touch_events_per_turn',                 v_terms->'touch_events_per_turn',
    'p95_time_to_service_min',               v_terms->'p95_time_to_service_min',
    'returns_unserved',                      NULLIF(v_kpi->>'returns_unserved', '')::numeric,
    'kpi_purged',                            (v_kpi->'purged') IS NOT NULL AND jsonb_typeof(v_kpi->'purged') <> 'null',
    -- the shield
    'rule_evaluations', v_evals, 'rule_failures', v_fail, 'safety_critical_failures', v_crit,
    'safety_critical_refused', v_crit_ref, 'safety_critical_unprevented', v_crit_unp,
    -- operations, from the arm's ottoq_ab_runs row
    'deploys', v_ab.deploys_total, 'trips_completed', v_ab.trips_completed,
    'vehicles_turned_around', v_ab.vehicles_turned_around, 'median_turnaround_min', v_ab.median_turnaround_min,
    'ready_or_deployed_pct', v_ab.ready_or_deployed_pct, 'throughput_per_hr', v_ab.throughput_per_hr,
    'charge_sessions', v_ab.charge_sessions,
    -- energy, realised
    'energy_samples', v_samples,
    'grid_import_kwh', round(v_grid_kwh, 2), 'energy_cost_usd', round(v_cost, 2),
    'peak_30min_kw', round(v_peak30, 1), 'demand_charge_usd_month', round(v_demand, 2),
    'demand_usd_per_day', round(v_demand / v_amort, 2),
    'bess_discharged_kwh', round(v_dis, 1), 'bess_charged_kwh', round(v_chg, 1),
    'bess_degradation_usd', round(v_dis * v_deg, 2),
    'soc_start_kwh', round(p_soc_start_kwh, 1), 'soc_end_kwh', round(v_soc_end, 1),
    'terminal_soc_usd', round(v_terminal, 2),
    'site_cost_usd_per_day', round(v_cost + v_demand / v_amort + v_dis * v_deg + v_terminal, 2),
    'dr_calls', v_dr, 'dr_deferred_assignments', v_defer,
    -- provenance of the arithmetic
    'amortization_days', v_amort, 'degradation_usd_kwh', v_deg, 'roundtrip', v_rt,
    'sim_min_per_tick', round(EXTRACT(EPOCH FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / NULLIF(r.tick_count, 0), 4),
    'ticks', r.tick_count);
END
$function$;

-- ── (5) THE PAIR ──
CREATE OR REPLACE FUNCTION public.ottoq_dial_pair(p_experiment_id uuid, p_seed bigint, p_arm_budget_s integer DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0439 (G161): one common-random-numbers pair for a designed dial experiment. Arm 1 is the CONTROL, arm 2 the
   TREATMENT. The arm protocol is ottoq_determinism_pair's, including 0421's GUC reset, plus ottoq_ab_pair's
   quiesce. The ONLY run-scoped difference between the arms is the experiment's dial. */
DECLARE
  x public.ottoq_dial_experiments%ROWTYPE; v_cat public.ottoq_policy_param_catalog%ROWTYPE;
  v_engine text; v_budget int; v_group uuid; v_scen_depot uuid; v_k text; v_num numeric;
  v_arm int; v_value numeric; v_run uuid; v_t0 timestamptz; v_clock timestamptz; v_status text; v_ticks int;
  v_boot jsonb; v_soc0 numeric; v_h jsonb; v_ab uuid;
  v_arms jsonb[] := '{}'; v_m jsonb[] := '{}';
  v_complete boolean; v_world boolean; v_paid boolean; v_moved jsonb; v_differs boolean; v_delta jsonb;
  v_pair bigint; v_vstatus text;
BEGIN
  SELECT * INTO x FROM public.ottoq_dial_experiments WHERE experiment_id = p_experiment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'dial_pair: no experiment %', p_experiment_id USING ERRCODE = 'P0002'; END IF;
  IF x.status <> 'active' THEN
    RAISE EXCEPTION 'dial_pair: experiment % is %, not active', p_experiment_id, x.status USING ERRCODE = 'P0001';
  END IF;

  -- ONE MOVER. The recertification runner's lock, so a dial pair and a determinism pair never share the world.
  IF NOT pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint) THEN
    RAISE EXCEPTION 'dial_pair: the recertification runner (or another pair) holds the world' USING ERRCODE = '55P03';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION 'dial_pair: a run is live; pairs run between runs' USING ERRCODE = '55006';
  END IF;

  v_engine := public.ottoq_engine_hash();
  IF EXISTS (SELECT 1 FROM public.ottoq_dial_pair_ledger
              WHERE experiment_id = p_experiment_id AND seed = p_seed AND engine_hash = v_engine) THEN
    RAISE EXCEPTION 'dial_pair: seed % is already paired on engine % -- under determinism a re-run is repetition, not replication (G153)',
      p_seed, v_engine USING ERRCODE = '23505';
  END IF;

  -- 0175: the experiment and its scenario must name the same world
  SELECT s.depot_id INTO v_scen_depot FROM public.ottoq_scenarios s WHERE s.scenario_code = x.scenario AND s.status = 'active';
  IF NOT FOUND OR v_scen_depot IS DISTINCT FROM x.depot_id THEN
    RAISE EXCEPTION 'dial_pair: scenario % is not active on depot %', x.scenario, x.depot_id USING ERRCODE = 'P0001';
  END IF;

  -- every value an arm will hold is one the catalog admits, so no arm runs a setting the engine would clamp
  SELECT * INTO v_cat FROM public.ottoq_policy_param_catalog WHERE param_key = x.param_key;
  IF (v_cat.min_value IS NOT NULL AND LEAST(x.control_value, x.treatment_value) < v_cat.min_value)
     OR (v_cat.max_value IS NOT NULL AND GREATEST(x.control_value, x.treatment_value) > v_cat.max_value) THEN
    RAISE EXCEPTION 'dial_pair: % control/treatment (%, %) outside the catalog range [%, %]', x.param_key,
      x.control_value, x.treatment_value, v_cat.min_value, v_cat.max_value USING ERRCODE = '22003';
  END IF;
  FOR v_k IN SELECT jsonb_object_keys(x.fixed_params) LOOP
    IF v_k IN ('cuopt_propose_enabled','cuopt_first_refusal_max_defers','orchestrator_agent_enabled','proposer_seat') THEN
      RAISE EXCEPTION 'dial_pair: fixed param % is one of the harness''s own keys', v_k USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_typeof(x.fixed_params->v_k) <> 'number' THEN
      RAISE EXCEPTION 'dial_pair: fixed param % is not a number', v_k USING ERRCODE = '22023';
    END IF;
    v_num := (x.fixed_params->>v_k)::numeric;
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog c WHERE c.param_key = v_k
                      AND (c.min_value IS NULL OR v_num >= c.min_value) AND (c.max_value IS NULL OR v_num <= c.max_value)) THEN
      RAISE EXCEPTION 'dial_pair: fixed param % = % is uncatalogued or outside its range', v_k, v_num USING ERRCODE = '22003';
    END IF;
  END LOOP;

  v_budget := COALESCE(p_arm_budget_s, GREATEST(240, x.ticks * 30));   -- the recert runner's own budget rule
  v_group  := md5('dial|' || p_experiment_id || '|' || p_seed || '|' || v_engine)::uuid;

  FOR v_arm IN 1..2 LOOP
    v_value := CASE v_arm WHEN 1 THEN x.control_value ELSE x.treatment_value END;
    PERFORM set_config('ottoq.sim_run_id', 'none', true);  /* 0421: the reset runs BEFORE this arm's run exists */
    PERFORM public.ottoq_tick_invariance_reset_fleet(x.depot_id, p_seed, x.sim_start);
    v_run := twin.ottoq_sim_start_run(x.scenario, x.sim_start, 60, p_seed, 'ab_harness');

    -- the deterministic core alone, plus the seat, exactly as ottoq_ab_pair quiesces an arm (0152, 0112, 0261)
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, 'cuopt_propose_enabled', 0, '0439_dial_quiesce'),
           ('run', v_run, 'cuopt_first_refusal_max_defers', 0, '0439_dial_quiesce'),
           ('run', v_run, 'orchestrator_agent_enabled', 0, '0439_dial_quiesce'),
           ('run', v_run, 'proposer_seat', 0, '0439_dial_quiesce')
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
      SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by;
    -- the dials held fixed on both arms, then the one that differs
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    SELECT 'run', v_run, f.key, f.value::numeric, '0439_dial_fixed' FROM jsonb_each_text(x.fixed_params) AS f(key, value)
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
      SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by;
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, x.param_key, v_value, '0439_dial_arm')
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
      SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by;
    UPDATE public.ottoq_sim_runs
       SET payload = COALESCE(payload, '{}'::jsonb)
                  || jsonb_build_object('dial_experiment_id', p_experiment_id, 'dial_arm', v_arm, 'dial_key', x.param_key,
                                        'dial_value', v_value, 'ab_group_id', v_group, 'ab_arm', v_arm, 'proposer_seat', 'otto_q')
     WHERE sim_run_id = v_run;

    BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, x.sim_start, 0.70);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'dial_pair arm % prime failed: %', v_arm, SQLERRM; END;

    v_boot := public.ottoq_boot_state_fingerprint(x.depot_id, v_run);
    SELECT sum(b.current_soc_kwh) INTO v_soc0 FROM public.ottoq_bess_units b WHERE b.depot_id = x.depot_id;

    v_t0 := clock_timestamp();
    LOOP
      SELECT sim_clock_current, status, tick_count INTO v_clock, v_status, v_ticks
        FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
      EXIT WHEN v_status <> 'running' OR v_ticks >= x.ticks;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) >= v_budget;
      PERFORM public.ottoq_sim_advance_tick(v_run);
    END LOOP;

    v_h := public.ottoq_ab_arm_atoms(x.depot_id, v_run)
        || jsonb_build_object('boot', v_boot, 'h_cal', v_boot->'calibration'->>'h',
                              'complete', (SELECT tick_count >= x.ticks FROM public.ottoq_sim_runs WHERE sim_run_id = v_run),
                              'wall_s', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0))::numeric, 1),
                              'dial_value', v_value);
    v_ab := public.ottoq_ab_write_score(v_group, v_run, 'otto_q', v_h);
    v_m := v_m || (public.ottoq_dial_arm_metrics(v_run, x.depot_id, v_soc0)
                   || jsonb_build_object('run', v_run, 'ab_run_id', v_ab, 'dial_value', v_value,
                                         'complete', v_h->'complete', 'wall_s', v_h->'wall_s'));
    v_arms := v_arms || v_h;

    PERFORM public.ottoq_sim_stop_and_reset(v_run, 'dial_arm_complete');
  END LOOP;
  -- stop_and_reset pins the tagging GUC to the run it tore down; whatever this transaction does next (the runner
  -- promotes through the setter, whose policy_write probe logs an evaluation) belongs to no arm
  PERFORM set_config('ottoq.sim_run_id', 'none', true);

  v_complete := COALESCE((v_arms[1]->>'complete')::boolean, false) AND COALESCE((v_arms[2]->>'complete')::boolean, false);
  -- the same world: boot image, priors, and the battery's charge (the energy experiment's state variable)
  v_world := (v_arms[1]->'boot') = (v_arms[2]->'boot')
         AND (v_arms[1]->>'h_cal') = (v_arms[2]->>'h_cal')
         AND (v_m[1]->'soc_start_kwh') IS NOT DISTINCT FROM (v_m[2]->'soc_start_kwh');
  -- db/checks/0146, structurally: a comparison where either arm skipped the shield is not a comparison
  v_paid := COALESCE((v_m[1]->>'rule_evaluations')::bigint, 0) > 0 AND COALESCE((v_m[2]->>'rule_evaluations')::bigint, 0) > 0;
  v_moved := (SELECT COALESCE(jsonb_agg(k ORDER BY k), '[]'::jsonb)
                FROM unnest(ARRAY['fp','h_cmd','h_dec','h_evt','h_bkg','h_nrg','h_prop','h_defr','h_rule','h_rcl','h_sdr',
                                  'ticks','endst','h_arr']) AS k
               WHERE (v_arms[1]->k) IS DISTINCT FROM (v_arms[2]->k));
  v_differs := jsonb_array_length(v_moved) > 0;
  v_delta := (SELECT COALESCE(jsonb_object_agg(e.key, round((v_m[2]->>e.key)::numeric - (e.value #>> '{}')::numeric, 4)), '{}'::jsonb)
                FROM jsonb_each(v_m[1]) AS e(key, value)
               WHERE jsonb_typeof(e.value) = 'number' AND jsonb_typeof(v_m[2]->e.key) = 'number');

  INSERT INTO public.ottoq_dial_pair_ledger
    (experiment_id, seed, engine_hash, run_a, run_b, ab_group_id, complete, world_identical, both_paid_shield,
     differs, moved, metrics_a, metrics_b, delta, wall_s)
  VALUES (p_experiment_id, p_seed, v_engine, (v_m[1]->>'run')::uuid, (v_m[2]->>'run')::uuid, v_group, v_complete, v_world, v_paid,
          v_differs, v_moved, v_m[1], v_m[2], v_delta,
          COALESCE((v_m[1]->>'wall_s')::numeric, 0) + COALESCE((v_m[2]->>'wall_s')::numeric, 0))
  RETURNING pair_id INTO v_pair;

  -- validation_status on a harness arm means THE INSTRUMENT WAS VALID, never that an arm won
  v_vstatus := CASE WHEN NOT v_complete THEN 'inconclusive' WHEN v_world AND v_paid THEN 'passed' ELSE 'failed' END;
  UPDATE public.ottoq_sim_runs
     SET validation_status = v_vstatus,
         validation_notes = jsonb_build_object('kind', 'dial_pair', 'pair_id', v_pair, 'experiment_id', p_experiment_id,
                                               'seed', p_seed, 'complete', v_complete, 'world_identical', v_world,
                                               'both_paid_shield', v_paid, 'moved', v_moved)::text
   WHERE sim_run_id IN ((v_m[1]->>'run')::uuid, (v_m[2]->>'run')::uuid);

  RETURN jsonb_build_object(
    'kind', 'dial_pair', 'pair_id', v_pair, 'experiment_id', p_experiment_id, 'param_key', x.param_key,
    'seed', p_seed, 'engine_hash', v_engine, 'ab_group_id', v_group,
    'valid', v_complete AND v_world AND v_paid, 'complete', v_complete, 'world_identical', v_world,
    'both_paid_shield', v_paid, 'differs', v_differs, 'moved', v_moved,
    'primary', jsonb_build_object('metric', x.primary_metric, 'better', x.primary_better,
                                  'control', v_m[1]->x.primary_metric, 'treatment', v_m[2]->x.primary_metric,
                                  'delta', v_delta->x.primary_metric),
    'delta', v_delta);
END
$function$;

-- ── (6) THE VERDICT ──
CREATE OR REPLACE FUNCTION public.ottoq_dial_counted_pairs(p_experiment_id uuid, p_engine_hash text)
 RETURNS TABLE(k bigint, pair_id bigint, seed bigint, differs boolean, a jsonb, b jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  /* 0439: the pairs the decision rule counts, in the order they ran: this engine, a valid instrument (complete,
     same world, both arms paid the shield), and the primary metric present on both arms. */
  SELECT row_number() OVER (ORDER BY l.pair_id), l.pair_id, l.seed, l.differs, l.metrics_a, l.metrics_b
    FROM public.ottoq_dial_pair_ledger l
    JOIN public.ottoq_dial_experiments x ON x.experiment_id = l.experiment_id
   WHERE l.experiment_id = p_experiment_id AND l.engine_hash = p_engine_hash
     AND l.complete AND l.world_identical AND l.both_paid_shield
     AND jsonb_typeof(l.metrics_a -> x.primary_metric) = 'number'
     AND jsonb_typeof(l.metrics_b -> x.primary_metric) = 'number'
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_dial_experiment_verdict(p_experiment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
/* 0439 (G161): the decision rule of the 0439 header §3, as a pure read over ottoq_dial_pair_ledger. */
DECLARE
  x public.ottoq_dial_experiments%ROWTYPE;
  v_engine text; v_sign numeric; v_weights jsonb; v_alpha_look numeric;
  v_all int := 0; v_stale int := 0; v_invalid int := 0; v_counted int := 0;
  v_unserved_worse int := 0; v_crit_a numeric := 0; v_crit_b numeric := 0;
  v_look int; v_w int := 0; v_l int := 0; v_t int := 0; v_n int := 0;
  v_rel numeric; v_identical boolean := false; v_p_treat numeric; v_p_ctrl numeric;
  v_ref_more int := 0; v_ref_fewer int := 0; v_p_ref numeric;
  v_guard jsonb := '{}'::jsonb; v_breach jsonb := '[]'::jsonb; v_pairs jsonb := '[]'::jsonb;
  v_outcome text; v_terminal boolean := true; v_why text;
BEGIN
  SELECT * INTO x FROM public.ottoq_dial_experiments WHERE experiment_id = p_experiment_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('outcome', 'unknown_experiment', 'terminal', false); END IF;
  v_engine := public.ottoq_engine_hash();
  v_sign := CASE x.primary_better WHEN 'lower' THEN -1 ELSE 1 END;
  SELECT w.weights INTO v_weights FROM public.ottoq_reward_weights w WHERE w.is_active;
  v_alpha_look := x.alpha / 2;   -- two planned looks, Bonferroni

  SELECT count(*),
         count(*) FILTER (WHERE l.engine_hash <> v_engine),
         count(*) FILTER (WHERE l.engine_hash = v_engine AND NOT (l.complete AND l.world_identical AND l.both_paid_shield))
    INTO v_all, v_stale, v_invalid
    FROM public.ottoq_dial_pair_ledger l WHERE l.experiment_id = p_experiment_id;

  -- SAFETY, over EVERY counted pair and not only the look's, so it can stop the experiment early. Only an
  -- UNPREVENTED safety-critical failure is an unsafe outcome; a refused one is shield reliance (a guardrail below).
  SELECT count(*),
         count(*) FILTER (WHERE COALESCE((c.b->>'returns_unserved')::numeric, 0) > COALESCE((c.a->>'returns_unserved')::numeric, 0)),
         COALESCE(sum(COALESCE((c.a->>'safety_critical_unprevented')::numeric, 0)), 0),
         COALESCE(sum(COALESCE((c.b->>'safety_critical_unprevented')::numeric, 0)), 0)
    INTO v_counted, v_unserved_worse, v_crit_a, v_crit_b
    FROM public.ottoq_dial_counted_pairs(p_experiment_id, v_engine) c;

  -- two FIXED looks: the first `first_look_pairs` counted pairs, then the first `final_look_pairs`
  v_look := CASE WHEN v_counted >= x.final_look_pairs THEN x.final_look_pairs
                 WHEN v_counted >= x.first_look_pairs THEN x.first_look_pairs END;

  IF v_look IS NOT NULL THEN
    -- the primary metric over the look's pairs; gain > 0 favours the treatment
    WITH q AS (SELECT * FROM public.ottoq_dial_counted_pairs(p_experiment_id, v_engine) c WHERE c.k <= v_look),
    g AS (SELECT q.k, q.pair_id, q.seed, q.differs,
                 (q.a->>x.primary_metric)::numeric AS pa, (q.b->>x.primary_metric)::numeric AS pb,
                 v_sign * ((q.b->>x.primary_metric)::numeric - (q.a->>x.primary_metric)::numeric) AS gain
            FROM q)
    SELECT count(*) FILTER (WHERE gain > 0), count(*) FILTER (WHERE gain < 0), count(*) FILTER (WHERE gain = 0),
           avg(CASE WHEN pa <> 0 THEN gain / abs(pa) END),
           bool_and(NOT differs),
           COALESCE(jsonb_agg(jsonb_build_object('pair_id', pair_id, 'seed', seed, 'control', pa, 'treatment', pb,
                                                 'gain', round(gain, 4), 'differs', differs) ORDER BY k), '[]'::jsonb)
      INTO v_w, v_l, v_t, v_rel, v_identical, v_pairs
      FROM g;
    v_n := v_w + v_l;
    v_p_treat := public.ottoq_binom_upper_tail(v_n, v_w);
    v_p_ctrl  := public.ottoq_binom_upper_tail(v_n, v_l);

    -- GUARDRAILS over the same pairs: each reward KPI's mean relative change, signed by its active weight so that
    -- positive is better -- the one place the repo already writes down what "better" means for each KPI
    WITH q AS (SELECT * FROM public.ottoq_dial_counted_pairs(p_experiment_id, v_engine) c WHERE c.k <= v_look),
    kk AS (SELECT w.key, sign(w.value::numeric) AS dir FROM jsonb_each_text(COALESCE(v_weights, '{}'::jsonb)) AS w(key, value)),
    ch AS (SELECT kk.key,
                  kk.dir * ((q.b->>kk.key)::numeric - (q.a->>kk.key)::numeric) / NULLIF(abs((q.a->>kk.key)::numeric), 0) AS rel
             FROM q CROSS JOIN kk
            WHERE jsonb_typeof(q.a->kk.key) = 'number' AND jsonb_typeof(q.b->kk.key) = 'number'),
    s AS (SELECT ch.key, avg(ch.rel) AS m, count(ch.rel) AS n FROM ch GROUP BY ch.key)
    SELECT COALESCE(jsonb_object_agg(s.key, jsonb_build_object('mean_change_pct', round(100 * s.m, 3), 'pairs', s.n,
                                     'breach', COALESCE(s.m < -x.guardrail_margin_pct / 100.0, false))), '{}'::jsonb),
           COALESCE(jsonb_agg(s.key ORDER BY s.key) FILTER (WHERE s.m < -x.guardrail_margin_pct / 100.0), '[]'::jsonb)
      INTO v_guard, v_breach
      FROM s;

    -- SHIELD RELIANCE: refusals are small counts (1-2 per arm), where a relative change means nothing, so they
    -- get the sign test, one-sided, at the more sensitive guardrail_alpha
    SELECT count(*) FILTER (WHERE rb > ra), count(*) FILTER (WHERE rb < ra)
      INTO v_ref_more, v_ref_fewer
      FROM (SELECT COALESCE((q.a->>'safety_critical_refused')::numeric, 0) AS ra,
                   COALESCE((q.b->>'safety_critical_refused')::numeric, 0) AS rb
              FROM public.ottoq_dial_counted_pairs(p_experiment_id, v_engine) q WHERE q.k <= v_look) z;
    v_p_ref := public.ottoq_binom_upper_tail(v_ref_more + v_ref_fewer, v_ref_more);
    v_guard := v_guard || jsonb_build_object('safety_critical_refused', jsonb_build_object(
                 'pairs_more', v_ref_more, 'pairs_fewer', v_ref_fewer, 'p', round(v_p_ref, 6),
                 'alpha', x.guardrail_alpha, 'breach', v_ref_more > 0 AND v_p_ref <= x.guardrail_alpha));
    IF v_ref_more > 0 AND v_p_ref <= x.guardrail_alpha THEN
      v_breach := v_breach || to_jsonb('safety_critical_refused'::text);
    END IF;
  END IF;

  IF v_unserved_worse > 0 THEN
    v_outcome := 'safety_regression';
    v_why := format('%s counted pair(s) leave more returns unserved under the treatment; vehicle-first is inviolable', v_unserved_worse);
  ELSIF v_crit_b > v_crit_a THEN
    v_outcome := 'safety_regression';
    v_why := format('the treatment totals %s unprevented safety-critical failures against the control''s %s', v_crit_b, v_crit_a);
  ELSIF v_look IS NULL THEN
    v_outcome := 'collecting'; v_terminal := false;
    v_why := format('%s of %s counted pairs needed for the first look', v_counted, x.first_look_pairs);
  ELSIF v_identical THEN
    v_outcome := 'no_effect';
    v_why := format('both arms of each of the first %s counted pairs are byte-identical on every atom: the dial changes nothing in this world', v_look);
  ELSIF v_p_treat <= v_alpha_look AND COALESCE(v_rel, 0) >= x.min_effect_pct / 100.0 THEN
    IF jsonb_array_length(v_breach) > 0 THEN
      v_outcome := 'guardrail_breach';
      v_why := format('the treatment wins %s (%s of %s, p = %s) and breaches %s (a KPI worse by more than %s%%, or refusals up at p <= %s)',
                      x.primary_metric, v_w, v_n, round(v_p_treat, 5), v_breach::text, x.guardrail_margin_pct, x.guardrail_alpha);
    ELSE
      v_outcome := 'treatment_wins';
      v_why := format('%s of %s non-tied pairs favour the treatment (%s tied), p = %s <= %s, mean gain %s%% on %s',
                      v_w, v_n, v_t, round(v_p_treat, 5), v_alpha_look, round(100 * v_rel, 2), x.primary_metric);
    END IF;
  ELSIF v_p_ctrl <= v_alpha_look THEN
    v_outcome := 'control_holds';
    v_why := format('%s of %s non-tied pairs favour the control, p = %s <= %s', v_l, v_n, round(v_p_ctrl, 5), v_alpha_look);
  ELSIF v_look = x.final_look_pairs AND v_p_treat <= v_alpha_look THEN
    v_outcome := 'negligible_effect';
    v_why := format('significant (p = %s) but the mean gain %s%% is under min_effect_pct %s',
                    round(v_p_treat, 5), round(100 * COALESCE(v_rel, 0), 3), x.min_effect_pct);
  ELSIF v_look = x.final_look_pairs THEN
    v_outcome := 'inconclusive';
    v_why := format('final look: %s wins, %s losses, %s ties; neither direction reaches p <= %s', v_w, v_l, v_t, v_alpha_look);
  ELSE
    v_outcome := 'collecting'; v_terminal := false;
    v_why := format('first look undecided (%s wins, %s losses, %s ties, p = %s); collecting to %s pairs',
                    v_w, v_l, v_t, round(v_p_treat, 5), x.final_look_pairs);
  END IF;

  RETURN jsonb_build_object(
    'experiment_id', p_experiment_id, 'param_key', x.param_key,
    'control', x.control_value, 'treatment', x.treatment_value,
    'outcome', v_outcome, 'terminal', v_terminal, 'why', v_why,
    'engine_hash', v_engine,
    'pairs', jsonb_build_object('recorded', v_all, 'counted', v_counted, 'invalid', v_invalid, 'stale_engine', v_stale),
    'look', v_look, 'alpha', x.alpha, 'alpha_per_look', v_alpha_look,
    'primary', jsonb_build_object('metric', x.primary_metric, 'better', x.primary_better,
                                  'wins', v_w, 'losses', v_l, 'ties', v_t,
                                  'p_treatment', round(v_p_treat, 6), 'p_control', round(v_p_ctrl, 6),
                                  'mean_gain_pct', round(100 * v_rel, 3), 'min_effect_pct', x.min_effect_pct),
    'guardrails', jsonb_build_object('margin_pct', x.guardrail_margin_pct, 'alpha', x.guardrail_alpha,
                                     'kpis', v_guard, 'breached', v_breach),
    'safety', jsonb_build_object('pairs_more_unserved', v_unserved_worse,
                                 'unprevented_control', v_crit_a, 'unprevented_treatment', v_crit_b),
    'look_pairs', v_pairs);
END
$function$;

-- ── (7) THE PROMOTER ──
CREATE OR REPLACE FUNCTION public.ottoq_promote_dial_experiment(p_experiment_id uuid, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/* 0439 (G161): conclude a decided experiment and, when the treatment won, promote it: through the setter, at
   depot scope, with its own forces_recert lineage row. A dry run writes nothing at all. Every terminal verdict
   concludes the experiment, including a win the gates refused, and every outcome is a promotion-ledger row. */
DECLARE
  x public.ottoq_dial_experiments%ROWTYPE; v_cat public.ottoq_policy_param_catalog%ROWTYPE;
  v jsonb; v_incumbent numeric; v_clamped numeric; v_set jsonb; v_outcome text; v_reason text; v_to numeric;
  v_prom bigint; v_wv int; v_lineage text; v_look int;
BEGIN
  SELECT * INTO x FROM public.ottoq_dial_experiments WHERE experiment_id = p_experiment_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'unknown_experiment'); END IF;
  IF x.status <> 'active' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'experiment_not_active', 'status', x.status, 'verdict', x.verdict);
  END IF;
  v := public.ottoq_dial_experiment_verdict(p_experiment_id);
  IF NOT COALESCE((v->>'terminal')::boolean, false) THEN
    RETURN jsonb_build_object('ok', true, 'action', 'none', 'verdict', v);
  END IF;

  SELECT * INTO v_cat FROM public.ottoq_policy_param_catalog WHERE param_key = x.param_key;
  -- the incumbent: what a run at this depot reads today with no run-scope override (ottoq_promote_dials' rule)
  SELECT pp.param_value INTO v_incumbent FROM public.ottoq_policy_params pp
   WHERE pp.param_key = x.param_key
     AND ((pp.scope_type = 'depot' AND pp.scope_id = x.depot_id)
       OR (pp.scope_type = 'global' AND pp.scope_id = '00000000-0000-0000-0000-000000000000'::uuid))
   ORDER BY (pp.scope_type = 'depot') DESC LIMIT 1;
  v_incumbent := COALESCE(v_incumbent, v_cat.default_value);
  SELECT w.weight_version INTO v_wv FROM public.ottoq_reward_weights w WHERE w.is_active;
  v_look := NULLIF(v->>'look', '')::int;

  IF v->>'outcome' <> 'treatment_wins' THEN
    v_outcome := 'concluded'; v_reason := 'verdict_' || (v->>'outcome');
  ELSIF v_incumbent IS DISTINCT FROM x.control_value THEN
    v_outcome := 'refused';
    v_reason := format('incumbent_moved: depot %s now reads %s; the experiment beat %s', x.depot_id, v_incumbent, x.control_value);
  ELSIF COALESCE(public.ottoq_policy_get(NULL, 'dial_promotion_enabled', 0), 0) < 1 THEN
    v_outcome := 'refused'; v_reason := 'gate1_dial_promotion_enabled_is_off';
  ELSIF NOT COALESCE(v_cat.agent_writable, false) THEN
    v_outcome := 'recommended'; v_to := x.treatment_value;
    v_reason := 'dial_is_not_agent_writable: an operator applies it with ottoq_policy_set at depot scope';
  ELSE
    v_to := x.treatment_value;
    -- a value the setter would clamp, or the drift cap would cut, is one the experiment never tested: refuse
    v_clamped := public.ottoq_dial_clamp(x.param_key, x.treatment_value, 'ottoq_prime:promoter');
    IF v_incumbent IS NOT NULL AND v_incumbent <> 0 AND COALESCE(v_cat.agent_max_drift_pct, 0) > 0
       AND abs(x.treatment_value - v_incumbent) > abs(v_incumbent) * v_cat.agent_max_drift_pct / 100.0 THEN
      v_outcome := 'refused';
      v_reason := format('drift_cap: %s -> %s exceeds the catalog''s %s%% step; a capped value is one the experiment never tested',
                         v_incumbent, x.treatment_value, v_cat.agent_max_drift_pct);
    ELSIF v_clamped IS DISTINCT FROM x.treatment_value THEN
      v_outcome := 'refused';
      v_reason := format('envelope: the setter would clamp %s to %s, a value the experiment never tested', x.treatment_value, v_clamped);
    ELSE
      v_outcome := 'enacted'; v_reason := 'treatment_wins_and_every_gate_passed';
    END IF;
  END IF;

  IF p_dry_run THEN
    RETURN jsonb_build_object('ok', true, 'action', 'dry_run', 'outcome', v_outcome, 'reason', v_reason,
                              'from', v_incumbent, 'to', v_to, 'verdict', v);
  END IF;

  IF v_outcome = 'enacted' THEN
    -- through the SETTER, never a direct INSERT: catalog clamp, agent_writable, G65's refusal contract and the
    -- AI.001 probe at policy_write all apply, exactly as for ottoq_promote_dials
    v_set := public.ottoq_policy_set('depot', x.depot_id, x.param_key, x.treatment_value, 'ottoq_prime:promoter');
    IF NOT COALESCE((v_set->>'ok')::boolean, false) THEN
      v_outcome := 'refused'; v_reason := 'setter_refused: ' || COALESCE(v_set->>'error', 'no ok field in response');
    END IF;
  END IF;

  INSERT INTO public.ottoq_dial_promotion_ledger
    (depot_id, param_key, from_value, to_value, outcome, reason, engine_hash, scenario, sim_min_per_tick,
     cell_runs, cell_seeds, weight_version, setter_response, experiment_id, evidence)
  VALUES (x.depot_id, x.param_key, v_incumbent, v_to, v_outcome, v_reason, v->>'engine_hash', x.scenario,
          (SELECT (l.metrics_a->>'sim_min_per_tick')::numeric FROM public.ottoq_dial_pair_ledger l
            WHERE l.experiment_id = p_experiment_id ORDER BY l.pair_id DESC LIMIT 1),
          2 * COALESCE(v_look, 0), COALESCE(v_look, 0), v_wv, v_set, p_experiment_id, v)
  RETURNING promotion_id INTO v_prom;

  IF v_outcome = 'enacted' THEN
    v_lineage := 'dial_promotion_' || v_prom || '_' || x.param_key;
    INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
    VALUES (v_lineage, true,
            format('0439: experiment %s promoted %s %s -> %s at depot %s (%s). Certification arms read depot scope, '
                   'so the canon re-certifies under the new value.',
                   p_experiment_id, x.param_key, v_incumbent, x.treatment_value, x.depot_id, v->>'why'),
            now());
  END IF;

  UPDATE public.ottoq_dial_experiments
     SET status = 'concluded', concluded_at = now(),
         verdict = v || jsonb_build_object('promotion', jsonb_build_object(
                     'promotion_id', v_prom, 'outcome', v_outcome, 'reason', v_reason,
                     'from', v_incumbent, 'to', v_to, 'lineage', v_lineage))
   WHERE experiment_id = p_experiment_id;

  RETURN jsonb_build_object('ok', true, 'action', 'concluded', 'outcome', v_outcome, 'reason', v_reason,
                            'from', v_incumbent, 'to', v_to, 'promotion_id', v_prom, 'lineage', v_lineage,
                            'setter', v_set, 'verdict', v);
END
$function$;

-- ── (8) THE RUNNER ──
CREATE OR REPLACE FUNCTION public.ottoq_dial_experiment_runner()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0439 (G161): at most ONE pair per call, and only in a quiet world. Certification has priority: while any
   enabled canon column is below the recert floor this does nothing, and it takes the recertification runner's
   own lock so the two can never share the world. */
DECLARE
  x public.ottoq_dial_experiments%ROWTYPE; v_engine text; v_seed bigint; v_below int;
  v_res jsonb; v_verdict jsonb; v_prom jsonb;
BEGIN
  IF COALESCE(public.ottoq_policy_get(NULL, 'dial_experiment_runner_enabled', 0), 0) < 1 THEN
    RETURN jsonb_build_object('ran', false, 'why', 'dial_experiment_runner_enabled is 0');
  END IF;
  IF NOT pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint) THEN
    RETURN jsonb_build_object('ran', false, 'why', 'the recertification runner holds the world');
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RETURN jsonb_build_object('ran', false, 'why', 'a run is live');
  END IF;
  SELECT count(*) INTO v_below FROM public.ottoq_determinism_canon WHERE enabled AND NOT satisfies_floor;
  IF v_below > 0 THEN
    RETURN jsonb_build_object('ran', false, 'why', format('certification has priority: %s canon column(s) below the recert floor', v_below));
  END IF;

  v_engine := public.ottoq_engine_hash();
  SELECT e.* INTO x FROM public.ottoq_dial_experiments e
   WHERE e.status = 'active'
   ORDER BY (SELECT count(*) FROM public.ottoq_dial_pair_ledger l
              WHERE l.experiment_id = e.experiment_id AND l.engine_hash = v_engine), e.created_at, e.experiment_id
   LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ran', false, 'why', 'no active experiment'); END IF;

  v_verdict := public.ottoq_dial_experiment_verdict(x.experiment_id);
  IF COALESCE((v_verdict->>'terminal')::boolean, false) THEN
    v_prom := public.ottoq_promote_dial_experiment(x.experiment_id, false);
    RETURN jsonb_build_object('ran', false, 'concluded', x.experiment_id, 'promotion', v_prom - 'verdict');
  END IF;

  -- the next seed of this experiment's own sequence not yet paired on this engine; twice the final look allows
  -- for invalid pairs, and running out is itself a finding, recorded as the experiment's end
  SELECT s.seed INTO v_seed
    FROM generate_series(1, 2 * x.final_look_pairs) AS g(k)
    CROSS JOIN LATERAL (SELECT public.ottoq_dial_experiment_seed(x.experiment_id, g.k) AS seed) s
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_dial_pair_ledger l
                      WHERE l.experiment_id = x.experiment_id AND l.seed = s.seed AND l.engine_hash = v_engine)
   ORDER BY g.k LIMIT 1;
  IF v_seed IS NULL THEN
    UPDATE public.ottoq_dial_experiments
       SET status = 'abandoned', concluded_at = now(),
           verdict = v_verdict || jsonb_build_object('abandoned',
                       format('all %s seeds of the sequence were spent on engine %s without a decision; the invalid pairs say why',
                              2 * x.final_look_pairs, v_engine))
     WHERE experiment_id = x.experiment_id;
    RETURN jsonb_build_object('ran', false, 'abandoned', x.experiment_id);
  END IF;

  v_res := public.ottoq_dial_pair(x.experiment_id, v_seed);
  v_verdict := public.ottoq_dial_experiment_verdict(x.experiment_id);
  IF COALESCE((v_verdict->>'terminal')::boolean, false) THEN
    v_prom := public.ottoq_promote_dial_experiment(x.experiment_id, false) - 'verdict';
  END IF;
  RETURN jsonb_build_object('ran', true, 'pair', v_res - 'delta', 'verdict', v_verdict - 'look_pairs', 'promotion', v_prom);
END
$function$;

REVOKE ALL ON FUNCTION public.ottoq_dial_experiment_seed(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ottoq_binom_upper_tail(integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ottoq_dial_counted_pairs(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ottoq_dial_experiment_verdict(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_dial_experiment_seed(uuid, integer), public.ottoq_binom_upper_tail(integer, integer),
                          public.ottoq_dial_counted_pairs(uuid, text), public.ottoq_dial_experiment_verdict(uuid)
  TO authenticated, service_role;
-- the four that move the world or the dials: service_role only
REVOKE ALL ON FUNCTION public.ottoq_dial_arm_metrics(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_dial_pair(uuid, bigint, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_promote_dial_experiment(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_dial_experiment_runner() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_dial_arm_metrics(uuid, uuid, numeric), public.ottoq_dial_pair(uuid, bigint, integer),
                          public.ottoq_promote_dial_experiment(uuid, boolean), public.ottoq_dial_experiment_runner()
  TO service_role;

-- ── (9) THE OBSERVATIONAL REWARD STOPS SCORING DESIGNED ARMS ──
DO $splice$
DECLARE v_def text; v_new text; v_before bigint; v_after bigint;
BEGIN
  v_def := pg_get_viewdef('public.ottoq_run_reward_ledger'::regclass, true);
  SELECT count(*) INTO v_before FROM public.ottoq_run_reward_ledger;
  v_new := replace(v_def,
    E'           FROM ottoq_run_dial_ledger d\n        ), cell AS (',
    E'           FROM ottoq_run_dial_ledger d\n'
    || E'          WHERE NOT (EXISTS ( SELECT 1 FROM ottoq_dial_pair_ledger pl WHERE pl.run_a = d.sim_run_id OR pl.run_b = d.sim_run_id))\n'
    || E'        ), cell AS (');
  IF v_new = v_def THEN RAISE EXCEPTION '0439 (9): the reward view splice did not apply'; END IF;
  EXECUTE 'CREATE OR REPLACE VIEW public.ottoq_run_reward_ledger AS ' || rtrim(v_new, E'; \n');
  SELECT count(*) INTO v_after FROM public.ottoq_run_reward_ledger;
  IF v_after <> v_before THEN
    RAISE EXCEPTION '0439 (9): the reward view moved from % to % rows with no pair recorded', v_before, v_after;
  END IF;
END $splice$;
COMMENT ON VIEW public.ottoq_run_reward_ledger IS
  'Per-run reward over ottoq_run_dial_ledger, min-max normalised within (engine_hash, scenario, sim_min_per_tick). '
  '0439: designed-experiment arms (ottoq_dial_pair_ledger) are excluded; they are scored paired, by '
  'ottoq_dial_experiment_verdict, and ranking them here as one more observational run is what G161 found wrong.';

-- ── (10) THE SWITCH, AND THE FIRST EXPERIMENT ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('dial_experiment_runner_enabled',
        '0439 (G161): master switch for public.ottoq_dial_experiment_runner (pg_cron every 10 min). When 1, each '
        'firing runs at most ONE common-random-numbers dial pair (a 48-tick determinism pair took 9 minutes on 2026-09-23), and only '
        'when no run is live, every canon column is current and the recertification lock is free. A pair blocks '
        'every other pg_cron job while it runs (G141), so this stays 0 unless an operator chooses a quiet window.',
        0, 0, 1, 'public.ottoq_dial_experiment_runner', false)
ON CONFLICT (param_key) DO NOTHING;

INSERT INTO public.ottoq_dial_experiments
  (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
   primary_metric, primary_better, hypothesis)
VALUES ('0439', '11111111-1111-1111-1111-111111111111', 'energy_reserve_shave', 0, 1,
        '{"bess_day_plan_enabled": 1}'::jsonb, 'busy_day', 48, '2026-09-01 09:00:00+00',
        'site_cost_usd_per_day', 'lower',
        'H1 (0435; G169, G173): on the twin depot, with the day plan on, the reserve-shaving battery lowers the '
        'realised daily site cost -- TOU energy, plus the NCP_30min demand charge amortised over 30 days, plus '
        'battery wear, plus the cost of refilling whatever charge the battery ends the day short -- against the '
        'fixed-factor demand target that certification arms run, by at least 0.5%, without moving asset hours, '
        'turns, peak, touches or time to service more than 2% the wrong way, without one more unserved return or '
        'unprevented safety-critical failure, and without leaning on the shield''s refusals significantly more.');

SELECT cron.schedule('ottoq-dial-experiment-runner', '*/10 * * * *',
                     $cmd$SET statement_timeout = 0; SELECT public.ottoq_dial_experiment_runner();$cmd$);

-- ── V1: the arithmetic ──
DO $$
DECLARE v_seeds bigint[];
BEGIN
  IF public.ottoq_binom_upper_tail(6, 6) <> 0.015625 THEN RAISE EXCEPTION '0439 V1: P(X>=6 | n=6) = %', public.ottoq_binom_upper_tail(6, 6); END IF;
  IF public.ottoq_binom_upper_tail(6, 5) <> 0.109375 THEN RAISE EXCEPTION '0439 V1: P(X>=5 | n=6) = %', public.ottoq_binom_upper_tail(6, 5); END IF;
  IF public.ottoq_binom_upper_tail(5, 5) <> 0.03125 THEN RAISE EXCEPTION '0439 V1: P(X>=5 | n=5) = %', public.ottoq_binom_upper_tail(5, 5); END IF;
  IF public.ottoq_binom_upper_tail(12, 10) <> 0.019287109375 THEN RAISE EXCEPTION '0439 V1: P(X>=10 | n=12) = %', public.ottoq_binom_upper_tail(12, 10); END IF;
  IF public.ottoq_binom_upper_tail(0, 0) <> 1 OR public.ottoq_binom_upper_tail(4, 5) <> 0 THEN
    RAISE EXCEPTION '0439 V1: the tail''s edge cases moved';
  END IF;
  SELECT array_agg(public.ottoq_dial_experiment_seed('00000000-0000-4000-8000-000000000439'::uuid, k) ORDER BY k)
    INTO v_seeds FROM generate_series(1, 24) AS k;
  IF (SELECT count(DISTINCT s) FROM unnest(v_seeds) AS s) <> 24 OR (SELECT min(s) FROM unnest(v_seeds) AS s) <= 0
     OR public.ottoq_dial_experiment_seed('00000000-0000-4000-8000-000000000439'::uuid, 1) <> v_seeds[1] THEN
    RAISE EXCEPTION '0439 V1: the seed sequence is not 24 distinct positive, repeatable seeds';
  END IF;
END $$;

-- ── V2 + V3: the decision rule and the promoter, on synthetic ledger rows, rolled back ──
DO $v2$
DECLARE
  v_x uuid; v_e text := public.ottoq_engine_hash(); v jsonb; v_msg text;
  v_depot uuid := '00000000-0000-4000-8000-000000000439';   -- no depot: the probe must not collide with a real experiment
BEGIN
  BEGIN
    CREATE FUNCTION pg_temp.v0439_pairs(p_x uuid, p_engine text, p_rows jsonb) RETURNS void LANGUAGE sql AS $f$
      INSERT INTO public.ottoq_dial_pair_ledger
        (experiment_id, seed, engine_hash, run_a, run_b, ab_group_id, complete, world_identical, both_paid_shield,
         differs, moved, metrics_a, metrics_b, delta)
      SELECT p_x, (r->>'seed')::bigint, COALESCE(r->>'engine', p_engine), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
             true, true, true, COALESCE((r->>'differs')::boolean, true), '["h_nrg"]'::jsonb,
             jsonb_build_object('site_cost_usd_per_day', (r->>'ca')::numeric,
                                'returns_unserved', COALESCE((r->>'ua')::numeric, 0),
                                'safety_critical_unprevented', COALESCE((r->>'xa')::numeric, 0),
                                'safety_critical_refused', COALESCE((r->>'fa')::numeric, 0),
                                'asset_hours_available_per_day', 100, 'service_point_turns_per_point_per_day', 10,
                                'peak_site_kw', 1500, 'touch_events_per_turn', 1, 'p95_time_to_service_min', 30),
             jsonb_build_object('site_cost_usd_per_day', (r->>'cb')::numeric,
                                'returns_unserved', COALESCE((r->>'ub')::numeric, 0),
                                'safety_critical_unprevented', COALESCE((r->>'xb')::numeric, 0),
                                'safety_critical_refused', COALESCE((r->>'fb')::numeric, 0),
                                'asset_hours_available_per_day', COALESCE((r->>'ahb')::numeric, 100),
                                'service_point_turns_per_point_per_day', 10, 'peak_site_kw', 1400,
                                'touch_events_per_turn', 1, 'p95_time_to_service_min', 30),
             '{}'::jsonb
        FROM jsonb_array_elements(p_rows) AS r
    $f$;

    INSERT INTO public.ottoq_dial_experiments
      (created_by, depot_id, param_key, control_value, treatment_value, scenario, ticks, sim_start,
       primary_metric, primary_better, hypothesis)
    VALUES ('0439_V2', v_depot, 'energy_reserve_shave', 0, 1, 'busy_day', 48, '2026-09-01 09:00:00+00',
            'site_cost_usd_per_day', 'lower', '0439 V2 probe')
    RETURNING experiment_id INTO v_x;

    -- (a) five unanimous pairs: still below the first look
    PERFORM pg_temp.v0439_pairs(v_x, v_e, '[{"seed":1,"ca":1000,"cb":950},{"seed":2,"ca":1000,"cb":955},{"seed":3,"ca":1000,"cb":960},
                                            {"seed":4,"ca":1000,"cb":940},{"seed":5,"ca":1000,"cb":945}]');
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'collecting' OR (v->>'terminal')::boolean THEN RAISE EXCEPTION '0439 V2(a): 5 pairs read %', v->>'outcome'; END IF;
    -- (b) the sixth decides it: 6 of 6, p = 1/64 <= 0.025, gain ~5%
    PERFORM pg_temp.v0439_pairs(v_x, v_e, '[{"seed":6,"ca":1000,"cb":950}]');
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'treatment_wins' OR (v->'primary'->>'p_treatment')::numeric <> 0.015625 THEN
      RAISE EXCEPTION '0439 V2(b): 6 of 6 read % p=%', v->>'outcome', v->'primary'->>'p_treatment';
    END IF;
    -- (c) two pairs lose 10% of asset hours: a mean of -3.3% breaks the 2% guardrail; one pair (-1.7%) does not
    UPDATE public.ottoq_dial_pair_ledger SET metrics_b = jsonb_set(metrics_b, '{asset_hours_available_per_day}', '90')
     WHERE experiment_id = v_x AND seed IN (1, 2);
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'guardrail_breach' THEN RAISE EXCEPTION '0439 V2(c): -3.3%% asset hours read %', v->>'outcome'; END IF;
    UPDATE public.ottoq_dial_pair_ledger SET metrics_b = jsonb_set(metrics_b, '{asset_hours_available_per_day}', '100')
     WHERE experiment_id = v_x AND seed = 2;
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'treatment_wins' THEN RAISE EXCEPTION '0439 V2(c): -1.7%% asset hours read %', v->>'outcome'; END IF;
    -- (d) one more unserved return under the treatment stops it, whatever the cost says
    UPDATE public.ottoq_dial_pair_ledger SET metrics_b = jsonb_set(metrics_b, '{returns_unserved}', '1')
     WHERE experiment_id = v_x AND seed = 3;
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'safety_regression' OR NOT (v->>'terminal')::boolean THEN RAISE EXCEPTION '0439 V2(d): read %', v->>'outcome'; END IF;
    -- (e) five wins and a loss: the first look is undecided (p = 7/64)
    DELETE FROM public.ottoq_dial_pair_ledger WHERE experiment_id = v_x;
    PERFORM pg_temp.v0439_pairs(v_x, v_e, '[{"seed":1,"ca":1000,"cb":950},{"seed":2,"ca":1000,"cb":955},{"seed":3,"ca":1000,"cb":960},
                                            {"seed":4,"ca":1000,"cb":940},{"seed":5,"ca":1000,"cb":945},{"seed":6,"ca":1000,"cb":1010}]');
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'collecting' OR (v->'primary'->>'p_treatment')::numeric <> 0.109375 THEN
      RAISE EXCEPTION '0439 V2(e): read % p=%', v->>'outcome', v->'primary'->>'p_treatment';
    END IF;
    -- (f) to twelve with two more wins and four losses: 7 of 12 at the final look is inconclusive
    PERFORM pg_temp.v0439_pairs(v_x, v_e, '[{"seed":7,"ca":1000,"cb":950},{"seed":8,"ca":1000,"cb":950},{"seed":9,"ca":1000,"cb":1050},
                                            {"seed":10,"ca":1000,"cb":1050},{"seed":11,"ca":1000,"cb":1050},{"seed":12,"ca":1000,"cb":1050}]');
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'inconclusive' OR (v->>'look')::int <> 12 THEN RAISE EXCEPTION '0439 V2(f): read % at look %', v->>'outcome', v->>'look'; END IF;
    -- (g) six losses: the control holds
    DELETE FROM public.ottoq_dial_pair_ledger WHERE experiment_id = v_x;
    PERFORM pg_temp.v0439_pairs(v_x, v_e, '[{"seed":1,"ca":1000,"cb":1050},{"seed":2,"ca":1000,"cb":1050},{"seed":3,"ca":1000,"cb":1050},
                                            {"seed":4,"ca":1000,"cb":1050},{"seed":5,"ca":1000,"cb":1050},{"seed":6,"ca":1000,"cb":1050}]');
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'control_holds' THEN RAISE EXCEPTION '0439 V2(g): read %', v->>'outcome'; END IF;
    -- (h) six byte-identical pairs: the dial is inert in this world
    DELETE FROM public.ottoq_dial_pair_ledger WHERE experiment_id = v_x;
    PERFORM pg_temp.v0439_pairs(v_x, v_e, '[{"seed":1,"ca":1000,"cb":1000,"differs":false},{"seed":2,"ca":1000,"cb":1000,"differs":false},
                                            {"seed":3,"ca":1000,"cb":1000,"differs":false},{"seed":4,"ca":1000,"cb":1000,"differs":false},
                                            {"seed":5,"ca":1000,"cb":1000,"differs":false},{"seed":6,"ca":1000,"cb":1000,"differs":false}]');
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'no_effect' THEN RAISE EXCEPTION '0439 V2(h): read %', v->>'outcome'; END IF;
    -- (i) six wins on another engine are never pooled
    DELETE FROM public.ottoq_dial_pair_ledger WHERE experiment_id = v_x;
    PERFORM pg_temp.v0439_pairs(v_x, v_e, '[{"seed":1,"ca":1000,"cb":950,"engine":"stale"},{"seed":2,"ca":1000,"cb":950,"engine":"stale"},
                                            {"seed":3,"ca":1000,"cb":950,"engine":"stale"},{"seed":4,"ca":1000,"cb":950,"engine":"stale"},
                                            {"seed":5,"ca":1000,"cb":950,"engine":"stale"},{"seed":6,"ca":1000,"cb":950,"engine":"stale"}]');
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'collecting' OR (v->'pairs'->>'stale_engine')::int <> 6 THEN
      RAISE EXCEPTION '0439 V2(i): read % stale %', v->>'outcome', v->'pairs'->>'stale_engine';
    END IF;
    -- (j) twelve unanimous wins of 0.1%: significant and not worth a change
    DELETE FROM public.ottoq_dial_pair_ledger WHERE experiment_id = v_x;
    PERFORM pg_temp.v0439_pairs(v_x, v_e, (SELECT jsonb_agg(jsonb_build_object('seed', g, 'ca', 1000, 'cb', 999)) FROM generate_series(1, 12) g));
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'negligible_effect' THEN RAISE EXCEPTION '0439 V2(j): read %', v->>'outcome'; END IF;
    -- (k) six wins, each with one more REFUSAL under the treatment: shield reliance, p = 1/64 <= 0.20, blocks the
    --     win; the same refusals split three more / three fewer (p = 0.656) do not, and the win stands
    DELETE FROM public.ottoq_dial_pair_ledger WHERE experiment_id = v_x;
    PERFORM pg_temp.v0439_pairs(v_x, v_e, (SELECT jsonb_agg(jsonb_build_object('seed', g, 'ca', 1000, 'cb', 950, 'fa', 2, 'fb', 3))
                                             FROM generate_series(1, 6) g));
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'guardrail_breach' OR NOT (v->'guardrails'->'breached') ? 'safety_critical_refused' THEN
      RAISE EXCEPTION '0439 V2(k): six more-refusal pairs read % %', v->>'outcome', v->'guardrails'->'breached';
    END IF;
    UPDATE public.ottoq_dial_pair_ledger SET metrics_b = jsonb_set(metrics_b, '{safety_critical_refused}', '1')
     WHERE experiment_id = v_x AND seed IN (4, 5, 6);
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'treatment_wins' THEN RAISE EXCEPTION '0439 V2(k): split refusals read %', v->>'outcome'; END IF;
    -- (l) one UNPREVENTED safety-critical failure more under the treatment stops it, whatever the cost says, while
    --     refusals alone (case k) never do
    UPDATE public.ottoq_dial_pair_ledger SET metrics_b = jsonb_set(metrics_b, '{safety_critical_unprevented}', '1')
     WHERE experiment_id = v_x AND seed = 1;
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' <> 'safety_regression' OR (v->'safety'->>'unprevented_treatment')::numeric <> 1 THEN
      RAISE EXCEPTION '0439 V2(l): read % %', v->>'outcome', v->'safety';
    END IF;

    -- V3: the promoter, on a win. A dry run writes nothing; the real call concludes and, if gate 1 is on,
    -- writes the depot row through the setter and its own forces_recert lineage row.
    DELETE FROM public.ottoq_dial_pair_ledger WHERE experiment_id = v_x;
    PERFORM pg_temp.v0439_pairs(v_x, v_e, (SELECT jsonb_agg(jsonb_build_object('seed', g, 'ca', 1000, 'cb', 950)) FROM generate_series(1, 6) g));
    v := public.ottoq_promote_dial_experiment(v_x, true);
    IF v->>'action' <> 'dry_run' OR EXISTS (SELECT 1 FROM public.ottoq_dial_promotion_ledger WHERE experiment_id = v_x)
       OR (SELECT status FROM public.ottoq_dial_experiments WHERE experiment_id = v_x) <> 'active' THEN
      RAISE EXCEPTION '0439 V3: the dry run wrote something or said %', v;
    END IF;
    v := public.ottoq_promote_dial_experiment(v_x, false);
    IF COALESCE(public.ottoq_policy_get(NULL, 'dial_promotion_enabled', 0), 0) >= 1 THEN
      IF v->>'outcome' <> 'enacted'
         OR (SELECT param_value FROM public.ottoq_policy_params
              WHERE scope_type = 'depot' AND scope_id = v_depot AND param_key = 'energy_reserve_shave') IS DISTINCT FROM 1
         OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = v->>'lineage' AND forces_recert) THEN
        RAISE EXCEPTION '0439 V3: gate 1 on, the promotion read %', v - 'verdict';
      END IF;
    ELSE
      IF v->>'outcome' <> 'refused' OR v->>'reason' <> 'gate1_dial_promotion_enabled_is_off' THEN
        RAISE EXCEPTION '0439 V3: gate 1 off, the promotion read %', v - 'verdict';
      END IF;
    END IF;
    IF (SELECT status FROM public.ottoq_dial_experiments WHERE experiment_id = v_x) <> 'concluded'
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_dial_promotion_ledger WHERE experiment_id = v_x) THEN
      RAISE EXCEPTION '0439 V3: the experiment was not concluded and recorded';
    END IF;
    v := public.ottoq_promote_dial_experiment(v_x, false);
    IF v->>'error' <> 'experiment_not_active' THEN RAISE EXCEPTION '0439 V3: a concluded experiment was promoted twice: %', v; END IF;

    RAISE EXCEPTION USING MESSAGE = '0439_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> '0439_probe_rollback' THEN RAISE EXCEPTION '%', v_msg; END IF;
  END;
END $v2$;

-- ── V4: what shipped is what the header says ──
DO $$
DECLARE v_src text; v_i int; v_j int; r jsonb; x record;
BEGIN
  -- the pair resets the tagging GUC BEFORE each arm's fleet reset (0421), in comment-stripped source
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure;
  v_i := position('set_config(''ottoq.sim_run_id'', ''none'', true)' IN v_src);
  v_j := position('ottoq_tick_invariance_reset_fleet' IN v_src);
  IF v_i = 0 OR v_j = 0 OR v_i > v_j THEN RAISE EXCEPTION '0439 V4: the 0421 reset does not precede the fleet reset'; END IF;
  -- the view now excludes designed arms
  IF position('ottoq_dial_pair_ledger' IN pg_get_viewdef('public.ottoq_run_reward_ledger'::regclass, true)) = 0 THEN
    RAISE EXCEPTION '0439 V4: the reward view does not exclude designed arms';
  END IF;
  -- the runner is off and says so; the cron job exists
  r := public.ottoq_dial_experiment_runner();
  IF COALESCE((r->>'ran')::boolean, true) OR r->>'why' <> 'dial_experiment_runner_enabled is 0' THEN
    RAISE EXCEPTION '0439 V4: the runner with its switch off answered %', r;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-dial-experiment-runner' AND active) THEN
    RAISE EXCEPTION '0439 V4: the runner is not scheduled';
  END IF;
  -- the first experiment exists, is active, and reads as collecting with nothing recorded
  SELECT * INTO x FROM public.ottoq_dial_experiments WHERE created_by = '0439' AND param_key = 'energy_reserve_shave';
  IF NOT FOUND OR x.status <> 'active' THEN RAISE EXCEPTION '0439 V4: the first experiment is missing'; END IF;
  r := public.ottoq_dial_experiment_verdict(x.experiment_id);
  IF r->>'outcome' <> 'collecting' OR (r->'pairs'->>'recorded')::int <> 0 THEN
    RAISE EXCEPTION '0439 V4: the first experiment reads %', r;
  END IF;
  -- a pair refuses a seed already paired on this engine without running anything: prove the refusal path
  -- exists in source rather than by running a 9-minute pair inside a migration
  IF position('already paired on engine' IN v_src) = 0 THEN
    RAISE EXCEPTION '0439 V4: the repeated-seed refusal is missing';
  END IF;
  RAISE NOTICE '0439 V4: first experiment % active, runner scheduled and off', x.experiment_id;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0439_the_learning_loop_had_nothing_to_compare_so_it_now_runs_its_own_experiments',
   false,
   'G161. Designed dial experiments: ottoq_dial_experiments, ottoq_dial_pair (CRN pair, one run-scoped dial apart, '
   '0421 reset, ab_pair quiesce, recert lock), ottoq_dial_pair_ledger (evidence), ottoq_dial_arm_metrics (five KPIs, '
   'safety, realised energy cost with terminal SoC), ottoq_dial_experiment_verdict (exact sign test, two looks at '
   'alpha/2, KPI guardrails, a shield-reliance sign test on refusals, a safety floor on unserved returns and '
   'unprevented safety-critical failures), ottoq_promote_dial_experiment (setter at depot scope + its own forces_recert '
   'lineage row), ottoq_dial_experiment_runner (cron every 10 min, dial default 0). ottoq_run_reward_ledger excludes '
   'designed arms. First experiment: energy_reserve_shave 0 -> 1 with the day plan, busy_day 48 ticks. FALSE: no '
   'engine function changes; the reward view has no caller in any tick; nothing runs at apply.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;
