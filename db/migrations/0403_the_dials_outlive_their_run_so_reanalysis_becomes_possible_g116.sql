-- migration-version: 20260921172038
-- migration-name:    the_dials_outlive_their_run_so_reanalysis_becomes_possible_g116
--
-- 0403  **THE PREREQUISITE FOR ANY LEARNING: THE DIALS OUTLIVE THEIR RUN.** `db/checks/0313` §3
--       measured that the engine cannot learn from itself for one structural reason — not a missing
--       algorithm, a missing *input*. `ottoq_prime` has set dials **1,351 times across 6 keys and
--       every single write is `scope_type='run'`**, so the agent's choices are deleted by
--       `ottoq_purge_prior_runs` before anything could correlate them with what they produced. This
--       file makes the choice survive the run that made it.
--
-- ══ APPLIED 20260921172038, AND PROVEN ON A ROLLED-BACK PROBE ═════════════
--
-- **An error-swallowing trigger that silently writes nothing is the exact defect this repo keeps
-- convicting, so it was proven rather than assumed.** A synthetic run was given two run-scope dials
-- and then archived; the trigger fired on that insert:
--
--   ledger rows for the probe run   **1**
--   dials captured                  **{"deploy_peak_fraction": 0.85, "energy_demand_factor_peak": 0.55}**
--   clock captured                  **30.0**, from `run_payload.tick_minutes_actual`
--   rule_evaluations                **0** — correct, the synthetic run logged none
--   reanalysis view rows            **2**, one per dial
--
-- The `rule_evaluations = 0` is the guard working rather than a gap: those two cells read
-- `every_run_paid_the_shield = false`, which is precisely the flag that tells a reader their
-- throughput columns are not comparable. Probe aborted by `RAISE`; residue in the ledger afterwards
-- is **0 rows**, verified.
--
-- **Readiness immediately after applying, as expected:** `captured=0 with_dials=0 cells=0
-- replicated=0 paid_shield=0`. It fills only from the next archived run onward — see the last
-- paragraph of this header for why that is permanent.
--
-- ══ WHAT ALREADY EXISTS, AND IS BETTER THAN EXPECTED ═══════════════════════
--
-- The OUTCOME half is already durable. `ottoq_run_archives` holds **1,526 rows** at
-- `class='run_ledger'`, and carries `scenario`, `policy`, `random_seed`, `tick_count`,
-- `sim_clock_start/end`, `config_hash`, `engine_hash`, a `metrics` object
-- (`charge_sessions`, `commands_issued`, **`commands_refused`**, `dispatches`, `events_generated`,
-- `tasks_completed`, `vehicles_simulated`) and a `run_payload` that already records
-- **`tick_minutes_actual`** and `world_fingerprint`. So the clock — the thing `0402` found the
-- *verdict* tables could not state — is recorded per run here.
--
-- **Measured comparability, which is what decides whether reanalysis is possible at all:**
--
--   comparability cells (engine_hash × scenario × clock)   **198**
--   …with n ≥ 2                                            **130**
--   …with n ≥ 5                                             **52**
--   largest single cell        **n=408**, 8 seeds, 1 policy, `busy_day`, 30.00 min/tick
--   cells that vary POLICY within the cell                   **0**
--   archives recording the DIALS                             **0 of 1,526**
--
-- So the population is strong and the instrument is one column short. **Capture the dials and that
-- 408-run cell becomes a real learning population** — for dial settings, not for policies, because
-- no cell varies policy (which is G113/`0146`'s open gap and is NOT what this file addresses).
--
-- ══ WHY A TRIGGER ON THE ARCHIVE, AND NOT AN EDIT TO `ottoq_archive_run` ═══
--
-- `public.ottoq_archive_run` is the single writer of the archive, so editing it is the obvious move.
-- **Deliberately not done.** It runs inside certified pairs, and `run_payload` already carries
-- `world_fingerprint`; widening what a certified path writes to reach a reporting goal is how a
-- certification round breaks. Instead: an **AFTER INSERT trigger** writing a **separate evidence
-- table that no atom reads**, with an error-swallowing body so it can never fail an archive. This is
-- exactly `0340`'s shape for the model-call ledger, which this repo has already validated.
--
-- **AND THE TIMING WINDOW IS THE WHOLE TRICK.** Archiving happens at run END; `ottoq_purge_prior_runs`
-- deletes `class='engine'` data at the START of the NEXT demo run. So at archive time the run's own
-- `scope_type='run'` policy rows are still present, and its rule evaluations are still countable.
-- **That window is the only moment both the dials and the outcome exist together**, which is why the
-- capture hangs off the archive rather than running later as a sweep.
--
-- ══ SAFETY TRAVELS WITH THROUGHPUT, BECAUSE `0146` SAYS IT MUST ════════════
--
-- `0146` established that the baselines do not pay the L1 shield, so a learner rewarded on throughput
-- alone would learn to prefer whichever configuration checks least — arithmetically correct and
-- worthless. The ledger therefore captures `rule_evaluations` and `rules_blocked` for the run **in
-- the same row** as the dials, and the reanalysis view below refuses to expose a throughput column
-- without them. A reward function is **not** defined here: that is a product decision, and this file
-- deliberately stops at making one possible.
--
-- `forces_recert` **FALSE**, on the same measurable ground as `0402`: this creates a table, a trigger
-- that writes only that table, and a view. **No atom reads any of them**, and nothing hashed can read
-- an object that did not exist. The trigger's body is wrapped so a failure inside it cannot roll back
-- the archive insert it observes.

BEGIN;

DO $preflight$
DECLARE v_n int;
BEGIN
  -- (1) The archive is the durable substrate this file hangs off, and is registered as such.
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_name='ottoq_run_archives' AND class='run_ledger') THEN
    RAISE EXCEPTION '0403 P1: ottoq_run_archives is no longer registered class=run_ledger; re-read the registry before hanging durable capture off it';
  END IF;

  -- (2) The dials live where this file expects, and are still run-scoped. If they have moved to
  --     depot or global scope the premise of this migration is gone and it should not be applied.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE updated_by='ottoq_prime' AND scope_type <> 'run';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0403 P2: % agent dial row(s) are no longer run-scoped -- the "choices do not survive" premise has changed; re-measure', v_n;
  END IF;

  -- (3) The columns the capture reads must exist, or it would silently write nulls.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_policy_params'
     AND column_name IN ('scope_type','scope_id','param_key','param_value');
  IF v_n <> 4 THEN
    RAISE EXCEPTION '0403 P3: ottoq_policy_params is missing one of scope_type/scope_id/param_key/param_value (found % of 4)', v_n;
  END IF;

  -- (4) The archive still carries the comparability keys the view groups on. Without engine_hash
  --     the view would compare runs from different engines, which is 0300 §3b's defect.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_run_archives'
     AND column_name IN ('engine_hash','scenario','tick_count','sim_clock_start','sim_clock_end','metrics','run_payload','random_seed','policy');
  IF v_n <> 9 THEN
    RAISE EXCEPTION '0403 P4: ottoq_run_archives is missing one of the 9 comparability/outcome columns (found %)', v_n;
  END IF;

  -- (5) ottoq_rule_evaluations must still be the shield's log, or the safety half of every row is
  --     silently zero and 0146's trap reopens without anyone noticing.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='ottoq_rule_evaluations'
                    AND column_name='sim_run_id') THEN
    RAISE EXCEPTION '0403 P5: ottoq_rule_evaluations has no sim_run_id; the per-run safety counter this ledger promises cannot be computed';
  END IF;
