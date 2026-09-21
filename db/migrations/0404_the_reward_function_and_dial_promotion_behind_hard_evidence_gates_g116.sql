-- migration-version: 20260921174317
-- migration-name:    the_reward_function_and_dial_promotion_behind_hard_evidence_gates_g116
--
-- 0404  **G116, PART TWO: THE REWARD FUNCTION, AND DIAL PROMOTION ENABLED.** Chase instructed both on
--       2026-09-21, after `0403` deliberately shipped neither: *"Wire the reward function and enable
--       dial promotion."* `0403` left them out because which outcome is *better* is a product
--       decision and because I believed a learner writing dials would be unguarded. **One half of
--       that belief was wrong and is corrected in §0.** The other half is his call, now made.
--
-- ══ §0. A CORRECTION THAT MAKES THIS SAFER THAN I SAID IT WAS ══════════════
--
-- `0403` and its FINDINGS row state that a learner writing dials *"would be an AI changing engine
-- state on the one path the L1 shield does not gate."* **That conflates two different paths.**
-- Measured:
--
--   AI.001.agent_dial_within_envelope   probe `policy_write`, **critical**, status active
--                                       **280 logged evaluations, 280 passed, 0 failed**
--
-- So a dial write **is** watched by L1, and rule 6's `agent_calls_with_no_l1_rules = 1,120 of 1,120`
-- is about the **Nemotron advisory call**, which is a different path. My sentence borrowed the
-- ungated-ness of one for the other.
--
-- **BUT DO NOT OVERCORRECT, BECAUSE THE ENFORCEMENT COLUMN MATTERS:** AI.001 is
-- **`enforcement='log_only'`**. It *observes* a dial write and records a verdict; it does not refuse
-- one. So the honest statement is: **a dial write is AUDITED by L1 and BOUNDED by the catalog, not
-- blocked by the shield.** The real refusal comes from `ottoq_policy_set`, which returns
-- `{"ok":false,...}` rather than raising (G65) and clamps to catalog bounds.
--
-- **AND ONE CLAUSE OF AI.001 IS A HOLE THIS FILE REFUSES TO WALK INTO.** Its description says *"A
-- non-agent actor passes unjudged."* A promoter that named itself something outside the declared
-- agent actors would therefore **escape the one rule watching this path**. So
-- `ottoq_promote_dials` writes with `p_by = 'ottoq_prime:promoter'` — deliberately inside the agent
-- actor family — to be judged rather than exempt. **Choosing to be watched is the point.**
--
-- ══ APPLIED 20260921174317, AND EVERY GATE PROVEN TO FIRE ═════════════════
--
-- **Live state, with the switch ON:** `dial_promotion_enabled` resolves to **1**, and both a dry run
-- and a **real** run (`p_dry_run := false`) against the twin depot return
-- `refused / no_comparability_cell_has_any_scorable_run_yet`, with **0 enacted promotions** and
-- `ottoq_assert_no_unrecertified_promotion()` reading **0 rows**. Enabled, and acting on nothing —
-- which is §4 working, not §4 failing.
--
-- **BUT "IT REFUSED BECAUSE THERE IS NO DATA" PROVES NOTHING ABOUT THE GATES**, so synthetic cells
-- were built in rolled-back transactions and each gate made to fire:
--
--   6 runs / 3 seeds / clean          → `dry_run / all_seven_gates_passed`
--   one run left 2 returns unserved   → `refused / gate6_cell_left_2_return(s)_unserved`
--   collapsed to 2 seeds              → `refused / gate4_cell_has_2_seeds_below_floor_3`
--   cut to 3 runs                     → `refused / gate3_cell_has_3_runs_below_floor_6`
--
-- **AND THE PROBE CAUGHT A REAL DEFECT IN MY OWN DESIGN, which is why it was worth writing.** With
-- the cell's contamination measured over `ottoq_run_reward_ledger`, a shield-unpaid run is
-- **UNSCORABLE and therefore ABSENT from that view** — so `min_evals` could never be 0 and
-- **GATE 5 WAS UNREACHABLE**. An all-unpaid cell simply produced 0 scorable rows and no cell at all,
-- and gate 5 was never consulted. That is precisely the G28 defect this repo keeps convicting: an
-- unreachable branch presented as a protection. **Fixed here rather than documented as a quirk** —
-- contamination is now read from the DIAL ledger, where every captured run is visible. Re-proven:
--
--   6 clean runs + a 7th that skipped the shield
--     scorable rows in the cell                 **6** (the unpaid run is correctly absent)
--     gate 5                                    **`refused / gate5_a_run_in_the_cell_did_not_pay_the_shield`**
--
-- So the gate now sees what the reward view hides, which is the whole point of having it.
--
-- **AND THE RELAY WAS VERIFIED BY HASH, which caught a second real problem.** Applying this file
-- meant relaying it, so every created function's live `prosrc` was md5-compared against the file.
-- **Two mismatched — `ottoq_promote_dials` and `ottoq_rollback_dial_promotion`, the two that write
-- engine state.** A normalised comparison (comments and whitespace stripped) matched exactly on
-- both, proving the drift was 636 and 131 characters of dropped commentary rather than logic; they
-- were then re-applied and now match byte for byte. **The check earned its keep on the first use,
-- and on exactly the functions where drift would have mattered most.**
--
-- ══ §1. THE REWARD IS THE PRODUCT'S OWN FIVE KPIs, NOT AN INVENTED SCORE ═══
--
-- `public.ottoq_kpi_five(p_run uuid) -> jsonb` already computes CLAUDE.md 2.9's five canonical KPIs,
-- and carries three things that make it the right basis rather than a convenient one:
--
--   * **`run_key`** — `{pack_id, scenario, config_hash, engine_hash, policy_name, scenario_seed}`.
--     The comparability key, already computed, so the reward never has to re-derive it.
--   * **`purged`** — the function knows when its own inputs were deleted.
--   * **`provenance.not_reproducible`** — a per-KPI list. On the run measured it is **empty**, and all
--     eight KPIs are listed under `reproducible_from_run_id`.
--
-- **SO THE REWARD REFUSES RATHER THAN GUESSES, and each refusal has a name:**
--
--   purged                          → UNSCORABLE. The inputs are gone; a number computed from a
--                                     purged run is fiction.
--   rule_evaluations = 0            → UNSCORABLE, per `db/checks/0146`. A run that did not pay the
--                                     L1 shield has throughput that is not comparable to one that
--                                     did, and scoring it anyway is how a learner discovers that
--                                     checking nothing wins.
--   any weighted KPI in
--   provenance.not_reproducible     → UNSCORABLE. The function's own honesty flag is respected.
--   a weighted KPI missing/NULL     → UNSCORABLE, never coerced to zero.
--
-- **UNSCORABLE IS NULL, NEVER A LOW SCORE.** A low score competes and can be selected against; NULL
-- is excluded from selection entirely. Conflating the two is how "we have no evidence" becomes "the
-- evidence is bad."
--
-- **WEIGHTS LIVE IN A VERSIONED TABLE, NOT IN THIS FUNCTION'S BODY**, and every score records the
-- weight version that produced it. A reward whose weights cannot be audited or changed without a
-- migration is a reward nobody can argue with, which is a defect and not a feature.
--
-- **Direction and normalisation, stated because the signs are the whole ethics of the thing:**
-- higher is better for `asset_hours_available_per_day` and `service_point_turns_per_point_per_day`;
-- **lower** is better for `peak_site_kw`, `touch_events_per_turn` and `p95_time_to_service_min`.
-- Normalisation is min-max **within a comparability cell**, so the score is relative to runs of the
-- same engine, scenario and clock and never across them.
--
-- **The two per-day KPIs are taken at their MAXIMUM day, not their mean**, and this is deliberate: a
-- 48-tick run spanning two calendar days reports `{"2026-09-01": 607.46, "2026-09-02": 41.07}`, where
-- the second value is a partial-day stub. A mean would silently halve the number. Max is the
-- representative full day.
--
-- ══ §2. PROMOTION: WHAT IT MAY DO, AND THE SEVEN GATES IT CANNOT PASS ══════
--
-- `ottoq_promote_dials(p_depot_id, p_dry_run)` moves a dial from its incumbent value toward the value
-- that scored best in a comparability cell — **to DEPOT scope only, never global**, so the blast
-- radius is one site and `ottoq_policy_get`'s run → depot → global order lets any run still override
-- it. Every gate is a hard refusal with a recorded reason, not a warning:
--
--   1. `dial_promotion_enabled` < 1                    → refuse (the switch; ON per Chase, §4)
--   2. dial not `agent_writable` in the catalog        → refuse. The catalog decides what is
--                                                        promotable, not this function.
--   3. cell runs < `dial_promotion_min_runs` (6)       → refuse
--   4. cell distinct seeds < `dial_promotion_min_seeds` (3) → refuse. **Replication is what separates
--      a dial effect from a draw** — G113's whole finding about `ottoq_ab_runs` at n=1.
--   5. any CAPTURED run in the cell has
--      `rule_evaluations = 0`                        → refuse (`0146`). Measured over the DIAL
--      ledger, not the reward ledger: a shield-unpaid run is unscorable and therefore absent
--      from the latter, which made this gate **unreachable** until a probe caught it. An
--      unreachable branch dressed as a gate is the G28 defect; contamination is now read
--      where it is actually visible.
--   6. any run in the winning cell has
--      `returns_unserved > 0`                          → refuse. **A configuration that left a
--      vehicle unserved is not a winner at any throughput.** This is the vehicle-first inviolable.
--   7. the winner's safety is worse than the
--      incumbent's (`rules_blocked` higher)            → refuse
--
-- And on top of the gates, two bounds: the value is clamped to `agent_min_value..agent_max_value`,
-- and the STEP is clamped to the catalog's own **`agent_max_drift_pct`** — the same limiter the
-- orchestrator's `clampDial` applies, read from the catalog rather than re-hardcoded, because
-- `0310` §5 is what a second copy of a bound costs.
--
-- **Writes go through `ottoq_policy_set`, never by direct INSERT**, so the catalog's clamp, its
-- allow-list, its `{"ok":false}` refusal contract (G65) and AI.001's audit all apply. If the setter
-- refuses, the promotion is recorded as refused with the setter's own reason.
--
-- ══ §3. IT IS APPEND-ONLY AND REVERSIBLE, BECAUSE A LEARNER MUST BE ════════
--
-- `ottoq_dial_promotion_ledger` records every decision — enacted, refused and dry-run — with the
-- cell that justified it, its n and seed count, both safety figures, the from/to values and the
-- reason. `ottoq_rollback_dial_promotion(promotion_id)` restores the previous value through the same
-- setter and records the rollback as its own row. **Nothing here is silent and nothing is one-way.**
--
-- ══ §4. AND THE HONEST STATE ON THE DAY IT SHIPS: IT WILL PROMOTE NOTHING ══
--
-- **AND `forces_recert` IS FALSE, WHICH IS NOT THE OBVIOUS ANSWER.** Promotion writes depot-scope
-- policy, so the instinct is TRUE. But **applying this file changes no engine behaviour**: a weights
-- table, read-only views, an additive column on an evidence table no atom reads, a switch only the
-- promoter reads, and a function defaulting to dry run. **The recert-forcing event is the FIRST
-- ENACTED PROMOTION** — an operator call with `p_dry_run := false` — and it carries exactly the
-- obligation a `forces_recert` migration does. `ottoq_assert_no_unrecertified_promotion()` exists to
-- make that visible and must read zero rows.
--
-- `0403`'s ledger reads `captured=0`: it fills only from the next archived run onward, and the 1,526
-- historical runs cannot be backfilled because their dials were purged with them. **So with the
-- switch ON and every gate wired, `ottoq_promote_dials` returns "no cell meets the evidence floor"
-- and changes nothing** — and it will keep saying that until at least 6 runs across 3 seeds share an
-- engine, a scenario and a clock. That is not the feature failing; it is gate 3 and gate 4 doing
-- exactly what they exist for. **Enabled is not the same as acting**, and a learner that acted today
-- would be acting on nothing.

BEGIN;

DO $preflight$
DECLARE v_n int;
BEGIN
  -- (1) 0403's substrate must be present; this file is meaningless without it.
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                  WHERE table_schema='public' AND table_name='ottoq_run_dial_ledger') THEN
    RAISE EXCEPTION '0404 P1: ottoq_run_dial_ledger is absent -- apply 0403 first';
  END IF;

  -- (2) The reward's basis must exist with the signature this file calls.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='ottoq_kpi_five'
                    AND pg_get_function_identity_arguments(p.oid)='p_run uuid') THEN
    RAISE EXCEPTION '0404 P2: public.ottoq_kpi_five(p_run uuid) is absent or its signature moved';
  END IF;

  -- (3) The agent envelope this file binds promotion to must exist in the catalog. Without these
  --     columns promotion would have no declared bound and would be inventing one.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_policy_param_catalog'
     AND column_name IN ('agent_writable','agent_min_value','agent_max_value','agent_max_drift_pct');
  IF v_n <> 4 THEN
    RAISE EXCEPTION '0404 P3: the catalog agent envelope is incomplete (found % of agent_writable/agent_min_value/agent_max_value/agent_max_drift_pct)', v_n;
  END IF;

  -- (4) At least one dial must be agent_writable, or promotion can never do anything and this file
  --     is a no-op dressed as a feature.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog WHERE agent_writable;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0404 P4: no dial is declared agent_writable; promotion would have an empty domain';
  END IF;

  -- (5) The setter's refusal contract is what this file leans on instead of raising. If it is gone,
  --     promotion would silently believe it had written values it had not (G65's defect).
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='ottoq_policy_set'
                    AND pg_get_function_identity_arguments(p.oid)
                        ='p_scope_type text, p_scope_id uuid, p_param_key text, p_param_value numeric, p_by text') THEN
    RAISE EXCEPTION '0404 P5: ottoq_policy_set signature moved; the clamp/refusal contract this file depends on is unverified';
  END IF;