END
$preflight$;

CREATE TABLE IF NOT EXISTS public.ottoq_run_dial_ledger (
  sim_run_id        uuid PRIMARY KEY,
  captured_at       timestamptz NOT NULL DEFAULT now(),
  depot_id          uuid,
  scenario          text,
  policy            text,
  random_seed       bigint,
  engine_hash       text,
  config_hash       text,
  -- The clock, so a number is never compared across granularities. 0402's lesson, applied at
  -- capture time rather than derived later: tick_minutes_actual is what the archive itself recorded.
  sim_min_per_tick  numeric,
  tick_count        integer,
  -- THE MISSING INPUT: every policy row in force for this run, as {param_key: value}.
  dials             jsonb NOT NULL DEFAULT '{}'::jsonb,
  dials_set_count   integer NOT NULL DEFAULT 0,
  -- OUTCOME, copied at capture time because its sources are class='engine' and purge.
  metrics           jsonb,
  -- SAFETY, travelling in the same row as throughput because 0146 requires it.
  rule_evaluations  bigint,
  rules_blocked     bigint
);

COMMENT ON TABLE public.ottoq_run_dial_ledger IS
'One row per archived run: the DIALS IN FORCE, the clock, the outcome metrics and the safety '
'counters, captured in the one moment they all exist together. Exists because agent dial settings '
'are written at scope_type=run (1,351 of 1,351) and ottoq_purge_prior_runs deletes them, so the '
'engine could not correlate a choice with what it produced -- 0 of 1,526 archives recorded a dial. '
'class=evidence: this must outlive its run, like ottoq_model_call_ledger (0340) and for the same '
'reason. Safety counters are NOT optional decoration: per db/checks/0146 the baselines do not pay '
'the L1 shield, so anything scoring throughput without them learns to prefer whichever '
'configuration checks least. NO reward function is defined anywhere in this file -- that is a '
'product decision. 0403 / G116.';