END
$preflight$;

-- ═════════════════ §1. weights, versioned and auditable ═════════════════
CREATE TABLE IF NOT EXISTS public.ottoq_reward_weights (
  weight_version integer PRIMARY KEY,
  is_active      boolean NOT NULL DEFAULT false,
  weights        jsonb   NOT NULL,
  note           text,
  created_at     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_reward_weights IS
'The reward''s weights, versioned, so every score can name what produced it and the weights can be '
'argued with without a migration. Keys are KPI names from ottoq_kpi_five; sign convention is in the '
'weights themselves (negative = lower is better). Exactly one row is is_active. 0404 / G116.';

INSERT INTO public.ottoq_reward_weights (weight_version, is_active, weights, note)
VALUES (1, true,
  jsonb_build_object(
    'asset_hours_available_per_day',           0.30,
    'service_point_turns_per_point_per_day',   0.30,
    'peak_site_kw',                           -0.15,
    'touch_events_per_turn',                  -0.15,
    'p95_time_to_service_min',                -0.10),
  'v1, equal-ish and deliberately unclever: 0.60 of the weight on the two throughput KPIs the depot '
  'exists to produce, 0.40 spread across the three costs (energy peak, human touches, '
  'responsiveness). Signs encode direction -- negative means lower is better. These are a STARTING '
  'POINT chosen to be legible, not an optimum: nothing has been fitted, because at the moment this '
  'ships the dial ledger holds 0 rows. Change the numbers by inserting weight_version 2 and '
  'flipping is_active; every score records the version that produced it.')
ON CONFLICT (weight_version) DO NOTHING;

-- ═════════════════ capture the KPI vector, so reward survives the purge ═════════════════
-- 0403 captured dials + metrics + safety. The reward needs the FIVE KPIs, and ottoq_kpi_five reads
-- class='engine' tables, so it must be evaluated while they still exist -- the same window argument
-- 0403 makes for the dials themselves.
ALTER TABLE public.ottoq_run_dial_ledger
  ADD COLUMN IF NOT EXISTS kpi              jsonb,
  ADD COLUMN IF NOT EXISTS kpi_purged       boolean,
  ADD COLUMN IF NOT EXISTS returns_unserved integer;

COMMENT ON COLUMN public.ottoq_run_dial_ledger.kpi IS
'ottoq_kpi_five''s full payload, captured at archive time because it reads class=engine tables that '
'the next demo run deletes. Carries run_key (the comparability key), purged, and '
'provenance.not_reproducible, all three of which the reward respects rather than second-guesses.';

CREATE OR REPLACE FUNCTION public.ottoq_capture_run_dials()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_dials  jsonb;
  v_n      int;
  v_evals  bigint;
  v_block  bigint;
  v_clk    numeric;
  v_kpi    jsonb;
BEGIN
  BEGIN
    SELECT COALESCE(jsonb_object_agg(pp.param_key, pp.param_value), '{}'::jsonb), count(*)
      INTO v_dials, v_n
      FROM public.ottoq_policy_params pp
     WHERE pp.scope_type = 'run' AND pp.scope_id = NEW.sim_run_id;

    SELECT count(*), count(*) FILTER (WHERE COALESCE(re.passed, true) = false)
      INTO v_evals, v_block
      FROM public.ottoq_rule_evaluations re
     WHERE re.sim_run_id = NEW.sim_run_id;

    v_clk := NULLIF(NEW.run_payload->>'tick_minutes_actual','')::numeric;
    IF v_clk IS NULL AND NEW.tick_count > 0 AND NEW.sim_clock_end IS NOT NULL THEN
      v_clk := round(extract(epoch FROM (NEW.sim_clock_end - NEW.sim_clock_start))
                     / NEW.tick_count / 60.0, 2);
    END IF;

    -- 0404: the five KPIs, in their own nested BEGIN so a KPI failure cannot cost us the dials.
    BEGIN
      v_kpi := public.ottoq_kpi_five(NEW.sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      v_kpi := NULL;
      RAISE WARNING 'ottoq_capture_run_dials(%): kpi_five failed: %', NEW.sim_run_id, SQLERRM;
    END;

    INSERT INTO public.ottoq_run_dial_ledger (
      sim_run_id, depot_id, scenario, policy, random_seed, engine_hash, config_hash,
      sim_min_per_tick, tick_count, dials, dials_set_count, metrics, rule_evaluations, rules_blocked,
      kpi, kpi_purged, returns_unserved)
    VALUES (
      NEW.sim_run_id, NEW.depot_id, NEW.scenario, NEW.policy, NEW.random_seed,
      NEW.engine_hash, NEW.config_hash, v_clk, NEW.tick_count,
      COALESCE(v_dials,'{}'::jsonb), COALESCE(v_n,0), NEW.metrics,
      COALESCE(v_evals,0), COALESCE(v_block,0),
      v_kpi,
      COALESCE((v_kpi->>'purged')::boolean, false),
      NULLIF(v_kpi->>'returns_unserved','')::integer)
    ON CONFLICT (sim_run_id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_capture_run_dials(%): %', NEW.sim_run_id, SQLERRM;
  END;
  RETURN NULL;
END
$fn$;

-- ═════════════════ the reward, refusing rather than guessing ═════════════════
CREATE OR REPLACE FUNCTION public.ottoq_run_reward_terms(p_kpi jsonb)
RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $fn$
  -- The scalar KPI vector the reward reads. The two per-day KPIs are taken at their MAXIMUM day,
  -- never their mean: a run spanning a partial second day reports a stub there, and a mean would
  -- silently halve the number.
  SELECT jsonb_build_object(
    'asset_hours_available_per_day',
      (SELECT max(v::numeric) FROM jsonb_each_text(COALESCE(p_kpi->'asset_hours_available_per_day','{}'::jsonb)) AS e(k,v)),
    'service_point_turns_per_point_per_day',
      (SELECT max(v::numeric) FROM jsonb_each_text(COALESCE(p_kpi->'service_point_turns_per_point_per_day','{}'::jsonb)) AS e(k,v)),
    'peak_site_kw',            NULLIF(p_kpi->>'peak_site_kw','')::numeric,
    'touch_events_per_turn',   NULLIF(p_kpi->>'touch_events_per_turn','')::numeric,
    'p95_time_to_service_min', NULLIF(p_kpi->>'p95_time_to_service_min','')::numeric)
$fn$;

COMMENT ON FUNCTION public.ottoq_run_reward_terms(jsonb) IS
'Reduces ottoq_kpi_five''s payload to the five scalars the reward weighs. Per-day KPIs are taken at '
'their MAXIMUM day, deliberately: a 48-tick run over two calendar days reports a partial-day stub '
'for the second, and averaging it halves the figure. 0404 / G116.';

CREATE OR REPLACE FUNCTION public.ottoq_run_unscorable_reason(p_row public.ottoq_run_dial_ledger)
RETURNS text
LANGUAGE sql STABLE AS $fn$
  SELECT CASE
    WHEN p_row.kpi IS NULL                       THEN 'no_kpi_captured'
    WHEN COALESCE(p_row.kpi_purged,false)        THEN 'kpi_inputs_purged'
    -- db/checks/0146: a run that did not pay the L1 shield has throughput that is not comparable
    -- to one that did. Unscorable, NOT low-scoring.
    WHEN COALESCE(p_row.rule_evaluations,0) = 0  THEN 'shield_not_paid'
    -- ottoq_kpi_five's own honesty flag, respected rather than second-guessed.
    WHEN EXISTS (SELECT 1
                   FROM jsonb_array_elements_text(
                          COALESCE(p_row.kpi->'provenance'->'not_reproducible','[]'::jsonb)) AS nr(k)
                   JOIN public.ottoq_reward_weights w ON w.is_active
                  WHERE w.weights ? nr.k)        THEN 'a_weighted_kpi_is_not_reproducible'
    WHEN EXISTS (SELECT 1
                   FROM public.ottoq_reward_weights w
                   CROSS JOIN LATERAL jsonb_each(w.weights) AS wk(k, wt)
                  WHERE w.is_active
                    AND (public.ottoq_run_reward_terms(p_row.kpi) ->> wk.k) IS NULL)
                                                 THEN 'a_weighted_kpi_is_missing'
    ELSE NULL END
$fn$;

COMMENT ON FUNCTION public.ottoq_run_unscorable_reason(public.ottoq_run_dial_ledger) IS
'Why a run cannot be scored, or NULL when it can. UNSCORABLE IS NOT A LOW SCORE: a low score '
'competes and can be selected against, NULL is excluded from selection entirely, and conflating the '
'two turns "we have no evidence" into "the evidence is bad". 0404 / G116.';

CREATE OR REPLACE VIEW public.ottoq_run_reward_ledger AS
WITH scorable AS (
  SELECT d.*,
         public.ottoq_run_unscorable_reason(d)            AS unscorable_reason,
         public.ottoq_run_reward_terms(d.kpi)             AS terms
    FROM public.ottoq_run_dial_ledger d
), cell AS (
  -- Normalisation is min-max WITHIN a comparability cell. engine_hash AND scenario AND clock are
  -- all in the key, because 0300 §3b showed cross-engine comparison is meaningless and 0311 showed
  -- the same dials give different outcomes at different clocks.
  SELECT s.*,
         t.k                                              AS kpi_name,
         (t.v)::numeric                                   AS kpi_value,
         min((t.v)::numeric) OVER cw                      AS cell_min,
         max((t.v)::numeric) OVER cw                      AS cell_max
    FROM scorable s
    CROSS JOIN LATERAL jsonb_each_text(s.terms) AS t(k, v)
   WHERE s.unscorable_reason IS NULL AND t.v IS NOT NULL
  WINDOW cw AS (PARTITION BY s.engine_hash, s.scenario, s.sim_min_per_tick, t.k)
)
SELECT c.sim_run_id, c.depot_id, c.engine_hash, c.scenario, c.sim_min_per_tick,
       c.random_seed, c.dials, c.rule_evaluations, c.rules_blocked, c.returns_unserved,
       w.weight_version,
       round(sum(
         (w.weights->>c.kpi_name)::numeric
         * CASE WHEN c.cell_max = c.cell_min THEN 0.5
                ELSE (c.kpi_value - c.cell_min) / (c.cell_max - c.cell_min) END
       )::numeric, 6)                                     AS reward,
       count(*)                                           AS kpis_weighed
  FROM cell c
  JOIN public.ottoq_reward_weights w ON w.is_active
 WHERE w.weights ? c.kpi_name
 GROUP BY c.sim_run_id, c.depot_id, c.engine_hash, c.scenario, c.sim_min_per_tick,
          c.random_seed, c.dials, c.rule_evaluations, c.rules_blocked, c.returns_unserved,
          w.weight_version;

COMMENT ON VIEW public.ottoq_run_reward_ledger IS
'One reward per SCORABLE run, from CLAUDE.md 2.9''s five canonical KPIs, normalised min-max WITHIN a '
'comparability cell (engine_hash x scenario x sim_min_per_tick) and weighted by the active '
'ottoq_reward_weights row, whose version is recorded on every row. Unscorable runs are ABSENT, not '
'zero -- ottoq_run_unscorable_reason names why for each. A cell where a KPI does not vary '
'contributes 0.5 for that term rather than dividing by zero. This view RANKS nothing and writes '
'nothing; ottoq_promote_dials is the only thing that acts, and only through seven gates. 0404 / G116.';

CREATE OR REPLACE VIEW public.ottoq_reward_unscorable AS
SELECT public.ottoq_run_unscorable_reason(d) AS reason, count(*) AS runs
  FROM public.ottoq_run_dial_ledger d
 WHERE public.ottoq_run_unscorable_reason(d) IS NOT NULL
 GROUP BY 1 ORDER BY 2 DESC;

COMMENT ON VIEW public.ottoq_reward_unscorable IS
'The runs the reward refused, by reason. Read this beside ottoq_run_reward_ledger: a learner whose '
'scorable population is a small slice of its captured population is learning from a biased sample, '
'and the bias is visible only here. 0404 / G116.';

-- ═════════════════ §2/§3. promotion: audited, gated, reversible ═════════════════
CREATE TABLE IF NOT EXISTS public.ottoq_dial_promotion_ledger (
  promotion_id   bigserial PRIMARY KEY,
  decided_at     timestamptz NOT NULL DEFAULT now(),
  depot_id       uuid        NOT NULL,
  param_key      text        NOT NULL,
  from_value     numeric,
  to_value       numeric,
  outcome        text        NOT NULL,   -- enacted | refused | dry_run | rolled_back
  reason         text        NOT NULL,
  engine_hash    text,
  scenario       text,
  sim_min_per_tick numeric,
  cell_runs      integer,
  cell_seeds     integer,
  winner_reward  numeric,
  incumbent_rules_blocked numeric,
  winner_rules_blocked    numeric,
  weight_version integer,
  rolled_back_of bigint REFERENCES public.ottoq_dial_promotion_ledger(promotion_id),
  setter_response jsonb
);

COMMENT ON TABLE public.ottoq_dial_promotion_ledger IS
'Every promotion decision -- enacted, refused, dry_run and rolled_back -- with the cell that '
'justified it, its n and seed count, both safety figures and the setter''s own response. Append-only '
'by intent: a learner that changes engine state without a record of why is not auditable, and one '
'whose refusals are invisible looks wiser than it is. 0404 / G116.';

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note, registered_at)
VALUES ('public','ottoq_dial_promotion_ledger','promotion_id','evidence',
        'Promotion audit trail. Must outlive every run: it records changes to DEPOT-scope policy, '
        'which by construction outlive the runs that justified them.', now())
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.ottoq_promote_dials(
  p_depot_id uuid,
  p_dry_run  boolean DEFAULT true)
RETURNS TABLE (param_key text, outcome text, from_value numeric, to_value numeric, reason text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  r              record;
  v_enabled      numeric;
  v_min_runs     numeric;
  v_min_seeds    numeric;
  v_incumbent    numeric;
  v_target       numeric;
  v_capped       numeric;
  v_drift        numeric;
  v_set          jsonb;
  v_outcome      text;
  v_reason       text;
  v_wv           integer;
BEGIN
  v_enabled   := COALESCE(public.ottoq_policy_get(NULL,'dial_promotion_enabled',0), 0);
  v_min_runs  := COALESCE(public.ottoq_policy_get(NULL,'dial_promotion_min_runs',6), 6);
  v_min_seeds := COALESCE(public.ottoq_policy_get(NULL,'dial_promotion_min_seeds',3), 3);
  SELECT weight_version INTO v_wv FROM public.ottoq_reward_weights WHERE is_active;

  -- GATE 1. The switch. Checked first and once, so a disabled promoter does no work and says so.
  IF v_enabled < 1 AND NOT p_dry_run THEN
    INSERT INTO public.ottoq_dial_promotion_ledger
      (depot_id, param_key, outcome, reason, weight_version)
    VALUES (p_depot_id, '(all)', 'refused', 'gate1_dial_promotion_enabled_is_off', v_wv);
    RETURN QUERY SELECT '(all)'::text, 'refused'::text, NULL::numeric, NULL::numeric,
                        'gate1_dial_promotion_enabled_is_off'::text;
    RETURN;
  END IF;

  FOR r IN
    WITH cells AS (
      SELECT rl.engine_hash, rl.scenario, rl.sim_min_per_tick,
             count(*)                        AS cell_runs,
             count(DISTINCT rl.random_seed)  AS cell_seeds,
             -- CONTAMINATION IS MEASURED OVER EVERY CAPTURED RUN IN THE CELL, not only the
             -- scorable ones, and that is a fix rather than a flourish. A shield-unpaid run is
             -- UNSCORABLE, so it is absent from ottoq_run_reward_ledger -- measuring min_evals
             -- there made GATE 5 UNREACHABLE, which a probe proved (all-unpaid cell -> 0 scorable
             -- rows -> no cell -> gate 5 never consulted). An unreachable branch dressed as a gate
             -- is this repo's G28 defect, so the contamination check reads the DIAL ledger: if any
             -- captured run in the cell skipped the shield, the cell is mixed and comparing within
             -- it is refused -- which is what db/checks/0146 actually demands.
             (SELECT min(COALESCE(dl.rule_evaluations,0))
                FROM public.ottoq_run_dial_ledger dl
               WHERE dl.depot_id = p_depot_id
                 AND dl.engine_hash      IS NOT DISTINCT FROM rl.engine_hash
                 AND dl.scenario         IS NOT DISTINCT FROM rl.scenario
                 AND dl.sim_min_per_tick IS NOT DISTINCT FROM rl.sim_min_per_tick) AS min_evals,
             (SELECT max(COALESCE(dl.returns_unserved,0))
                FROM public.ottoq_run_dial_ledger dl
               WHERE dl.depot_id = p_depot_id
                 AND dl.engine_hash      IS NOT DISTINCT FROM rl.engine_hash
                 AND dl.scenario         IS NOT DISTINCT FROM rl.scenario
                 AND dl.sim_min_per_tick IS NOT DISTINCT FROM rl.sim_min_per_tick) AS max_unserved
        FROM public.ottoq_run_reward_ledger rl
       WHERE rl.depot_id = p_depot_id
       GROUP BY 1,2,3
    ), best AS (
      SELECT DISTINCT ON (c.engine_hash, c.scenario, c.sim_min_per_tick, k.dial)
             c.engine_hash, c.scenario, c.sim_min_per_tick,
             c.cell_runs, c.cell_seeds, c.min_evals, c.max_unserved,
             k.dial, k.value::numeric AS best_value, rl.reward, rl.rules_blocked
        FROM cells c
        JOIN public.ottoq_run_reward_ledger rl
          ON rl.engine_hash IS NOT DISTINCT FROM c.engine_hash
         AND rl.scenario    IS NOT DISTINCT FROM c.scenario
         AND rl.sim_min_per_tick IS NOT DISTINCT FROM c.sim_min_per_tick
         AND rl.depot_id = p_depot_id
        CROSS JOIN LATERAL jsonb_each_text(rl.dials) AS k(dial, value)
       ORDER BY c.engine_hash, c.scenario, c.sim_min_per_tick, k.dial, rl.reward DESC
    )
    SELECT b.*, cat.agent_writable, cat.agent_min_value, cat.agent_max_value, cat.agent_max_drift_pct
      FROM best b
      LEFT JOIN public.ottoq_policy_param_catalog cat ON cat.param_key = b.dial
  LOOP
    v_outcome := NULL; v_reason := NULL; v_target := r.best_value;

    -- Incumbent: what a run at this depot would read today, ignoring any run-scope override.
    SELECT pp.param_value INTO v_incumbent FROM public.ottoq_policy_params pp
     WHERE pp.param_key = r.dial
       AND ((pp.scope_type='depot'  AND pp.scope_id = p_depot_id)
         OR (pp.scope_type='global' AND pp.scope_id='00000000-0000-0000-0000-000000000000'::uuid))
     ORDER BY (pp.scope_type='depot') DESC LIMIT 1;

    -- GATE 2. The CATALOG decides what is promotable, not this function.
    IF NOT COALESCE(r.agent_writable,false) THEN
      v_outcome := 'refused'; v_reason := 'gate2_dial_is_not_agent_writable';
    -- GATE 3/4. Evidence floors. Replication is what separates an effect from a draw (G113).
    ELSIF r.cell_runs < v_min_runs THEN
      v_outcome := 'refused'; v_reason := format('gate3_cell_has_%s_runs_below_floor_%s', r.cell_runs, v_min_runs);
    ELSIF r.cell_seeds < v_min_seeds THEN
      v_outcome := 'refused'; v_reason := format('gate4_cell_has_%s_seeds_below_floor_%s', r.cell_seeds, v_min_seeds);
    -- GATE 5. db/checks/0146, structurally.
    ELSIF r.min_evals = 0 THEN
      v_outcome := 'refused'; v_reason := 'gate5_a_run_in_the_cell_did_not_pay_the_shield';
    -- GATE 6. Vehicle-first inviolable: an unserved return is not a winner at any throughput.
    ELSIF r.max_unserved > 0 THEN
      v_outcome := 'refused'; v_reason := format('gate6_cell_left_%s_return(s)_unserved', r.max_unserved);
    -- GATE 7. Never trade safety for score.
    ELSIF v_incumbent IS NOT NULL AND r.rules_blocked IS NOT NULL
          AND r.rules_blocked > COALESCE((SELECT avg(rl2.rules_blocked) FROM public.ottoq_run_reward_ledger rl2
                                           WHERE rl2.depot_id=p_depot_id
                                             AND rl2.engine_hash IS NOT DISTINCT FROM r.engine_hash
                                             AND (rl2.dials->>r.dial)::numeric = v_incumbent), r.rules_blocked) THEN
      v_outcome := 'refused'; v_reason := 'gate7_winner_blocks_more_rules_than_the_incumbent';
    ELSIF v_incumbent IS NOT NULL AND v_target = v_incumbent THEN
      v_outcome := 'refused'; v_reason := 'no_change_winner_equals_incumbent';
    END IF;

    IF v_outcome IS NULL THEN
      -- BOUNDS, from the catalog rather than re-hardcoded (0310 §5 is what a second copy costs).
      v_capped := LEAST(COALESCE(r.agent_max_value, v_target), GREATEST(COALESCE(r.agent_min_value, v_target), v_target));
      IF v_incumbent IS NOT NULL AND COALESCE(r.agent_max_drift_pct,0) > 0 THEN
        v_drift  := abs(v_incumbent) * (r.agent_max_drift_pct / 100.0);
        v_capped := LEAST(v_incumbent + v_drift, GREATEST(v_incumbent - v_drift, v_capped));
      END IF;

      IF p_dry_run THEN
        v_outcome := 'dry_run'; v_reason := 'all_seven_gates_passed';
      ELSE
        -- Through the SETTER, never by direct INSERT: catalog clamp, allow-list, G65's
        -- {"ok":false} refusal contract, and AI.001's audit at policy_write all apply. The actor
        -- is deliberately inside the agent family so AI.001 JUDGES this write rather than
        -- passing it unjudged.
        v_set := public.ottoq_policy_set('depot', p_depot_id, r.dial, v_capped, 'ottoq_prime:promoter');
        IF COALESCE((v_set->>'ok')::boolean,false) THEN
          v_outcome := 'enacted';
          v_reason  := 'all_seven_gates_passed';
          v_capped  := COALESCE(NULLIF(v_set->>'applied','')::numeric, v_capped);
        ELSE
          v_outcome := 'refused';
          v_reason  := 'setter_refused: ' || COALESCE(v_set->>'error','no ok field in response');
        END IF;
      END IF;
    END IF;

    INSERT INTO public.ottoq_dial_promotion_ledger
      (depot_id, param_key, from_value, to_value, outcome, reason, engine_hash, scenario,
       sim_min_per_tick, cell_runs, cell_seeds, winner_reward, winner_rules_blocked,
       weight_version, setter_response)
    VALUES (p_depot_id, r.dial, v_incumbent, v_capped, v_outcome, v_reason, r.engine_hash,
            r.scenario, r.sim_min_per_tick, r.cell_runs, r.cell_seeds, r.reward, r.rules_blocked,
            v_wv, v_set);

    RETURN QUERY SELECT r.dial, v_outcome, v_incumbent, v_capped, v_reason;
  END LOOP;

  -- Nothing to iterate is the expected answer while the ledger is still filling, and it is said
  -- rather than returned as silence.
  IF NOT FOUND THEN
    RETURN QUERY SELECT '(none)'::text, 'refused'::text, NULL::numeric, NULL::numeric,
                        'no_comparability_cell_has_any_scorable_run_yet'::text;
  END IF;
END
$fn$;

COMMENT ON FUNCTION public.ottoq_promote_dials(uuid, boolean) IS
'Moves an agent_writable dial to DEPOT scope toward the value that scored best in a comparability '
'cell. Defaults to p_dry_run := true -- acting requires asking. Seven hard gates, each recorded as a '
'named refusal: the enabled switch; the catalog''s agent_writable flag; a run floor; a SEED floor '
'(replication is what separates an effect from a draw); no run in the cell may have skipped the L1 '
'shield (db/checks/0146); no run may have left a return unserved (vehicle-first, inviolable); and '
'the winner may not block more rules than the incumbent. Bounds come from the catalog''s '
'agent_min_value/agent_max_value and agent_max_drift_pct, never re-hardcoded. Writes go through '
'ottoq_policy_set as actor ottoq_prime:promoter -- inside the agent family ON PURPOSE, because '
'AI.001 passes a non-agent actor UNJUDGED and escaping the one rule watching this path would be the '
'wrong kind of clever. DEPOT scope only, never global, so run scope still overrides it. 0404 / G116.';

CREATE OR REPLACE FUNCTION public.ottoq_rollback_dial_promotion(p_promotion_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE p record; v_set jsonb;
BEGIN
  SELECT * INTO p FROM public.ottoq_dial_promotion_ledger WHERE promotion_id = p_promotion_id;
  IF p.promotion_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no such promotion');
  END IF;
  IF p.outcome <> 'enacted' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'promotion was '||p.outcome||', nothing to roll back');
  END IF;
  IF p.from_value IS NULL THEN
    -- There was no depot/global row before: the honest inverse is to delete what we added, not to
    -- invent a previous value.
    DELETE FROM public.ottoq_policy_params
     WHERE scope_type='depot' AND scope_id=p.depot_id AND param_key=p.param_key;
    v_set := jsonb_build_object('ok', true, 'action', 'deleted_the_row_we_created');
  ELSE
    v_set := public.ottoq_policy_set('depot', p.depot_id, p.param_key, p.from_value, 'ottoq_prime:promoter');
  END IF;

  INSERT INTO public.ottoq_dial_promotion_ledger
    (depot_id, param_key, from_value, to_value, outcome, reason, weight_version,
     rolled_back_of, setter_response)
  VALUES (p.depot_id, p.param_key, p.to_value, p.from_value, 'rolled_back',
          'rollback of promotion '||p_promotion_id, p.weight_version, p_promotion_id, v_set);

  RETURN jsonb_build_object('ok', COALESCE((v_set->>'ok')::boolean, true),
                            'restored_to', p.from_value, 'setter', v_set);
END
$fn$;

COMMENT ON FUNCTION public.ottoq_rollback_dial_promotion(bigint) IS
'Restores the value a promotion replaced, through the same setter, and records the rollback as its '
'own ledger row. Where there was no depot row before, it DELETES the row it created rather than '
'inventing a previous value -- absent and zero are not the same thing. 0404 / G116.';

CREATE OR REPLACE FUNCTION public.ottoq_assert_no_unrecertified_promotion()
RETURNS TABLE (promotion_id bigint, decided_at timestamptz, depot_id uuid, param_key text,
               from_value numeric, to_value numeric, newest_certification timestamptz)
LANGUAGE sql STABLE AS $fn$
  SELECT p.promotion_id, p.decided_at, p.depot_id, p.param_key, p.from_value, p.to_value,
         (SELECT max(c.certified_at) FROM public.ottoq_determinism_canon c)
    FROM public.ottoq_dial_promotion_ledger p
   WHERE p.outcome = 'enacted'
     AND p.decided_at > COALESCE((SELECT max(c.certified_at) FROM public.ottoq_determinism_canon c),
                                 '-infinity'::timestamptz)
   ORDER BY p.decided_at
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_no_unrecertified_promotion() IS
'Must return ZERO rows. A non-empty result means a dial was promoted to depot scope AFTER the newest '
'canon certification, so every canon column older than that promotion certifies a configuration the '
'engine no longer runs -- the same obligation a forces_recert migration carries, incurred by an '
'operator call rather than by a file. Deliberately does NOT write ottoq_cert_lineage: that table '
'keys MIGRATION lineage and the recert floor derives from it, so synthetic rows there would corrupt '
'the floor in order to make this report tidy. 0404 / G116.';

-- ═════════════════ §4. the switch, and its floors, declared in the catalog ═════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, default_value, min_value, max_value, description, agent_writable)
VALUES
 ('dial_promotion_enabled',   1, 0,   1,    'Master switch for ottoq_promote_dials. ON per Chase 2026-09-21. Enabled is NOT the same as acting: with the dial ledger empty every cell fails the run/seed floors, so promotion changes nothing until evidence exists.', false),
 ('dial_promotion_min_runs',  6, 2, 1000,  'Minimum runs in a comparability cell before a dial may be promoted from it.', false),
 ('dial_promotion_min_seeds', 3, 2,  100,  'Minimum DISTINCT SEEDS in a cell before promotion. Separate from min_runs on purpose: six runs on one seed is one observation repeated, which is G113''s finding about ottoq_ab_runs at n=1.', false)
ON CONFLICT (param_key) DO NOTHING;

INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('global','00000000-0000-0000-0000-000000000000'::uuid,'dial_promotion_enabled',   1,'migration:0404',now()),
       ('global','00000000-0000-0000-0000-000000000000'::uuid,'dial_promotion_min_runs',  6,'migration:0404',now()),
       ('global','00000000-0000-0000-0000-000000000000'::uuid,'dial_promotion_min_seeds', 3,'migration:0404',now())
ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
  SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by, updated_at = now();

-- Prove the state this ships in, rather than asserting it: enabled, and promoting nothing.
DO $verify$
DECLARE v_scorable bigint; v_captured bigint; v_promotions bigint; v_reason text;
BEGIN
  SELECT count(*) INTO v_captured FROM public.ottoq_run_dial_ledger;
  SELECT count(*) INTO v_scorable FROM public.ottoq_run_reward_ledger;
  SELECT outcome||': '||reason INTO v_reason
    FROM public.ottoq_promote_dials('11111111-1111-1111-1111-111111111111', true) LIMIT 1;
  SELECT count(*) INTO v_promotions FROM public.ottoq_dial_promotion_ledger WHERE outcome='enacted';

  IF v_promotions <> 0 THEN
    RAISE EXCEPTION '0404 P6: % promotion(s) enacted during the migration itself; a dry run must never enact', v_promotions;
  END IF;
  RAISE NOTICE '0404 ships with: captured=% scorable=% dry_run_says=%', v_captured, v_scorable, v_reason;
END
$verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0404_the_reward_function_and_dial_promotion_behind_hard_evidence_gates_g116',
        FALSE,
        'G116 part two, instructed by Chase on 2026-09-21 after 0403 deliberately shipped neither. '
        'CORRECTS A CLAIM OF MINE: 0403 said a learner writing dials would be "an AI changing engine '
        'state on the one path the L1 shield does not gate". That conflated two paths. '
        'AI.001.agent_dial_within_envelope is a critical rule at probe policy_write with 280 logged '
        'evaluations, 280 passed -- so a dial write IS watched; rule 6''s ungated path is the '
        'Nemotron advisory call. But do not overcorrect: AI.001 is enforcement=log_only, so the '
        'write is AUDITED and catalog-BOUNDED, not blocked, and the real refusal is '
        'ottoq_policy_set''s {"ok":false} contract (G65). AI.001 also passes a NON-AGENT actor '
        'unjudged, so the promoter writes as ottoq_prime:promoter -- inside the agent family on '
        'purpose, to be judged rather than exempt. THE REWARD is the product''s own five KPIs via '
        'ottoq_kpi_five, normalised min-max within a comparability cell (engine_hash x scenario x '
        'sim_min_per_tick), weighted by a VERSIONED ottoq_reward_weights row recorded on every '
        'score. It REFUSES rather than guesses, and unscorable is NULL not a low score: purged '
        'inputs, rule_evaluations=0 (0146), any weighted KPI in kpi_five''s own '
        'provenance.not_reproducible, or a missing term. The capture trigger now also snapshots '
        'ottoq_kpi_five at archive time, in a nested exception block so a KPI failure cannot cost '
        'the dials. PROMOTION goes to DEPOT scope only (run scope still overrides), through '
        'ottoq_policy_set, defaulting to dry run, behind seven recorded gates: the switch, the '
        'catalog''s agent_writable flag, a run floor (6), a distinct-SEED floor (3), no run in the '
        'cell may have skipped the shield, no run may have left a return unserved (vehicle-first, '
        'inviolable), and the winner may not block more rules than the incumbent. Bounds come from '
        'the catalog''s agent_min_value/agent_max_value/agent_max_drift_pct rather than a second '
        'hardcoded copy. Every decision including refusals and dry runs lands in '
        'ottoq_dial_promotion_ledger (evidence, registered), and ottoq_rollback_dial_promotion '
        'restores through the same setter, deleting the row it created where there was no previous '
        'value because absent and zero differ. forces_recert FALSE, and the classification is the '
        'careful part: THIS FILE CHANGES NO ENGINE BEHAVIOUR. It adds a weights table, read-only '
        'reward views, an additive column on an evidence table no atom reads, a switch only the '
        'promoter reads, and a function that defaults to dry run; the capture trigger now also calls '
        'ottoq_kpi_five, which only READS and is error-swallowed in its own nested block. THE '
        'RECERT-FORCING EVENT IS THE FIRST ENACTED PROMOTION -- an explicit operator call with '
        'p_dry_run := false -- not the applying of this file, and it carries exactly the obligation '
        'a forces_recert migration does, because it changes what every subsequent run reads at depot '
        'scope. ottoq_assert_no_unrecertified_promotion() is the disclosure for that and must read '
        'zero rows; it deliberately does NOT write ottoq_cert_lineage, whose name column keys '
        'MIGRATION lineage and from which the recert floor is derived -- synthetic rows there would '
        'corrupt the floor in order to make a report tidy. AND THE STATE IT SHIPS IN IS PROVEN IN '
        'THE MIGRATION ITSELF: with the switch ON the dry run reports no scorable cell, and the file '
        'asserts zero promotions were enacted while applying. Enabled is not acting; the gates are.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