COMMENT ON COLUMN public.ottoq_run_dial_ledger.sim_min_per_tick IS
'SIM minutes advanced per tick, taken from the archive''s own run_payload.tick_minutes_actual. Never '
'compare outcomes across different values of this column: 0311 measured that the begin_charge chain '
'cannot complete inside a charge window with less than about one tick of budget left, so the same '
'dials produce different outcomes at 30.00 and at 2.00 min/tick.';

-- Registered so the purge check can never mistake this for run-scoped working data.
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note, registered_at)
VALUES ('public','ottoq_run_dial_ledger','sim_run_id','evidence',
        'Per-run dial settings + outcome + safety, captured at archive time. MUST survive '
        'ottoq_purge_prior_runs: it exists precisely because the dials it records do not. '
        'Deliberately no FK to ottoq_sim_runs -- the run it describes is purged while this row '
        'remains, exactly as 0340 established for ottoq_model_call_ledger.', now())
ON CONFLICT DO NOTHING;

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
BEGIN
  -- Error-swallowing by construction: archiving a run must never fail because a reporting ledger
  -- did. 0340's capture triggers are the precedent.
  BEGIN
    SELECT COALESCE(jsonb_object_agg(pp.param_key, pp.param_value), '{}'::jsonb), count(*)
      INTO v_dials, v_n
      FROM public.ottoq_policy_params pp
     WHERE pp.scope_type = 'run' AND pp.scope_id = NEW.sim_run_id;

    SELECT count(*), count(*) FILTER (WHERE COALESCE(re.passed, true) = false)
      INTO v_evals, v_block
      FROM public.ottoq_rule_evaluations re
     WHERE re.sim_run_id = NEW.sim_run_id;

    -- The clock the archive itself recorded, preferred over re-deriving it.
    v_clk := NULLIF(NEW.run_payload->>'tick_minutes_actual','')::numeric;
    IF v_clk IS NULL AND NEW.tick_count > 0 AND NEW.sim_clock_end IS NOT NULL THEN
      v_clk := round(extract(epoch FROM (NEW.sim_clock_end - NEW.sim_clock_start))
                     / NEW.tick_count / 60.0, 2);
    END IF;

    INSERT INTO public.ottoq_run_dial_ledger (
      sim_run_id, depot_id, scenario, policy, random_seed, engine_hash, config_hash,
      sim_min_per_tick, tick_count, dials, dials_set_count, metrics, rule_evaluations, rules_blocked)
    VALUES (
      NEW.sim_run_id, NEW.depot_id, NEW.scenario, NEW.policy, NEW.random_seed,
      NEW.engine_hash, NEW.config_hash, v_clk, NEW.tick_count,
      COALESCE(v_dials,'{}'::jsonb), COALESCE(v_n,0), NEW.metrics,
      COALESCE(v_evals,0), COALESCE(v_block,0))
    ON CONFLICT (sim_run_id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_capture_run_dials(%): %', NEW.sim_run_id, SQLERRM;
  END;
  RETURN NULL;
END
$fn$;

COMMENT ON FUNCTION public.ottoq_capture_run_dials() IS
'AFTER INSERT on ottoq_run_archives: snapshots the run''s scope_type=run policy rows before '
'ottoq_purge_prior_runs deletes them, alongside the outcome and safety counters. Fires at the only '
'moment dials and outcome coexist. Error-swallowing: archiving must never fail because reporting '
'did (0340''s precedent). Hung off the archive rather than added to ottoq_archive_run, which runs '
'inside certified pairs. 0403 / G116.';

DROP TRIGGER IF EXISTS trg_ottoq_capture_run_dials ON public.ottoq_run_archives;
CREATE TRIGGER trg_ottoq_capture_run_dials
  AFTER INSERT ON public.ottoq_run_archives
  FOR EACH ROW
  EXECUTE FUNCTION public.ottoq_capture_run_dials();

-- ═════════════ REANALYSIS: reports, never enacts ═════════════
CREATE OR REPLACE VIEW public.ottoq_dial_outcome_reanalysis AS
SELECT d.engine_hash,
       d.scenario,
       d.sim_min_per_tick,
       k.dial,
       k.value,
       count(*)                                         AS runs,
       count(DISTINCT d.random_seed)                    AS seeds,
       round(avg((d.metrics->>'tasks_completed')::numeric), 2)   AS avg_tasks_completed,
       round(avg((d.metrics->>'charge_sessions')::numeric), 2)    AS avg_charge_sessions,
       round(avg((d.metrics->>'commands_refused')::numeric), 2)   AS avg_commands_refused,
       -- SAFETY, never omittable. A cell with 0 evaluations did not pay the shield and its
       -- throughput is not comparable to one that did -- db/checks/0146.
       round(avg(d.rule_evaluations), 1)                AS avg_rule_evaluations,
       round(avg(d.rules_blocked), 1)                   AS avg_rules_blocked,
       (count(DISTINCT d.random_seed) >= 2)             AS has_replication,
       (min(COALESCE(d.rule_evaluations,0)) > 0)        AS every_run_paid_the_shield
  FROM public.ottoq_run_dial_ledger d
  CROSS JOIN LATERAL jsonb_each_text(d.dials) AS k(dial, value)
 WHERE d.metrics IS NOT NULL
 GROUP BY d.engine_hash, d.scenario, d.sim_min_per_tick, k.dial, k.value;

COMMENT ON VIEW public.ottoq_dial_outcome_reanalysis IS
'Dial value -> outcome, grouped so that only like is compared with like: engine_hash AND scenario '
'AND sim_min_per_tick are all in the GROUP BY, because 0300 §3b showed cross-engine comparison is '
'meaningless and 0311 showed the same dials produce different outcomes at different clocks. '
'has_replication is false at one seed -- a row without it cannot separate a dial effect from a draw '
'(G113''s finding about ottoq_ab_runs, in a different table). every_run_paid_the_shield is false '
'when any run in the cell logged zero rule evaluations, and a false there invalidates the throughput '
'columns beside it per db/checks/0146. THIS VIEW PROPOSES NOTHING AND ENACTS NOTHING. It has no '
'reward function, no ranking and no recommendation, because which outcome is "better" is a product '
'decision and because a learner that writes dials would be an AI changing engine state on a path '
'the L1 shield does not gate -- rule 6''s standing finding about the agent. 0403 / G116.';

CREATE OR REPLACE FUNCTION public.ottoq_assert_dial_ledger_readiness()
RETURNS TABLE (runs_captured bigint, runs_with_dials bigint, cells bigint,
               cells_with_replication bigint, cells_that_paid_the_shield bigint)
LANGUAGE sql STABLE AS $fn$
  SELECT (SELECT count(*) FROM public.ottoq_run_dial_ledger),
         (SELECT count(*) FROM public.ottoq_run_dial_ledger WHERE dials_set_count > 0),
         (SELECT count(*) FROM public.ottoq_dial_outcome_reanalysis),
         (SELECT count(*) FROM public.ottoq_dial_outcome_reanalysis WHERE has_replication),
         (SELECT count(*) FROM public.ottoq_dial_outcome_reanalysis WHERE every_run_paid_the_shield)
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_dial_ledger_readiness() IS
'How close the engine is to being able to learn from itself. Expected to read all zeros immediately '
'after 0403 and to fill only as runs are archived FROM NOW ON -- the 1,526 already-archived runs '
'cannot be backfilled, because the dials they used were purged with them. That irreversibility is '
'the finding: every run completed before this migration is permanently unlearnable. 0403 / G116.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0403_the_dials_outlive_their_run_so_reanalysis_becomes_possible_g116',
        FALSE,
        'G116, the prerequisite for any self-improvement. db/checks/0313 measured that the engine '
        'cannot learn from itself because of a missing INPUT rather than a missing algorithm: '
        'ottoq_prime has set dials 1,351 times and all 1,351 are scope_type=run, so '
        'ottoq_purge_prior_runs deletes the choice before anything can correlate it with the '
        'outcome, and 0 of 1,526 archived runs record a dial. The outcome half is already durable '
        '(ottoq_run_archives, 1,526 rows, class=run_ledger, carrying metrics, engine_hash, '
        'config_hash and run_payload.tick_minutes_actual), and comparability is good: 198 cells of '
        'engine_hash x scenario x clock, 130 with n>=2, 52 with n>=5, the largest n=408 over 8 '
        'seeds at one clock and one policy. Adds ottoq_run_dial_ledger (evidence, registered, no FK '
        'to ottoq_sim_runs by 0340 precedent), an error-swallowing AFTER INSERT trigger on the '
        'archive that snapshots the run-scope policy rows in the one window where dials and outcome '
        'coexist, a reanalysis view grouping on engine_hash AND scenario AND sim_min_per_tick so '
        'only like is compared with like, and ottoq_assert_dial_ledger_readiness(). Safety counters '
        'travel in the same row as throughput because 0146 showed the baselines do not pay the L1 '
        'shield and anything scoring throughput alone learns to prefer whichever configuration '
        'checks least; the view exposes every_run_paid_the_shield beside the throughput columns and '
        'has_replication so a one-seed cell cannot be read as a result. NO REWARD FUNCTION, no '
        'ranking, no recommendation and no writer of dials: which outcome is better is a product '
        'decision, and a learner that wrote dials would be an AI changing engine state on the one '
        'path the L1 shield does not gate. DELIBERATELY NOT an edit to ottoq_archive_run, which '
        'runs inside certified pairs and whose run_payload already carries world_fingerprint. '
        'forces_recert FALSE on the same measurable ground as 0402: a table, a trigger writing only '
        'that table, and a view -- no atom reads any of them. AND THE IRREVERSIBILITY IS THE '
        'FINDING: the 1,526 runs already archived cannot be backfilled, because the dials they used '
        'were purged with them, so every run completed before this migration is permanently '
        'unlearnable and the ledger starts empty by necessity.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
