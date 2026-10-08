-- migration-version: PENDING
-- migration-name:    the_kernel_learns_each_cars_charge_clock_from_its_own_charges
--
-- 0622  **The kernel learns each car's charge clock from its own charges, and looks for the variable its clock misses.**
--       0621's grader read the check against what happened for the first time on run d9d49732, and within the hour its
--       self-assessment named the learned charge clock (0619 charge_time_v1) as miscalibrated on fast chargers: charges
--       ran 34% short of it, with a z spread of 2.05 and 67% inside an 80% band, and "a spread that stays wide means the
--       band model misses a variable". It could not say which. Measured by hand the same morning, the variable is the car,
--       at every scale: its class, its make and model, the car itself, the day it is having, and the charge it is in.
--       0622 learns all of them from the depot's own charges, as a hierarchy that shrinks each level toward the one above
--       it by how much evidence it has, and gives the self-assessment the instrument it lacked: an audit of the clock's
--       residuals against every recorded covariate, so that next time the system names the missing variable itself.
--       Chase, 2026-10-08: "identify well, it can't technically do XYZ, so I should probably build that in ... Ideally,
--       after a while, the system itself will pick up areas for self improvement." Rule 10 holds: OTTO-Q refits an
--       estimate nightly from real charges (an estimate, never a rule or a setting); every finding is for a person.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The clock is wrong for the cars the depot actually has. On run d9d49732 the 29 completed fast charges (all to
--       100%) took 37.3 minutes on average against 61.5 forecast (mean log ratio -0.47); its 48 L2 charges were right (mean
--       log ratio 0.003). 0619 fits one factor per kind and band of starting battery across every car, and the fleet is
--       three classes and seven makes and models that charge very differently on the same fast charger. Since 2026-09-30,
--       against 0614's base estimate (median, fine ticks): Zoox Robotaxi 0.51x (165 charges), Waymo I-Pace 1.61x (182),
--       Tesla Model Y 2.42x (167), with a log spread of 0.13-0.31 inside a class against about 0.6 pooled. Recency-
--       weighted over 21 days, relative to the pooled band: Zoox x0.31, Waymo x1.03, Tesla x1.44 on fast chargers, and
--       inside the classes Cybercab x0.54 of the Model Y, Zeekr x0.52 of the I-Pace, Zoox VH6 x1.35 of the Robotaxi. On L2
--       every class is within 1% of the pooled band: the 19.2 kW charger is the limit for every car, as it should be.
--   (b) The clock lags. 0619 weights 21 days equally, and 588 of its fast charges are from 2026-09-28/29, when the daily
--       median ratio to the base estimate was 2.0-2.1; it has been 1.32-1.55 every day since, and 1.39 today. CLAUDE.md's
--       standing test (group by day and read the last row) fails on the clock's own evidence.
--   (c) The car and the day carry information the clock throws away. After class, model and band, fast-charge residuals
--       still correlate across runs for the same car (run means, rho 0.50) and between consecutive fast charges of the
--       same car in the same run (rho 0.96: the twin draws each car's charge-curve condition at the run's boot, as a real
--       car carries its battery's condition from charge to charge); and run means vary with a spread of 0.19 beyond what
--       sampling explains (the day's weather and draw). And a charge in progress predicts its own end: on fast chargers
--       the first half's ratio to the base estimate predicts the second half's with rho 0.90 (135 charges on three runs);
--       on L2, -0.10.
--   (d) It is what made the check wrong. 0621's Shapley attribution over d9d49732's 15 decisions put 39% of the verdict
--       mass on these two parts (charge times 15%, charges under way 24%).
--
-- ══ §2 WHAT ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_charge_time_v2_params(depot, through, window, half_life)` (read-only) and `ottoq_fit_charge_time_v2(...)`,
--       which writes one row of the new append-only evidence table `public.ottoq_charge_clock_fits` (model
--       `charge_time_v2`; depot-scoped, no run column, like 0619's `ottoq_learned_estimates`, which is left exactly as it
--       is: its per-car cells make a v2 fit a different shape). From the depot's completed charges (fine ticks when a kind
--       has 100), every charge weighted
--       by 0.5^(age / half-life), 3 days by default, the log ratio of each charge's minutes to 0614's base estimate is
--       explained in levels, each a robust weighted median of what the levels above left, shrunk toward zero by an
--       empirical-Bayes prior strength estimated from the levels' own spread (method of moments, floor 2):
--         pooled   per kind and band (0619's cells, recency-weighted; the same keys, so a v1 reader still reads them),
--         class    per kind and class (vehicles.vehicle_class_code), with the class's own residual spread,
--         model    per kind and make/model within the class,
--         band     per kind, class and band (each class tapers differently),
--         run      a run's charges so far, shrunk by n/(n + k_run), k_run from the spread of run means,
--         car      per kind and car across runs, shrunk by Spearman-Brown on the measured across-run correlation,
--         in run   the car's own charges in this run so far, shrunk by the measured within-run correlation,
--         session  for a charge under way, its own progress: the residual of the remaining part regressed on the residual
--                  of the part done (weighted least squares per kind at a quarter, half and three quarters of the charge,
--                  from the run's MeterValues), applied once a sixth of the charge is done.
--       Every correlation and prior strength is estimated from the data each night and kept with the fit, with the spread
--       ladder (how much each level explained) in its diagnostics.
--   (b) `ottoq_charge_clock(model, kind, who, battery, from, to, charger_kw, inlet_kw, run)`: the one function every
--       reader times a charge with: {m minutes, sd log spread, f log factor, lvl the levels used}. On a 0619 model it is
--       0619's minutes and 0620's spread exactly (V1). `ottoq_charge_clock_who(vehicle, class, make, model)` builds its
--       keys; `ottoq_charge_clock_model(depot)` picks the latest usable v2, else v1;
--       `ottoq_charge_clock_run_evidence(model, run, as_of)` reads the run's completed charges up to a sim time and turns
--       them into the run and in-run offsets; `ottoq_charge_clock_remaining(...)` times what is left of a charge under way.
--   (c) The readers move to it: `ottoq_charge_line_state` (the check's line, the cars coming home and the chargers in use;
--       each car now carries its class `cls` and the levels its clock used `lv`), `ottoq_charge_order_realized` (the
--       check's clock for the cars it saw coming and those it did not, as of the order), and
--       `ottoq_agent_charge_queue_board` (each car's minutes on each kind, the chargers freeing soonest, and in `check` the
--       clock's identity and each class against the depot's typical charge). The simulator, rollout, verdict, door and
--       grade are unchanged.
--   (d) `ottoq_charge_clock_calibration(depot, since)`: the check's charge forecasts against what came, one row per charge
--       (the check's last forecast before the charge began), counting only charges that would have finished inside the
--       window at the forecast's 90th percentile, so the window's survivorship no longer biases them short (0621's
--       forecast sums keep every completed charge, and a long charge that starts late is never completed in the window);
--       by kind, by class and by the levels the clock used.
--   (e) `ottoq_charge_clock_audit(depot, since, model)`: the latest clock and 0619's on the depot's charges since,
--       out of sample when the fit is older than them, and the share of what the clock leaves unexplained that each
--       recorded covariate explains (adjusted eta squared: class, model, car, band, run, charger, ambient temperature, sim
--       hour, a full charge or not). A covariate the clock does not model that explains 5% or more is named.
--   (f) `ottoq_arbiter_self_assessment_v2(depot, since)`: 0621's assessment with the charge clock's calibration taken
--       from (d) in place of the window-biased sums, the audit (e) and its findings, and the depot's outflow: the cars that
--       leave after an order and come back inside its window, which the simulator does not model (on d9d49732 every one
--       of the 532 cars that appeared that way had left after the order: 467 at the battery reserve). The nightly
--       assessment writes it; `ottoq-learn-charge-clock-nightly` refits the clock at 11:22 UTC (6:22 AM CT).
--
--   The tick path is untouched: the clock is read by the check, the agent's board and the grader, which run only on runs
--   that take an agent's charge order (0615). Nothing here writes a dial, a rule or the bar.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the state, realized reader, board, assessment, nightly assess, learned minutes, learned
--   spread, base estimate, band and latest-fit reader are the bodies this file was written against (md5); nothing this
--   file creates exists. Nothing here drops or deletes anything: the fit reads its evidence into an array, not a table.
--   V1: on the depot's v1 fit, the clock returns 0619's minutes and 0620's spread on a grid of 4,320 cases.
--   V2: THE GATE. A v2 fit through the moment run d9d49732 started, scored on that run's completed charges against the v1
--   fit the run actually used, with the run and in-run levels as of each charge's start: on fast chargers v2's mean
--   absolute log error must be lower than v1's and its 80% band must hold at least 60% of the charges, or nothing here is
--   applied. V3: on the same run's charges, the remaining-time forecast at the half-way point with the session level is no
--   worse than without it on fast chargers. Dry run on the live database, 2026-10-08 15:57 UTC (rolled back): the fit
--   through the run's start read 3,095 charges of 34 runs; on the run's 31 fast charges 0619's clock had a bias of -0.476,
--   a mean absolute log error of 0.605 and 61% inside its band, and this one -0.030, 0.131 and 74%; on its 50 L2 charges
--   0.094 and 86% against 0.078 and 94%. At half way, what was left of a fast charge: 0.136 either way; of an L2 charge
--   0.185 without the session level and 0.144 with it. The fit took 4.2 s with the ledger cached (28 s cold). V4: the first fit at apply is usable; the state and board on a running twin run
--   time their cars with it. V5: the stored realized records of five of d9d49732's graded orders (v1 snapshots) are what
--   this file's realized reader returns.
--   tests/test_agent_arbiter_sql.py executes the rest on the miniature depot.
--
-- ══ §4 RECERT ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   FALSE/FALSE. The clock is read by the agent's charge-order check, board and grader only, on operator_demo runs
--   (0615); no certification, sweep or dial pair arms an order. On a v1 model every reader returns what it returned (V1,
--   V5); the new estimate rows are evidence.
--
-- ROLLBACK: SELECT cron.unschedule('ottoq-learn-charge-clock-nightly'); EXECUTE each `definition` in ottoq_schema_snapshots
--   WHERE label = '0622_pre' (the state, realized reader, board and nightly assess as 0621 left them); the readers then
--   use v1 again whatever v2 rows exist. DROP FUNCTION public.ottoq_arbiter_self_assessment_v2(uuid, timestamptz),
--   public.ottoq_charge_clock_audit(uuid, timestamptz, jsonb), public.ottoq_charge_clock_calibration(uuid, timestamptz),
--   public.ottoq_fit_charge_time_v2(uuid, timestamptz, interval, numeric, text),
--   public.ottoq_charge_time_v2_params(uuid, timestamptz, interval, numeric),
--   public.ottoq_charge_clock_remaining(jsonb, text, jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric, jsonb),
--   public.ottoq_charge_clock_run_evidence(jsonb, uuid, timestamptz),
--   public.ottoq_charge_clock(jsonb, text, jsonb, numeric, numeric, numeric, numeric, numeric, jsonb),
--   public.ottoq_charge_clock_model(uuid), public.ottoq_charge_clock_who(uuid, text, text, text); the table
--   ottoq_charge_clock_fits and the type ottoq_charge_clock_evidence may stay (nothing else reads them);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0622_the_kernel_learns_each_cars_charge_clock_from_its_own_charges'.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0622 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 'b2e9ddaa', 'the state (0620)'),
      ('public.ottoq_charge_order_realized(bigint,numeric)', '0788bc95', 'the realized reader (0621)'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 'a4983f6a', 'the board (0621)'),
      ('public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)', '97d1401b', 'the assessment (0621)'),
      ('public.ottoq_arbiter_assess(uuid,integer)', 'f91156d3', 'the nightly assess (0621)'),
      ('public.ottoq_charge_minutes_learned_with(jsonb,text,numeric,numeric,numeric,numeric,numeric)', '97486660', 'the learned minutes (0619)'),
      ('public.ottoq_charge_time_log_sd(jsonb,text,numeric)', '8f4b869e', 'the learned spread (0620)'),
      ('public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)', '21f22ff8', 'the base estimate (0614)'),
      ('public.ottoq_charge_time_band(numeric)', '9212138a', 'the band (0619)'),
      ('public.ottoq_learned_estimate(uuid,text)', 'ff910870', 'the latest fit (0619)'))
    AS x(sig, md5, what)
  LOOP
    IF left((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)), 8) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0622 P1: % is not the body this file was written against (md5 %); read it again', r.what, r.md5;
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_clock_who(uuid,text,text,text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_clock_model(uuid)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)') IS NOT NULL
     OR to_regprocedure('public.ottoq_arbiter_self_assessment_v2(uuid,timestamp with time zone)') IS NOT NULL
     OR to_regclass('public.ottoq_charge_clock_fits') IS NOT NULL
     OR to_regtype('public.ottoq_charge_clock_evidence') IS NOT NULL
     OR EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-learn-charge-clock-nightly') THEN
    RAISE EXCEPTION '0622 P1: something this file creates already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0622_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_order_realized(bigint,numeric)'::regprocedure,
                 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_arbiter_assess(uuid,integer)'::regprocedure);

-- ══ the model family ═════════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_charge_clock_fits (
  fit_id           bigserial PRIMARY KEY,
  depot_id         uuid NOT NULL,
  model            text NOT NULL CHECK (model = 'charge_time_v2'),
  fitted_at        timestamptz NOT NULL DEFAULT now(),
  --: the real-clock window of evidence read (the ledger's recorded_at), not a sim clock
  evidence_from    timestamptz,
  evidence_through timestamptz,
  n_evidence       integer NOT NULL,
  n_runs           integer NOT NULL,
  --: both kinds have a usable pooled cell
  usable           boolean NOT NULL,
  --: ottoq_charge_time_v2_params: the pooled cells (0619's keys), class_cells, model_cells, vehicle_cells, icc, run,
  --: session, and the spread ladder in diagnostics
  params           jsonb NOT NULL,
  code_md5         text NOT NULL,
  fitted_by        text NOT NULL DEFAULT current_user,
  note             text
);

COMMENT ON TABLE public.ottoq_charge_clock_fits IS
'0622. One row per fit of a depot''s charge clock, charge_time_v2: from its completed charges, recency-weighted, the log ratio of each charge''s minutes to ottoq_charge_minutes_estimate explained in levels (pooled band, class, make and model, class and band, car across runs), each shrunk by its evidence, with the run and in-run correlations and the in-session regression. Written by ottoq_fit_charge_time_v2 (at apply and nightly at 11:22 UTC), read through ottoq_charge_clock_model and timed by ottoq_charge_clock. An estimate, never a rule or a setting (CLAUDE.md rule 10). Append-only (override: ottoq.learned_estimates_unlock=on). No run column: it belongs to the depot and outlives every purge. 0619''s ottoq_learned_estimates keeps charge_time_v1 and return_v1.';

CREATE INDEX ottoq_charge_clock_fits_latest_idx ON public.ottoq_charge_clock_fits (depot_id, fit_id DESC);

CREATE FUNCTION public.ottoq_charge_clock_fits_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.learned_estimates_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_charge_clock_fits is append-only: % refused. A new fit is a new row. Set ottoq.learned_estimates_unlock=on in '
    'the session to override, and say why in a migration.', TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_charge_clock_fits_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_charge_clock_fits
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_clock_fits_append_only();

ALTER TABLE public.ottoq_charge_clock_fits ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_charge_clock_fits_read ON public.ottoq_charge_clock_fits FOR SELECT USING (true);
REVOKE ALL ON public.ottoq_charge_clock_fits FROM anon, authenticated;
GRANT SELECT ON public.ottoq_charge_clock_fits TO anon, authenticated;

-- one completed charge as the fit reads it: the fit holds its evidence in an array of these, never a table
CREATE TYPE public.ottoq_charge_clock_evidence AS (
  sid uuid, run uuid, kind text, band text, who jsonb, cls text, mdl text, veh text, lr float8, w float8,
  st timestamptz, en timestamptz, bat numeric, s0 numeric, s1 numeric, ckw numeric, vkw numeric);

-- ══ (b) the clock ════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_clock_who(p_vehicle_id uuid, p_class text, p_make text, p_model text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0622: the keys a car's charge clock is learned under: its class, its make and model within the class, and the car.
  -- The fit and every reader build them here, so they cannot disagree.
  SELECT jsonb_build_object(
    'cls', COALESCE(NULLIF(btrim(p_class), ''), '?'),
    'mdl', COALESCE(NULLIF(btrim(p_class), ''), '?') || '/'
           || btrim(COALESCE(NULLIF(btrim(p_make), ''), '?') || ' ' || COALESCE(NULLIF(btrim(p_model), ''), '?')),
    'veh', p_vehicle_id::text)
$fn$;

CREATE FUNCTION public.ottoq_charge_clock_model(p_depot uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0622: the clock a depot's charges are timed by: its latest usable charge_time_v2 fit (ottoq_charge_clock_fits), else
  -- its latest charge_time_v1 (ottoq_learned_estimates), in the shape ottoq_learned_estimate returns.
  SELECT COALESCE(
    (SELECT jsonb_build_object('estimate_id', f.fit_id, 'model', f.model, 'fitted_at', f.fitted_at, 'usable', f.usable,
                               'n_evidence', f.n_evidence, 'n_runs', f.n_runs, 'params', f.params)
       FROM public.ottoq_charge_clock_fits f
      WHERE f.depot_id = p_depot AND f.usable
      ORDER BY f.fit_id DESC LIMIT 1),
    public.ottoq_learned_estimate(p_depot, 'charge_time_v1'))
$fn$;

CREATE FUNCTION public.ottoq_charge_clock(p_model jsonb, p_kind text, p_who jsonb, p_batt_kwh numeric, p_soc_from numeric,
                                          p_soc_to numeric, p_charger_kw numeric, p_inlet_kw numeric,
                                          p_run jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0622: how long a charge from p_soc_from to p_soc_to on a charger of p_kind takes, for the car p_who
   (ottoq_charge_clock_who), on p_model (a learned estimate as ottoq_learned_estimate returns it):
   {m: minutes, sd: the log spread of a charge like it, f: the log factor on 0614's base estimate, lvl: the levels used}.
   On a 0619 model (no class_cells): 0619's minutes and 0620's spread, exactly. On a 0622 model: the pooled cell, then the
   offsets of the car's class, class and band, make and model, and the car itself, each as the fit shrank it; with p_run
   (one kind's block of ottoq_charge_clock_run_evidence) the run's offset and the car's own in this run. The spread is the
   class's, narrowed by the share of it the car-level evidence explains. m is NULL when the battery size is unknown and 0
   when nothing is owed. */
DECLARE
  v_p      jsonb := p_model -> 'params';
  v_band   text := public.ottoq_charge_time_band(p_soc_from);
  v_base   numeric := public.ottoq_charge_minutes_estimate(p_batt_kwh, p_soc_from, p_soc_to, p_charger_kw, p_inlet_kw);
  v_cls    text := COALESCE(p_who ->> 'cls', '?');
  v_mdl    text := p_who ->> 'mdl';
  v_veh    text := p_who ->> 'veh';
  v_c      jsonb;
  v_x      jsonb;
  v_factor numeric;
  v_f      numeric := 0;
  v_sd     numeric := 0;
  v_lvl    text := 'none';
  v_expl   numeric := 0;
BEGIN
  -- the pooled cell: the band the charge starts in, else the kind's (0619's lookup)
  IF (v_p #>> ARRAY['cells', p_kind || ':' || v_band, 'usable']) = 'true' THEN
    v_c := v_p #> ARRAY['cells', p_kind || ':' || v_band]; v_lvl := 'band';
  ELSIF (v_p #>> ARRAY['cells', p_kind || ':*', 'usable']) = 'true' THEN
    v_c := v_p #> ARRAY['cells', p_kind || ':*']; v_lvl := 'kind';
  END IF;
  IF v_c IS NOT NULL THEN
    v_factor := (v_c ->> 'factor')::numeric;
    v_sd := COALESCE((v_c ->> 'log_sd')::numeric, 0);
  END IF;
  -- a 0619 model: 0619's minutes and 0620's spread
  IF v_p -> 'class_cells' IS NULL THEN
    RETURN jsonb_build_object(
      'm', CASE WHEN v_base IS NULL THEN NULL WHEN v_base = 0 THEN 0 ELSE round(v_base * COALESCE(v_factor, 1.0), 1) END,
      'sd', v_sd, 'f', round(ln(COALESCE(v_factor, 1.0)), 4), 'lvl', v_lvl);
  END IF;
  v_f := ln(COALESCE(v_factor, 1.0));
  v_x := v_p #> ARRAY['class_cells', p_kind || '|' || v_cls];
  IF v_x IS NOT NULL THEN
    v_f := v_f + COALESCE((v_x ->> 'off')::numeric, 0);
    v_sd := COALESCE((v_x ->> 'sd')::numeric, v_sd);
    v_lvl := 'class';
    v_x := v_p #> ARRAY['class_cells', p_kind || '|' || v_cls || '|' || v_band];
    IF v_x IS NOT NULL THEN
      v_f := v_f + COALESCE((v_x ->> 'off')::numeric, 0); v_lvl := 'class_band';
    END IF;
  END IF;
  v_x := v_p #> ARRAY['model_cells', p_kind || '|' || COALESCE(v_mdl, '')];
  IF v_x IS NOT NULL THEN
    v_f := v_f + COALESCE((v_x ->> 'off')::numeric, 0); v_lvl := v_lvl || '+model';
  END IF;
  v_x := v_p #> ARRAY['vehicle_cells', p_kind || '|' || COALESCE(v_veh, '')];
  IF v_x IS NOT NULL THEN
    v_f := v_f + COALESCE((v_x ->> 'off')::numeric, 0);
    v_expl := COALESCE((v_p #>> ARRAY['icc', p_kind, 'vehicle_single'])::numeric, 0) * COALESCE((v_x ->> 's')::numeric, 0);
    v_lvl := v_lvl || '+vehicle';
  END IF;
  IF p_run IS NOT NULL THEN
    IF COALESCE((p_run ->> 'n')::int, 0) > 0 THEN
      v_f := v_f + COALESCE((p_run ->> 'off')::numeric, 0); v_lvl := v_lvl || '+run';
    END IF;
    v_x := p_run #> ARRAY['veh', COALESCE(v_veh, '')];
    IF v_x IS NOT NULL AND COALESCE((v_x ->> 'n')::int, 0) > 0 THEN
      v_f := v_f + COALESCE((v_x ->> 'off')::numeric, 0);
      v_expl := GREATEST(v_expl, COALESCE((v_p #>> ARRAY['icc', p_kind, 'in_run'])::numeric, 0) * COALESCE((v_x ->> 's')::numeric, 0));
      v_lvl := v_lvl || '+vehicle_in_run';
    END IF;
  END IF;
  v_sd := v_sd * sqrt(1 - LEAST(GREATEST(v_expl, 0), 0.95));
  RETURN jsonb_build_object(
    'm', CASE WHEN v_base IS NULL THEN NULL WHEN v_base = 0 THEN 0 ELSE round(v_base * exp(v_f), 1) END,
    'sd', round(v_sd, 4), 'f', round(v_f, 4), 'lvl', v_lvl);
END $fn$;

CREATE FUNCTION public.ottoq_charge_clock_remaining(p_model jsonb, p_kind text, p_who jsonb, p_batt_kwh numeric,
                                                    p_soc_start numeric, p_soc_now numeric, p_soc_to numeric,
                                                    p_charger_kw numeric, p_inlet_kw numeric, p_elapsed_min numeric,
                                                    p_run jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0622: what is left of a charge under way: the clock from the battery it is at now to its target, and, once enough of
   it is done, corrected by how the part done ran (the model's session regression for the kind: the remaining part's
   residual on the done part's, fitted on completed charges at a quarter, half and three quarters). On a model without a
   session block, or with too little of the charge done, the clock from now, unchanged. */
DECLARE
  v_r    jsonb := public.ottoq_charge_clock(p_model, p_kind, p_who, p_batt_kwh, p_soc_now, p_soc_to, p_charger_kw,
                                            p_inlet_kw, p_run);
  v_s    jsonb := p_model #> ARRAY['params', 'session', p_kind];
  v_d    jsonb;
  v_done numeric;
  v_rem  numeric;
  v_frac numeric;
  v_x    numeric;
  v_f    numeric;
BEGIN
  IF v_s IS NULL OR (v_r ->> 'm') IS NULL OR (v_r ->> 'm')::numeric <= 0 OR p_elapsed_min IS NULL OR p_soc_start IS NULL
     OR p_soc_now IS NULL OR p_soc_now <= p_soc_start THEN
    RETURN v_r || jsonb_build_object('session', false);
  END IF;
  v_done := public.ottoq_charge_minutes_estimate(p_batt_kwh, p_soc_start, p_soc_now, p_charger_kw, p_inlet_kw);
  IF COALESCE(v_done, 0) < 3 OR p_elapsed_min < 2 THEN
    RETURN v_r || jsonb_build_object('session', false);
  END IF;
  v_d := public.ottoq_charge_clock(p_model, p_kind, p_who, p_batt_kwh, p_soc_start, p_soc_now, p_charger_kw, p_inlet_kw,
                                   p_run);
  v_frac := (v_d ->> 'm')::numeric / NULLIF((v_d ->> 'm')::numeric + (v_r ->> 'm')::numeric, 0);
  IF v_frac IS NULL OR v_frac < COALESCE((v_s ->> 'min_frac')::numeric, 0.15) THEN
    RETURN v_r || jsonb_build_object('session', false, 'frac', round(v_frac, 3));
  END IF;
  v_x := ln(p_elapsed_min / v_done) - (v_d ->> 'f')::numeric;
  v_f := (v_r ->> 'f')::numeric + COALESCE((v_s ->> 'a')::numeric, 0) + COALESCE((v_s ->> 'b')::numeric, 0) * v_x;
  v_rem := public.ottoq_charge_minutes_estimate(p_batt_kwh, p_soc_now, p_soc_to, p_charger_kw, p_inlet_kw);
  RETURN jsonb_build_object(
    'm', round(v_rem * exp(v_f), 1), 'sd', COALESCE((v_s ->> 's')::numeric, (v_r ->> 'sd')::numeric),
    'f', round(v_f, 4), 'lvl', (v_r ->> 'lvl') || '+session', 'session', true, 'frac', round(v_frac, 3),
    'done_res', round(v_x, 4));
END $fn$;

CREATE FUNCTION public.ottoq_charge_clock_run_evidence(p_model jsonb, p_sim_run_id uuid, p_asof timestamptz)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0622: what a run's own completed charges, up to sim time p_asof, say about its clock, per kind: {n, off, s, veh: {car:
  -- {n, off, s}}}. Each charge's residual is its log ratio less the cross-run clock (no run evidence); the run's offset is
  -- their mean shrunk by n / (n + k_run); a car's offset is the mean of its own residuals less the run's, shrunk by
  -- Spearman-Brown on the model's measured in-run correlation. NULL on a model without the levels (0619).
  WITH ok AS (
    SELECT (p_model #> '{params,class_cells}') IS NOT NULL AND p_sim_run_id IS NOT NULL AND p_asof IS NOT NULL AS go
  ), c AS (
    SELECT l.charger_type AS kind, l.vehicle_id::text AS veh,
           ln((l.duration_min / est.m)::numeric)
             - (public.ottoq_charge_clock(p_model, l.charger_type,
                                          public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model),
                                          l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw, NULL) ->> 'f')::numeric AS res
      FROM ok
      JOIN public.ottoq_charge_duration_ledger l ON ok.go
      JOIN public.vehicles v ON v.id = l.vehicle_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                      l.vehicle_kw) AS m) est
     WHERE l.sim_run_id = p_sim_run_id AND l.stopped_reason = 'completed' AND l.ended_at <= p_asof
       AND l.charger_type IN ('dcfc', 'l2') AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0
  ), k AS (
    SELECT c.kind, count(*) AS n, avg(c.res) AS mres,
           GREATEST(COALESCE((p_model #>> ARRAY['params', 'run', c.kind, 'k'])::numeric, 1000), 0.5) AS kr,
           LEAST(GREATEST(COALESCE((p_model #>> ARRAY['params', 'icc', c.kind, 'in_run'])::numeric, 0), 0), 0.95) AS rho
      FROM c GROUP BY c.kind
  ), ko AS (
    SELECT k.kind, k.n, k.rho, k.n / (k.n + k.kr) AS s, k.n / (k.n + k.kr) * k.mres AS off FROM k
  ), vv AS (
    SELECT c.kind, c.veh, count(*) AS n, avg(c.res - ko.off) AS mres, max(ko.rho) AS rho
      FROM c JOIN ko USING (kind) GROUP BY c.kind, c.veh
  )
  SELECT CASE WHEN (SELECT go FROM ok) THEN COALESCE((
    SELECT jsonb_object_agg(ko.kind, jsonb_build_object(
             'n', ko.n, 's', round(ko.s, 4), 'off', round(ko.off, 4),
             'veh', COALESCE((SELECT jsonb_object_agg(vv.veh, jsonb_build_object(
                                       'n', vv.n,
                                       's', round(vv.n * vv.rho / (1 + (vv.n - 1) * vv.rho), 4),
                                       'off', round(vv.n * vv.rho / (1 + (vv.n - 1) * vv.rho) * vv.mres, 4)))
                                FROM vv WHERE vv.kind = ko.kind AND vv.rho > 0), '{}'::jsonb)))
      FROM ko), '{}'::jsonb) END
$fn$;

-- ══ (a) the fit ══════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_time_v2_params(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                                   p_window interval DEFAULT interval '21 days',
                                                   p_half_life_days numeric DEFAULT 3)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0622: the params of a charge_time_v2 fit for a depot from its completed charges recorded in (through - window,
   through], without writing anything: the evidence is held in an array of ottoq_charge_clock_evidence and each stage's
   residuals in an array beside it. Every charge weighs 0.5^(age in days / half-life). Each level is a robust weighted
   median of what the levels above left (the residual is computed by ottoq_charge_clock itself, so the fit and every
   reader agree by construction), shrunk toward zero by k = within-level variance over between-group variance (method of
   moments, floor 2). Then the run's prior strength, the across-run and in-run correlations of a car's residuals, and the
   in-session regression from the MeterValues of completed charges. Deterministic for a given ledger and through. */
DECLARE
  c_min_fine  constant int := 100;
  c_min_cell  constant int := 30;
  c_min_neff  constant numeric := 10;
  c_k_floor   constant float8 := 2;
  c_min_pairs constant int := 20;
  v_through   timestamptz := COALESCE(p_through, now());
  v_from      timestamptz := COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days');
  v_h         float8 := GREATEST(COALESCE(p_half_life_days, 3), 0.25)::float8;
  v_e         public.ottoq_charge_clock_evidence[];
  v_r         float8[];   -- each charge's residual once the class levels are out, aligned with v_e
  v_r2        float8[];   -- ... and its run's offset
  v_r3        float8[];   -- ... and its car's offset across runs
  v_pop       jsonb;
  v_p         jsonb;
  v_m         jsonb;
  v_lvl       jsonb;
  v_rms       jsonb;
  v_level     text;
  v_ladder    jsonb := '{}'::jsonb;
  v_icc       jsonb := '{}'::jsonb;
  v_run       jsonb := '{}'::jsonb;
  v_veh       jsonb;
  v_sess      jsonb := '{}'::jsonb;
  v_within    jsonb;
  v_n         int;
  v_runs      int;
BEGIN
  IF p_depot IS NULL THEN RAISE EXCEPTION 'ottoq_charge_time_v2_params: a depot is required'; END IF;

  -- the evidence and its population: a kind with c_min_fine charges at ticks of a minute or less fits on those alone (a
  -- 5-minute tick rounds every charge up to the next tick, 0619)
  WITH b AS (
    SELECT l.session_id, l.sim_run_id, l.charger_type AS kind, w.j AS who,
           (l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1) AS fine,
           ln((l.duration_min / est.m)::float8) AS lr,
           power(0.5::float8, GREATEST(extract(epoch FROM (v_through - l.recorded_at))::float8, 0) / 86400.0 / v_h) AS w,
           l.started_at, l.ended_at, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw
      FROM ottoq_charge_duration_ledger l
      JOIN vehicles v ON v.id = l.vehicle_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                      l.vehicle_kw) AS m) est
     WHERE l.depot_id = p_depot AND l.recorded_at > v_from AND l.recorded_at <= v_through
       AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2')
       AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0
  ), pop AS (
    SELECT b.kind, CASE WHEN count(*) FILTER (WHERE b.fine) >= c_min_fine THEN 'fine_ticks' ELSE 'all_ticks' END AS p
      FROM b GROUP BY b.kind
  )
  SELECT (SELECT COALESCE(jsonb_object_agg(pop.kind, pop.p), '{}'::jsonb) FROM pop),
         (SELECT array_agg(ROW(b.session_id::uuid, b.sim_run_id::uuid, b.kind::text,
                               public.ottoq_charge_time_band(b.soc_start)::text, b.who, (b.who ->> 'cls')::text,
                               (b.who ->> 'mdl')::text, (b.who ->> 'veh')::text, b.lr, b.w, b.started_at::timestamptz,
                               b.ended_at::timestamptz, b.battery_kwh::numeric, b.soc_start::numeric, b.soc_end::numeric,
                               b.charger_kw::numeric, b.vehicle_kw::numeric)::public.ottoq_charge_clock_evidence
                           ORDER BY b.session_id)
            FROM b JOIN pop USING (kind)
           WHERE b.fine OR pop.p = 'all_ticks')
    INTO v_pop, v_e;
  v_e := COALESCE(v_e, '{}'::public.ottoq_charge_clock_evidence[]);
  SELECT count(*), count(DISTINCT x.run) INTO v_n, v_runs FROM unnest(v_e) x;

  -- ── the pooled cells: per kind and band, and per kind: the weighted median, the weighted MAD, n, n_eff ──
  WITH src AS (
    SELECT x.kind, x.band AS cell, x.lr, x.w, x.sid, x.run FROM unnest(v_e) x
    UNION ALL
    SELECT x.kind, '*', x.lr, x.w, x.sid, x.run FROM unnest(v_e) x
  ), o AS (
    SELECT src.*, sum(src.w) OVER (PARTITION BY src.kind, src.cell ORDER BY src.lr, src.sid) AS cw,
           sum(src.w) OVER (PARTITION BY src.kind, src.cell) AS tw
      FROM src
  ), med AS (
    SELECT o.kind, o.cell, min(o.lr) FILTER (WHERE o.cw >= o.tw / 2) AS mu, count(*) AS n, count(DISTINCT o.run) AS runs,
           sum(o.w) AS sw, sum(o.w * o.w) AS sw2
      FROM o GROUP BY o.kind, o.cell
  ), od AS (
    SELECT src.kind, src.cell, abs(src.lr - med.mu) AS dv,
           sum(src.w) OVER (PARTITION BY src.kind, src.cell ORDER BY abs(src.lr - med.mu), src.sid) AS cw,
           sum(src.w) OVER (PARTITION BY src.kind, src.cell) AS tw
      FROM src JOIN med ON med.kind = src.kind AND med.cell = src.cell
  ), mad AS (
    SELECT od.kind, od.cell, min(od.dv) FILTER (WHERE od.cw >= od.tw / 2) AS mad FROM od GROUP BY od.kind, od.cell
  )
  SELECT COALESCE(jsonb_object_agg(med.kind || ':' || med.cell, jsonb_build_object(
           'factor', round(exp(med.mu)::numeric, 4), 'log_sd', round((1.4826 * mad.mad)::numeric, 4),
           'n', med.n, 'n_eff', round((med.sw * med.sw / NULLIF(med.sw2, 0))::numeric, 1), 'runs', med.runs,
           'usable', med.n >= c_min_cell AND med.sw * med.sw / NULLIF(med.sw2, 0) >= c_min_neff)), '{}'::jsonb)
    INTO v_lvl
    FROM med JOIN mad USING (kind, cell);

  v_p := jsonb_build_object('cells', v_lvl, 'class_cells', '{}'::jsonb, 'model_cells', '{}'::jsonb,
                            'vehicle_cells', '{}'::jsonb);
  v_m := jsonb_build_object('params', v_p);

  -- ── class, model, class and band: each a shrunk robust offset on what the levels above left ──
  FOREACH v_level IN ARRAY ARRAY['class', 'model', 'class_band'] LOOP
    WITH e AS (
      SELECT x.kind, x.sid, x.w,
             CASE v_level WHEN 'class' THEN x.cls WHEN 'model' THEN x.mdl ELSE x.cls || '|' || x.band END AS grp,
             x.lr - (public.ottoq_charge_clock(v_m, x.kind, x.who, x.bat, x.s0, x.s1, x.ckw, x.vkw, NULL) ->> 'f')::float8 AS r
        FROM unnest(v_e) x
    ), o AS (
      SELECT e.*, sum(e.w) OVER (PARTITION BY e.kind, e.grp ORDER BY e.r, e.sid) AS cw,
             sum(e.w) OVER (PARTITION BY e.kind, e.grp) AS tw
        FROM e
    ), g AS (
      SELECT o.kind, o.grp, min(o.r) FILTER (WHERE o.cw >= o.tw / 2) AS d, count(*) AS n,
             sum(o.w) * sum(o.w) / NULLIF(sum(o.w * o.w), 0) AS neff
        FROM o GROUP BY o.kind, o.grp
    ), sw AS (   -- the within-group variance of the residual, per kind
      SELECT e.kind, sum(e.w * (e.r - g.d) ^ 2) / NULLIF(sum(e.w), 0) AS s2
        FROM e JOIN g ON g.kind = e.kind AND g.grp = e.grp GROUP BY e.kind
    ), tb AS (   -- the between-group variance beyond what sampling explains (method of moments)
      SELECT g.kind,
             GREATEST(sum(g.neff * (g.d - x.dbar) ^ 2) / NULLIF(sum(g.neff), 0) - avg(sw.s2 / NULLIF(g.neff, 0)), 1e-4) AS t2
        FROM g JOIN sw USING (kind)
        JOIN (SELECT g2.kind, sum(g2.neff * g2.d) / NULLIF(sum(g2.neff), 0) AS dbar FROM g g2 GROUP BY g2.kind) x USING (kind)
       GROUP BY g.kind
    ), kk AS (
      SELECT sw.kind, GREATEST(sw.s2 / tb.t2, c_k_floor) AS k FROM sw JOIN tb USING (kind)
    )
    SELECT (SELECT COALESCE(jsonb_object_agg(g.kind || '|' || g.grp, jsonb_build_object(
                     'off', round((g.d * g.neff / (g.neff + kk.k))::numeric, 4), 'raw', round(g.d::numeric, 4), 'n', g.n,
                     'n_eff', round(g.neff::numeric, 1), 'k', round(kk.k::numeric, 2))), '{}'::jsonb)
              FROM g JOIN kk USING (kind)
             WHERE g.d IS NOT NULL AND g.neff > 0),
           (SELECT jsonb_object_agg(z.kind, z.rms)
              FROM (SELECT e.kind, round(sqrt(sum(e.w * e.r * e.r) / sum(e.w))::numeric, 4) AS rms FROM e GROUP BY e.kind) z)
      INTO v_lvl, v_rms;
    v_ladder := v_ladder || jsonb_build_object('before_' || v_level, v_rms);
    IF v_level = 'model' THEN
      v_p := jsonb_set(v_p, '{model_cells}', v_lvl);
    ELSE
      v_p := jsonb_set(v_p, '{class_cells}', (v_p -> 'class_cells') || v_lvl);
    END IF;
    v_m := jsonb_build_object('params', v_p);
  END LOOP;

  -- ── each class's own spread: the robust weighted spread of what the class levels leave, shrunk toward the kind's ──
  v_r := ARRAY(SELECT x.lr - (public.ottoq_charge_clock(v_m, x.kind, x.who, x.bat, x.s0, x.s1, x.ckw, x.vkw, NULL) ->> 'f')::float8
                 FROM unnest(v_e) WITH ORDINALITY x ORDER BY x.ordinality);
  v_ladder := v_ladder || jsonb_build_object('after_class_levels',
                (SELECT jsonb_object_agg(z.kind, z.rms) FROM (
                   SELECT x.kind, round(sqrt(sum(x.w * v_r[x.ordinality] ^ 2) / sum(x.w))::numeric, 4) AS rms
                     FROM unnest(v_e) WITH ORDINALITY x GROUP BY x.kind) z));
  WITH e AS (
    SELECT x.kind, x.cls, x.w, x.sid, v_r[x.ordinality] AS r FROM unnest(v_e) WITH ORDINALITY x
  ), src AS (
    SELECT e.kind, e.cls AS grp, abs(e.r) AS dv, e.w, e.sid FROM e
    UNION ALL
    SELECT e.kind, '*', abs(e.r), e.w, e.sid FROM e
  ), o AS (
    SELECT src.*, sum(src.w) OVER (PARTITION BY src.kind, src.grp ORDER BY src.dv, src.sid) AS cw,
           sum(src.w) OVER (PARTITION BY src.kind, src.grp) AS tw
      FROM src
  ), s AS (
    SELECT o.kind, o.grp, 1.4826 * min(o.dv) FILTER (WHERE o.cw >= o.tw / 2) AS sd,
           sum(o.w) * sum(o.w) / NULLIF(sum(o.w * o.w), 0) AS neff
      FROM o GROUP BY o.kind, o.grp
  )
  SELECT jsonb_object_agg(s.kind || '|' || s.grp,
           round(((s.neff * s.sd + 10 * k.sd) / (s.neff + 10))::numeric, 4))
    INTO v_within
    FROM s JOIN s k ON k.kind = s.kind AND k.grp = '*';
  SELECT COALESCE(jsonb_object_agg(c.key, c.value || jsonb_build_object('sd', v_within -> c.key)), '{}'::jsonb)
    INTO v_lvl
    FROM jsonb_each(v_p -> 'class_cells') c
   WHERE array_length(string_to_array(c.key, '|'), 1) = 2 AND v_within ? c.key;
  v_p := jsonb_set(v_p, '{class_cells}', (v_p -> 'class_cells') || v_lvl);
  v_m := jsonb_build_object('params', v_p);

  -- ── the run: how far a run's mean departs beyond sampling (its prior strength), and its shrunk offsets ──
  WITH e AS (
    SELECT x.kind, x.run, x.w, v_r[x.ordinality] AS r FROM unnest(v_e) WITH ORDINALITY x WHERE x.run IS NOT NULL
  ), ru AS (
    SELECT e.kind, e.run, avg(e.r) AS u, count(*) AS n FROM e GROUP BY e.kind, e.run
  ), sw AS (
    SELECT e.kind, sum(e.w * e.r * e.r) / NULLIF(sum(e.w), 0) AS s2 FROM e GROUP BY e.kind
  ), t AS (
    SELECT ru.kind, count(*) AS runs, GREATEST(var_samp(ru.u) - avg(sw.s2 / ru.n), 0) AS t2, max(sw.s2) AS s2
      FROM ru JOIN sw USING (kind) WHERE ru.n >= 3 GROUP BY ru.kind
  )
  SELECT COALESCE(jsonb_object_agg(t.kind, jsonb_build_object(
           'k', round(LEAST(GREATEST(CASE WHEN t.t2 > 1e-4 THEN t.s2 / t.t2 ELSE 1000 END, 1), 1000)::numeric, 2),
           'tau', round(sqrt(t.t2)::numeric, 4), 'runs', t.runs)), '{}'::jsonb)
    INTO v_run
    FROM t;
  v_r2 := ARRAY(
    SELECT v_r[x.ordinality] - COALESCE(ru.u * ru.n / (ru.n + COALESCE((v_run #>> ARRAY[x.kind, 'k'])::float8, 1000)), 0)
      FROM unnest(v_e) WITH ORDINALITY x
      LEFT JOIN (SELECT y.kind, y.run, avg(v_r[y.ordinality]) AS u, count(*) AS n
                   FROM unnest(v_e) WITH ORDINALITY y WHERE y.run IS NOT NULL GROUP BY y.kind, y.run) ru
        ON ru.kind = x.kind AND ru.run = x.run
     ORDER BY x.ordinality);
  v_ladder := v_ladder || jsonb_build_object('after_run',
                (SELECT jsonb_object_agg(z.kind, z.rms) FROM (
                   SELECT x.kind, round(sqrt(sum(x.w * v_r2[x.ordinality] ^ 2) / sum(x.w))::numeric, 4) AS rms
                     FROM unnest(v_e) WITH ORDINALITY x GROUP BY x.kind) z));

  -- ── the car across runs: the correlation of its run means, and its offset shrunk by Spearman-Brown ──
  WITH e AS (
    SELECT x.kind, x.veh, x.run, x.st, x.sid, x.w, v_r2[x.ordinality] AS r FROM unnest(v_e) WITH ORDINALITY x
  ), vr AS (
    SELECT e.kind, e.veh, e.run, avg(e.r) AS m, max(e.w) AS w FROM e GROUP BY e.kind, e.veh, e.run
  ), pr AS (
    SELECT a.kind, a.m AS x, b.m AS y, a.w * b.w AS w
      FROM vr a JOIN vr b ON a.kind = b.kind AND a.veh = b.veh AND a.run < b.run
  ), rho AS (
    SELECT pr.kind, count(*) AS pairs,
           (sum(pr.w * pr.x * pr.y) / sum(pr.w) - (sum(pr.w * pr.x) / sum(pr.w)) * (sum(pr.w * pr.y) / sum(pr.w)))
             / NULLIF(sqrt(GREATEST(sum(pr.w * pr.x * pr.x) / sum(pr.w) - (sum(pr.w * pr.x) / sum(pr.w)) ^ 2, 0))
                      * sqrt(GREATEST(sum(pr.w * pr.y * pr.y) / sum(pr.w) - (sum(pr.w * pr.y) / sum(pr.w)) ^ 2, 0)), 0) AS c
      FROM pr GROUP BY pr.kind
  ), one AS (   -- single charges of the same car in different runs (each run's first), for the share of a charge's spread
    SELECT DISTINCT ON (e.kind, e.veh, e.run) e.kind, e.veh, e.run, e.r, e.w FROM e ORDER BY e.kind, e.veh, e.run, e.st, e.sid
  ), prs AS (
    SELECT a.kind, a.r AS x, b.r AS y, a.w * b.w AS w FROM one a JOIN one b ON a.kind = b.kind AND a.veh = b.veh AND a.run < b.run
  ), rhos AS (
    SELECT prs.kind,
           (sum(prs.w * prs.x * prs.y) / sum(prs.w) - (sum(prs.w * prs.x) / sum(prs.w)) * (sum(prs.w * prs.y) / sum(prs.w)))
             / NULLIF(sqrt(GREATEST(sum(prs.w * prs.x * prs.x) / sum(prs.w) - (sum(prs.w * prs.x) / sum(prs.w)) ^ 2, 0))
                      * sqrt(GREATEST(sum(prs.w * prs.y * prs.y) / sum(prs.w) - (sum(prs.w * prs.y) / sum(prs.w)) ^ 2, 0)), 0) AS c
      FROM prs GROUP BY prs.kind
  )
  SELECT COALESCE(jsonb_object_agg(k.kind, jsonb_build_object(
           'vehicle', round(CASE WHEN COALESCE(rho.pairs, 0) >= c_min_pairs THEN LEAST(GREATEST(rho.c, 0), 0.9) ELSE 0 END::numeric, 4),
           'vehicle_single', round(CASE WHEN COALESCE(rho.pairs, 0) >= c_min_pairs THEN LEAST(GREATEST(rhos.c, 0), 0.9) ELSE 0 END::numeric, 4),
           'vehicle_pairs', COALESCE(rho.pairs, 0))), '{}'::jsonb)
    INTO v_icc
    FROM (SELECT DISTINCT e.kind FROM e) k LEFT JOIN rho USING (kind) LEFT JOIN rhos USING (kind);
  WITH vr AS (
    SELECT x.kind, x.veh, x.run, avg(v_r2[x.ordinality]) AS m, max(x.w) AS w
      FROM unnest(v_e) WITH ORDINALITY x GROUP BY x.kind, x.veh, x.run
  ), v AS (
    SELECT vr.kind, vr.veh, sum(vr.w * vr.m) / NULLIF(sum(vr.w), 0) AS g, sum(vr.w) * sum(vr.w) / NULLIF(sum(vr.w * vr.w), 0) AS reff,
           count(*) AS runs, COALESCE((v_icc #>> ARRAY[vr.kind, 'vehicle'])::float8, 0) AS rho
      FROM vr GROUP BY vr.kind, vr.veh
  )
  SELECT COALESCE(jsonb_object_agg(v.kind || '|' || v.veh, jsonb_build_object(
           's', round((v.reff * v.rho / (1 + (v.reff - 1) * v.rho))::numeric, 4),
           'off', round((v.reff * v.rho / (1 + (v.reff - 1) * v.rho) * v.g)::numeric, 4),
           'runs', v.runs, 'r_eff', round(v.reff::numeric, 2))), '{}'::jsonb)
    INTO v_veh
    FROM v WHERE v.rho > 0 AND v.g IS NOT NULL;
  v_p := jsonb_set(v_p, '{vehicle_cells}', v_veh);
  v_m := jsonb_build_object('params', v_p);

  -- ── the car in its run: consecutive charges of the same car in the same run, once the car's cross-run offset is out ──
  v_r3 := ARRAY(SELECT v_r2[x.ordinality] - COALESCE((v_veh #>> ARRAY[x.kind || '|' || x.veh, 'off'])::float8, 0)
                  FROM unnest(v_e) WITH ORDINALITY x ORDER BY x.ordinality);
  v_ladder := v_ladder || jsonb_build_object('after_vehicle',
                (SELECT jsonb_object_agg(z.kind, z.rms) FROM (
                   SELECT x.kind, round(sqrt(sum(x.w * v_r3[x.ordinality] ^ 2) / sum(x.w))::numeric, 4) AS rms
                     FROM unnest(v_e) WITH ORDINALITY x GROUP BY x.kind) z));
  WITH e AS (
    SELECT x.kind, x.veh, x.run, x.st, x.sid, x.w, v_r3[x.ordinality] AS r FROM unnest(v_e) WITH ORDINALITY x
  ), s AS (
    SELECT e.kind, e.r AS x, lead(e.r) OVER (PARTITION BY e.kind, e.veh, e.run ORDER BY e.st, e.sid) AS y,
           LEAST(e.w, lead(e.w) OVER (PARTITION BY e.kind, e.veh, e.run ORDER BY e.st, e.sid)) AS w
      FROM e
  ), c AS (
    SELECT s.kind, count(*) AS pairs,
           (sum(s.w * s.x * s.y) / sum(s.w) - (sum(s.w * s.x) / sum(s.w)) * (sum(s.w * s.y) / sum(s.w)))
             / NULLIF(sqrt(GREATEST(sum(s.w * s.x * s.x) / sum(s.w) - (sum(s.w * s.x) / sum(s.w)) ^ 2, 0))
                      * sqrt(GREATEST(sum(s.w * s.y * s.y) / sum(s.w) - (sum(s.w * s.y) / sum(s.w)) ^ 2, 0)), 0) AS rho
      FROM s WHERE s.y IS NOT NULL GROUP BY s.kind
  )
  SELECT COALESCE(jsonb_object_agg(k.key, k.value || jsonb_build_object(
           'in_run', round(CASE WHEN COALESCE(c.pairs, 0) >= c_min_pairs THEN LEAST(GREATEST(c.rho, 0), 0.95) ELSE 0 END::numeric, 4),
           'in_run_pairs', COALESCE(c.pairs, 0))), '{}'::jsonb)
    INTO v_icc
    FROM jsonb_each(v_icc) k LEFT JOIN c ON c.kind = k.key;

  -- ── the charge in progress: the remaining part's residual on the done part's, at a quarter, half, three quarters ──
  v_p := v_p || jsonb_build_object('icc', v_icc, 'run', v_run);
  v_m := jsonb_build_object('params', v_p);
  WITH cut AS (
    SELECT x.*, q.frac, x.s0 + q.frac * (x.s1 - x.s0) AS soc_cut
      FROM unnest(v_e) x CROSS JOIN (VALUES (0.25::numeric), (0.5), (0.75)) q(frac)
     WHERE x.s1 - x.s0 >= 8
  ), mv AS (
    SELECT cut.*, m.t_at, m.soc_at
      FROM cut
      CROSS JOIN LATERAL (
        SELECT mm.sim_clock_at AS t_at, (mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric AS soc_at
          FROM ottoq_ocpp_messages mm
         WHERE mm.ocpp_session_id = cut.sid AND mm.message_type = 'MeterValues'
           AND (mm.payload -> 'sampledValue' -> 1 ->> 'measurand') = 'SoC'
           AND (mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric >= cut.soc_cut
         ORDER BY mm.message_at
         LIMIT 1) m
  ), xy AS (
    SELECT mv.kind, mv.w,
           ln((extract(epoch FROM (mv.t_at - mv.st)) / 60.0 / b1.m)::numeric)
             - (public.ottoq_charge_clock(v_m, mv.kind, mv.who, mv.bat, mv.s0, mv.soc_at, mv.ckw, mv.vkw, NULL) ->> 'f')::numeric AS x,
           ln((extract(epoch FROM (mv.en - mv.t_at)) / 60.0 / b2.m)::numeric)
             - (public.ottoq_charge_clock(v_m, mv.kind, mv.who, mv.bat, mv.soc_at, mv.s1, mv.ckw, mv.vkw, NULL) ->> 'f')::numeric AS y,
           mv.sid
      FROM mv
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(mv.bat, mv.s0, mv.soc_at, mv.ckw, mv.vkw) AS m) b1
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(mv.bat, mv.soc_at, mv.s1, mv.ckw, mv.vkw) AS m) b2
     WHERE mv.t_at > mv.st AND mv.en > mv.t_at AND mv.soc_at < mv.s1 AND b1.m >= 3 AND b2.m >= 3
  ), mom AS (
    SELECT xy.kind, count(*) AS n, count(DISTINCT xy.sid) AS sessions, sum(xy.w) AS sw,
           sum(xy.w * xy.x) / sum(xy.w) AS mx, sum(xy.w * xy.y) / sum(xy.w) AS my,
           sum(xy.w * xy.x * xy.x) / sum(xy.w) AS mxx, sum(xy.w * xy.x * xy.y) / sum(xy.w) AS mxy
      FROM xy GROUP BY xy.kind
  ), fit AS (
    SELECT mom.*, LEAST(GREATEST((mom.mxy - mom.mx * mom.my) / NULLIF(mom.mxx - mom.mx * mom.mx, 0), 0), 1) AS b FROM mom
  ), fit2 AS (
    SELECT fit.*, fit.my - fit.b * fit.mx AS a FROM fit
  ), res AS (
    SELECT fit2.kind, sqrt(sum(xy.w * (xy.y - fit2.a - fit2.b * xy.x) ^ 2) / sum(xy.w)) AS s,
           sqrt(sum(xy.w * (xy.y - fit2.my) ^ 2) / sum(xy.w)) AS s0
      FROM xy JOIN fit2 USING (kind) GROUP BY fit2.kind
  )
  SELECT COALESCE(jsonb_object_agg(fit2.kind, jsonb_build_object(
           'a', round(fit2.a::numeric, 4), 'b', round(COALESCE(fit2.b, 0)::numeric, 4), 's', round(res.s::numeric, 4),
           's_without', round(res.s0::numeric, 4), 'n', fit2.n, 'sessions', fit2.sessions, 'min_frac', 0.15,
           'cuts', jsonb_build_array(0.25, 0.5, 0.75))), '{}'::jsonb)
    INTO v_sess
    FROM fit2 JOIN res USING (kind)
   WHERE fit2.n >= 30;

  RETURN v_p || jsonb_build_object(
    'session', v_sess,
    'base', 'ottoq_charge_minutes_estimate', 'bands', jsonb_build_array(45, 70, 85),
    'half_life_days', v_h, 'window_days', round((extract(epoch FROM (v_through - v_from)) / 86400.0)::numeric, 2),
    'population', v_pop, 'min_cell_n', c_min_cell, 'min_cell_n_eff', c_min_neff, 'k_floor', c_k_floor,
    'stopped_reason', 'completed', 'fine_tick_max_min', 1,
    'diagnostics', jsonb_build_object('n', v_n, 'runs', v_runs, 'rms_ladder', v_ladder, 'within_sd', v_within));
END $fn$;

CREATE FUNCTION public.ottoq_fit_charge_time_v2(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                                p_window interval DEFAULT interval '21 days',
                                                p_half_life_days numeric DEFAULT 3, p_note text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0622: fit charge_time_v2 for a depot (ottoq_charge_time_v2_params) and append it to ottoq_charge_clock_fits; returns
   its fit_id. Usable when both kinds have a usable pooled cell. */
DECLARE
  v_through timestamptz := COALESCE(p_through, now());
  v_window  interval := COALESCE(p_window, interval '21 days');
  v_p       jsonb;
  v_id      bigint;
BEGIN
  v_p := public.ottoq_charge_time_v2_params(p_depot, v_through, v_window, p_half_life_days);
  INSERT INTO public.ottoq_charge_clock_fits
    (depot_id, model, evidence_from, evidence_through, n_evidence, n_runs, usable, params, code_md5, note)
  VALUES (p_depot, 'charge_time_v2', v_through - v_window, v_through,
          COALESCE((v_p #>> '{diagnostics,n}')::int, 0), COALESCE((v_p #>> '{diagnostics,runs}')::int, 0),
          COALESCE((v_p #>> '{cells,dcfc:*,usable}')::boolean, false) AND COALESCE((v_p #>> '{cells,l2:*,usable}')::boolean, false),
          v_p,
          md5(pg_get_functiondef('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_who(uuid,text,text,text)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)'::regprocedure)),
          p_note)
  RETURNING fit_id INTO v_id;
  RETURN v_id;
END $fn$;

-- ══ (c) the readers ══════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_line_state(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0620: everything a charge-line rollout reads, once: the line (less a car holding a reserved charger, already
   assigned), the cars coming home within 180 minutes, the chargers (0618's gates), the order's life in minutes and the
   pin, every charge timed and spread by 0619's charge_time_v1. 0622: every charge is timed by the depot's charge clock
   (ottoq_charge_clock on ottoq_charge_clock_model: its charge_time_v2 when it has one, with this run's charges up to
   p_clock), a charge under way by what is left of it (ottoq_charge_clock_remaining); each car carries its class (cls) and
   the levels its clock used (lv). Read-only. */
DECLARE
  c_horizon constant numeric := 480;
  c_window  constant numeric := 180;
  v_ct jsonb := public.ottoq_charge_clock_model(p_depot_id);
  v_rt jsonb := public.ottoq_learned_estimate(p_depot_id, 'return_v1');
  v_ev jsonb;
  v_kw_d numeric; v_kw_l numeric; v_tick numeric; v_ttl numeric; v_pin numeric;
  v_cars jsonb; v_inb jsonb; v_ch jsonb;
BEGIN
  v_ev := public.ottoq_charge_clock_run_evidence(v_ct, p_sim_run_id, p_clock);
  SELECT max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'dcfc'),
         max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'l2')
    INTO v_kw_d, v_kw_l
    FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2');
  SELECT CASE WHEN r.tick_count > 0 AND r.sim_clock_start IS NOT NULL AND r.sim_clock_current > r.sim_clock_start
              THEN extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / r.tick_count END
    INTO v_tick FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  v_tick := COALESCE(v_tick, 0.25);
  v_ttl := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15) * v_tick;
  v_pin := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', x.id, 'w', round(x.wait_min, 2), 'g', round(x.gap, 2), 'imm', x.immediate, 'soc', x.soc,
           'due', x.due, 'dok', x.dok, 'lok', x.lok, 'md', (x.cd ->> 'm')::numeric, 'ml', (x.cl ->> 'm')::numeric,
           'sd', (x.cd ->> 'sd')::numeric, 'sl', (x.cl ->> 'sd')::numeric, 'cls', x.who ->> 'cls', 'lv', x.cd ->> 'lvl')
           ORDER BY x.kernel_pos), '[]'::jsonb)
    INTO v_cars
    FROM (SELECT k.vehicle_id AS id, k.kernel_pos, k.wait_min, k.gap, k.immediate, k.soc, wh.who,
                 round(extract(epoch FROM (vn.dispatch_due_at - p_clock)) / 60.0, 2) AS due,
                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc') AS dok,
                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2') AS lok,
                 public.ottoq_charge_clock(v_ct, 'dcfc', wh.who, v.battery_capacity_kwh, k.soc, tg.t, v_kw_d, v.inlet_max_kw,
                                           v_ev -> 'dcfc') AS cd,
                 public.ottoq_charge_clock(v_ct, 'l2', wh.who, v.battery_capacity_kwh, k.soc, tg.t, v_kw_l, v.inlet_max_kw,
                                           v_ev -> 'l2') AS cl
            FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock) k
            JOIN vehicles v ON v.id = k.vehicle_id
            CROSS JOIN LATERAL (SELECT public.ottoq_effective_target_soc_at(v.id, p_clock) AS t) tg
            CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
            LEFT JOIN LATERAL (SELECT vn.dispatch_due_at FROM ottoq_visit_needs vn
                                WHERE vn.vehicle_id = v.id AND vn.status IN ('open', 'in_progress')
                                  AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                    = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) vn ON true
           WHERE NOT k.holds_charger) x
   WHERE (x.cd ->> 'm') IS NOT NULL AND (x.cl ->> 'm') IS NOT NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', i.vehicle_id, 'eta', i.eta_min, 'src', i.source, 'esd', i.eta_log_sd, 'trip', i.trip_min,
           'soc', i.soc_at_arrival, 'g', round(GREATEST(tg.t - i.soc_at_arrival, 1), 2), 'imm', false, 'w', 0,
           'dok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc'),
           'lok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2'),
           'md', (ck.cd ->> 'm')::numeric, 'ml', (ck.cl ->> 'm')::numeric,
           'sd', (ck.cd ->> 'sd')::numeric, 'sl', (ck.cl ->> 'sd')::numeric, 'cls', wh.who ->> 'cls', 'lv', ck.cd ->> 'lvl')
           ORDER BY i.eta_min, i.vehicle_id), '[]'::jsonb)
    INTO v_inb
    FROM public.ottoq_charge_line_inbound(p_sim_run_id, p_depot_id, p_clock, c_window, v_rt) i
    JOIN vehicles v ON v.id = i.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_effective_target_soc_at(v.id, p_clock) AS t) tg
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(v_ct, 'dcfc', wh.who, v.battery_capacity_kwh, i.soc_at_arrival, tg.t,
                                                         v_kw_d, v.inlet_max_kw, v_ev -> 'dcfc') AS cd,
                               public.ottoq_charge_clock(v_ct, 'l2', wh.who, v.battery_capacity_kwh, i.soc_at_arrival, tg.t,
                                                         v_kw_l, v.inlet_max_kw, v_ev -> 'l2') AS cl) ck
   WHERE i.soc_at_arrival < tg.t - 1 AND v.battery_capacity_kwh IS NOT NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', y.id, 'k', y.kind, 'free', y.free_at, 'sd', y.sd)
                            ORDER BY y.kind, y.free_at, y.id), '[]'::jsonb)
    INTO v_ch
    FROM (
      SELECT s.id, s.stall_type::text AS kind,
             CASE WHEN s.current_vehicle_id IS NULL THEN 0::numeric ELSE (rm.c ->> 'm')::numeric END AS free_at,
             CASE WHEN s.current_vehicle_id IS NULL THEN 0::numeric ELSE (rm.c ->> 'sd')::numeric END AS sd
        FROM stalls s
        JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
        LEFT JOIN vehicles cv ON cv.id = s.current_vehicle_id
        LEFT JOIN LATERAL (SELECT os.soc_start, os.started_at FROM ocpp_sessions os
                            WHERE os.stall_id = s.id AND os.status = 'active' AND os.vehicle_id = cv.id
                            ORDER BY os.started_at DESC LIMIT 1) ses ON cv.id IS NOT NULL
        LEFT JOIN LATERAL (SELECT public.ottoq_charge_clock_remaining(
                                    v_ct, s.stall_type::text,
                                    public.ottoq_charge_clock_who(cv.id, cv.vehicle_class_code, cv.make, cv.model),
                                    cv.battery_capacity_kwh, ses.soc_start, cv.current_soc,
                                    public.ottoq_effective_target_soc_at(cv.id, p_clock), s.connector_max_kw, cv.inlet_max_kw,
                                    extract(epoch FROM (p_clock - ses.started_at)) / 60.0,
                                    v_ev -> s.stall_type::text) AS c) rm ON cv.id IS NOT NULL
       WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2')
         AND c.station_state IS DISTINCT FROM 'Faulted'
         AND (   (s.current_vehicle_id IS NULL
                  AND NOT (s.reserved_by IS NOT NULL AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > p_clock)
                  AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '90 seconds'
                  AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                                   WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                                     AND b.state IN ('held', 'active', 'done', 'interrupted') AND b.during @> p_clock))
              OR cv.current_state::text IN ('charging_dcfc', 'charging_l2'))) y
   WHERE y.free_at IS NOT NULL;

  RETURN jsonb_build_object(
    'v', 1, 'clock', p_clock, 'tick_min', round(v_tick, 4), 'ttl_min', round(v_ttl, 3), 'pin_min', v_pin,
    'horizon_min', c_horizon, 'arrival_window_min', c_window,
    'models', jsonb_build_object('charge_time', v_ct -> 'estimate_id', 'charge_time_model', v_ct ->> 'model',
                                 'return', v_rt -> 'estimate_id',
                                 'return_usable', COALESCE((v_rt ->> 'usable')::boolean, false),
                                 'run_evidence', (SELECT jsonb_object_agg(e.key, e.value -> 'n') FROM jsonb_each(COALESCE(v_ev, '{}'::jsonb)) e)),
    'cars', v_cars, 'inbound', v_inb, 'chargers', v_ch);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_charge_order_realized(p_order_id bigint, p_window_min numeric DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: what actually happened in the p_window_min sim-minutes after a checked order (ottoq_charge_order_snapshots), from
   the run's own records, shaped as the order's state is, in minutes from the order's clock. cars / inbound: each car
   the check saw, keyed by id: its first charge after the order (s0 when, k0 on which kind, m how long, cen true when the
   charge was still running at the cut (m is then a lower bound) or ended any way but completed, end how it ended; m is
   NULL for a charge cut by a fault, which is the faults' part); and for a car the check saw coming home, when it arrived
   (eta; when it had not by the cut, no sooner than the cut), its battery, its due time and immediacy, and its minutes at
   that battery on the check's own charge clock (the snapshot's model, by id). appeared: the cars the check did not see
   that joined the line, as state entries: home inside the window owing a charge (how = returned), or in the depot at
   the order and charged on a charger the check modelled (how = at_depot, joining when it plugged in). chargers: for each
   charger the check modelled, when the charge under way at the order ended (free) and when it was down (dn: from the
   charger's faulted sessions, until the repair on the fault's event). back: the chargers the check left out that came
   back from a repair inside the window. faults: faults inside the window; unmodeled_sessions: charges inside the window
   on chargers the check left out. Read-only.
   0622: "the check's own charge clock" is ottoq_charge_clock on the snapshot's model, with the run's own charges as of the
   order (ottoq_charge_clock_run_evidence): on a 0619 snapshot, exactly what 0621 returned (V5). */
DECLARE
  s record; v_clock timestamptz; v_status text; v_t0 timestamptz; v_cut timestamptz; v_obs numeric;
  v_model jsonb; v_kw_d numeric; v_kw_l numeric; v_ids text[]; v_ch_ids text[]; v_back_ids text[];
  v_cars jsonb; v_inb jsonb; v_app jsonb; v_ch jsonb; v_back jsonb; v_faults int; v_unmod int; v_fs jsonb; v_ev jsonb;
BEGIN
  SELECT * INTO s FROM ottoq_charge_order_snapshots x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT r.sim_clock_current, r.status INTO v_clock, v_status FROM ottoq_sim_runs r WHERE r.sim_run_id = s.sim_run_id;
  v_t0 := s.sim_clock;
  v_cut := GREATEST(LEAST(v_t0 + make_interval(secs => GREATEST(COALESCE(p_window_min, 90), 1) * 60),
                          COALESCE(v_clock, v_t0)), v_t0);
  v_obs := round((extract(epoch FROM (v_cut - v_t0)) / 60.0)::numeric, 2);
  -- the snapshot's clock, by id: a charge_time_v2 fit (0622) or, on every snapshot before it, a charge_time_v1 estimate
  IF (s.state #>> '{models,charge_time}') ~ '^[0-9]+$' THEN
    IF (s.state #>> '{models,charge_time_model}') = 'charge_time_v2' THEN
      SELECT jsonb_build_object('params', f.params) INTO v_model
        FROM ottoq_charge_clock_fits f WHERE f.fit_id = (s.state #>> '{models,charge_time}')::bigint;
    ELSE
      SELECT jsonb_build_object('params', e.params) INTO v_model
        FROM ottoq_learned_estimates e WHERE e.estimate_id = (s.state #>> '{models,charge_time}')::bigint;
    END IF;
  END IF;
  v_ev := public.ottoq_charge_clock_run_evidence(v_model, s.sim_run_id, v_t0);
  SELECT max(st.connector_max_kw) FILTER (WHERE st.stall_type::text = 'dcfc'),
         max(st.connector_max_kw) FILTER (WHERE st.stall_type::text = 'l2')
    INTO v_kw_d, v_kw_l
    FROM stalls st WHERE st.depot_id = s.depot_id AND st.stall_type::text IN ('dcfc', 'l2');
  SELECT COALESCE(array_agg(x.value ->> 'id'), '{}'::text[]) INTO v_ids
    FROM (SELECT value FROM jsonb_array_elements(COALESCE(s.state -> 'cars', '[]'::jsonb))
          UNION ALL
          SELECT value FROM jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb))) x;
  SELECT COALESCE(array_agg(x.value ->> 'id'), '{}'::text[]) INTO v_ch_ids
    FROM jsonb_array_elements(COALESCE(s.state -> 'chargers', '[]'::jsonb)) x;

  -- the chargers the check left out that came back from a repair inside the window
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', b.id, 'k', b.kind, 'free', round(b.back::numeric, 2), 'sd', 0)
                            ORDER BY b.kind, b.back, b.id), '[]'::jsonb),
         COALESCE(array_agg(b.id), '{}'::text[])
    INTO v_back, v_back_ids
    FROM (SELECT DISTINCT ON (os.stall_id) os.stall_id::text AS id, st.stall_type::text AS kind,
                 extract(epoch FROM (COALESCE(ev.at, os.ended_at) + make_interval(secs => COALESCE(ev.rep, 0) * 60) - v_t0)) / 60.0 AS back
            FROM ocpp_sessions os
            JOIN stalls st ON st.id = os.stall_id
            LEFT JOIN LATERAL (SELECT e.sim_clock_at AS at, (e.payload ->> 'repair_minutes')::numeric AS rep
                                 FROM ottoq_events e
                                WHERE e.entity_type = 'ocpp_session' AND e.entity_id = os.id
                                  AND e.event_type = 'charge.session_faulted'
                                ORDER BY e.occurred_at DESC LIMIT 1) ev ON true
           WHERE os.sim_run_id = s.sim_run_id AND os.status::text = 'faulted' AND os.ended_at IS NOT NULL
             AND st.depot_id = s.depot_id AND st.stall_type::text IN ('dcfc', 'l2')
             AND os.stall_id::text <> ALL (v_ch_ids)
             AND COALESCE(ev.at, os.ended_at) < v_t0
           ORDER BY os.stall_id, COALESCE(ev.at, os.ended_at) DESC) b
   WHERE b.back > 0 AND b.back <= v_obs;

  -- the chargers the check modelled: when the charge under way ended, and when each was down
  SELECT COALESCE(jsonb_object_agg(c.id, jsonb_strip_nulls(jsonb_build_object(
           'free', CASE WHEN rs.stall_id IS NULL THEN NULL
                        WHEN rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut
                        THEN round((extract(epoch FROM (rs.ended_at - v_t0)) / 60.0)::numeric, 2)
                        ELSE GREATEST(v_obs, c.free) END,
           'cen', CASE WHEN rs.stall_id IS NOT NULL THEN NOT (rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut) END,
           'dn', dn.w)))
           FILTER (WHERE rs.stall_id IS NOT NULL OR dn.w IS NOT NULL), '{}'::jsonb)
    INTO v_ch
    FROM (SELECT x.value ->> 'id' AS id, COALESCE((x.value ->> 'free')::numeric, 0) AS free
            FROM jsonb_array_elements(COALESCE(s.state -> 'chargers', '[]'::jsonb)) x
           WHERE (x.value ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') c
    LEFT JOIN LATERAL (SELECT os.stall_id, os.ended_at FROM ocpp_sessions os
                        WHERE c.free > 0 AND os.sim_run_id = s.sim_run_id AND os.stall_id = c.id::uuid
                          AND os.started_at < v_t0 AND (os.ended_at IS NULL OR os.ended_at > v_t0)
                        ORDER BY os.started_at DESC LIMIT 1) rs ON true
    LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_array(round(f.a::numeric, 2), round((f.a + f.rep)::numeric, 2))
                                        ORDER BY f.a) AS w
                         FROM (SELECT extract(epoch FROM (COALESCE(ev.at, os.ended_at) - v_t0)) / 60.0 AS a,
                                      COALESCE(ev.rep, 0) AS rep
                                 FROM ocpp_sessions os
                                 LEFT JOIN LATERAL (SELECT e.sim_clock_at AS at, (e.payload ->> 'repair_minutes')::numeric AS rep
                                                      FROM ottoq_events e
                                                     WHERE e.entity_type = 'ocpp_session' AND e.entity_id = os.id
                                                       AND e.event_type = 'charge.session_faulted'
                                                     ORDER BY e.occurred_at DESC LIMIT 1) ev ON true
                                WHERE os.sim_run_id = s.sim_run_id AND os.stall_id = c.id::uuid
                                  AND os.status::text = 'faulted' AND os.ended_at IS NOT NULL
                                  AND COALESCE(ev.at, os.ended_at) >= v_t0 AND COALESCE(ev.at, os.ended_at) < v_cut) f) dn ON true;

  SELECT count(*) INTO v_faults
    FROM ocpp_sessions os JOIN stalls st ON st.id = os.stall_id
   WHERE os.sim_run_id = s.sim_run_id AND os.status::text = 'faulted' AND os.ended_at >= v_t0 AND os.ended_at < v_cut
     AND st.depot_id = s.depot_id;
  SELECT count(*) INTO v_unmod
    FROM ocpp_sessions os JOIN stalls st ON st.id = os.stall_id
   WHERE os.sim_run_id = s.sim_run_id AND os.started_at >= v_t0 AND os.started_at < v_cut
     AND st.depot_id = s.depot_id AND st.stall_type::text IN ('dcfc', 'l2')
     AND os.stall_id::text <> ALL (v_ch_ids || v_back_ids);

  -- every car's first charge after the order, keyed by vehicle: {j: the car's record, stall, started_at, soc_start}
  SELECT COALESCE(jsonb_object_agg(f.id, jsonb_build_object(
           'j', jsonb_build_object(
                  's0', round((extract(epoch FROM (f.started_at - v_t0)) / 60.0)::numeric, 2),
                  'k0', f.kind,
                  'm', CASE WHEN f.status = 'faulted' OR COALESCE(f.stopped_reason, '') LIKE 'fault.%' THEN NULL
                            ELSE round((extract(epoch FROM (LEAST(COALESCE(f.ended_at, v_cut), v_cut) - f.started_at)) / 60.0)::numeric, 2) END,
                  'cen', NOT (f.ended_at IS NOT NULL AND f.ended_at <= v_cut AND f.stopped_reason = 'completed'),
                  'end', CASE WHEN f.ended_at IS NULL OR f.ended_at > v_cut THEN 'running'
                              ELSE COALESCE(f.stopped_reason, f.status) END),
           'stall', f.stall, 'started_at', f.started_at, 'soc_start', f.soc_start)), '{}'::jsonb)
    INTO v_fs
    FROM (SELECT DISTINCT ON (os.vehicle_id) os.vehicle_id::text AS id, os.started_at, os.ended_at, os.stopped_reason,
                 os.status::text AS status, os.stall_id::text AS stall, st.stall_type::text AS kind, os.soc_start
            FROM ocpp_sessions os JOIN stalls st ON st.id = os.stall_id
           WHERE os.sim_run_id = s.sim_run_id AND os.vehicle_id IS NOT NULL
             AND os.started_at >= v_t0 AND os.started_at < v_cut AND st.stall_type::text IN ('dcfc', 'l2')
           ORDER BY os.vehicle_id, os.started_at, os.id) f;

  SELECT COALESCE(jsonb_object_agg(c.id, COALESCE(v_fs #> ARRAY[c.id, 'j'], jsonb_build_object('s0', NULL))), '{}'::jsonb)
    INTO v_cars
    FROM (SELECT x.value ->> 'id' AS id FROM jsonb_array_elements(COALESCE(s.state -> 'cars', '[]'::jsonb)) x) c;

  SELECT COALESCE(jsonb_object_agg(i.id, q.j), '{}'::jsonb)
    INTO v_inb
    FROM (SELECT x.value AS e, x.value ->> 'id' AS id
            FROM jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) x) i
    JOIN vehicles v ON v.id::text = i.id
    LEFT JOIN LATERAL (SELECT d.actual_return_at, d.soc_at_return_pct FROM ottoq_vehicle_dispatches d
                        WHERE d.sim_run_id = s.sim_run_id AND d.vehicle_id = v.id AND d.dispatched_at <= v_t0
                        ORDER BY d.dispatched_at DESC LIMIT 1) d ON true
    CROSS JOIN LATERAL (SELECT (d.actual_return_at IS NOT NULL AND d.actual_return_at >= v_t0
                                AND d.actual_return_at <= v_cut) AS arrived) a
    CROSS JOIN LATERAL (SELECT CASE WHEN a.arrived THEN COALESCE(d.soc_at_return_pct, (i.e ->> 'soc')::numeric)
                                    ELSE (i.e ->> 'soc')::numeric END AS soc,
                               public.ottoq_effective_target_soc_at(v.id, v_t0) AS tgt) b
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(v_model, 'dcfc', wh.who, v.battery_capacity_kwh, b.soc, b.tgt, v_kw_d,
                                                         v.inlet_max_kw, v_ev -> 'dcfc') AS cd,
                               public.ottoq_charge_clock(v_model, 'l2', wh.who, v.battery_capacity_kwh, b.soc, b.tgt, v_kw_l,
                                                         v.inlet_max_kw, v_ev -> 'l2') AS cl) ck
    LEFT JOIN LATERAL (SELECT vn.dispatch_due_at, vn.urgency FROM ottoq_visit_needs vn
                        WHERE a.arrived AND vn.vehicle_id = v.id AND vn.sim_run_id = s.sim_run_id
                          AND vn.arrived_at >= d.actual_return_at - interval '2 minutes' AND vn.arrived_at <= v_cut
                        ORDER BY vn.arrived_at, vn.created_at LIMIT 1) vn ON true
    CROSS JOIN LATERAL (SELECT COALESCE(v_fs #> ARRAY[i.id, 'j'], '{}'::jsonb) || jsonb_build_object(
        'arrived', a.arrived,
        'eta', CASE WHEN a.arrived THEN round((extract(epoch FROM (d.actual_return_at - v_t0)) / 60.0)::numeric, 2)
                    ELSE round(GREATEST(COALESCE((i.e ->> 'eta')::numeric, 0), v_obs), 2) END,
        'soc', round(b.soc, 1),
        'g', round(GREATEST(b.tgt - b.soc, 1), 2),
        'md', (ck.cd ->> 'm')::numeric,
        'ml', (ck.cl ->> 'm')::numeric,
        'sd', (ck.cd ->> 'sd')::numeric,
        'sl', (ck.cl ->> 'sd')::numeric,
        'due', CASE WHEN vn.dispatch_due_at IS NOT NULL
                    THEN round((extract(epoch FROM (vn.dispatch_due_at - v_t0)) / 60.0)::numeric, 2) END,
        'imm', COALESCE(vn.urgency = 'immediate_dispatch', false)) AS j) q;

  -- the cars the check did not see that joined the line: home inside the window owing a charge, or in the depot and
  -- charged on a charger the check modelled
  SELECT COALESCE(jsonb_agg(z.j ORDER BY (z.j ->> 'eta')::numeric, z.j ->> 'id'), '[]'::jsonb)
    INTO v_app
    FROM (
      SELECT COALESCE(fs.f -> 'j', '{}'::jsonb) || jsonb_build_object(
               'id', v.id::text, 'src', 'appeared', 'how', CASE WHEN rt.actual_return_at IS NOT NULL THEN 'returned' ELSE 'at_depot' END,
               'eta', round((extract(epoch FROM (COALESCE(rt.actual_return_at, fs.plug_at) - v_t0)) / 60.0)::numeric, 2),
               'esd', 0, 'trip', 0, 'w', 0, 'soc', round(b.soc, 1), 'g', round(GREATEST(b.tgt - b.soc, 1), 2),
               'imm', COALESCE(vn.urgency = 'immediate_dispatch', false),
               'due', CASE WHEN vn.dispatch_due_at IS NOT NULL
                           THEN round((extract(epoch FROM (vn.dispatch_due_at - v_t0)) / 60.0)::numeric, 2) END,
               'dok', public.ottoq_charge_kind_compatible(v.id, s.depot_id, 'dcfc'),
               'lok', public.ottoq_charge_kind_compatible(v.id, s.depot_id, 'l2'),
               'md', (ck.cd ->> 'm')::numeric,
               'ml', (ck.cl ->> 'm')::numeric,
               'sd', (ck.cd ->> 'sd')::numeric,
               'sl', (ck.cl ->> 'sd')::numeric) AS j
        FROM (SELECT k.key AS id FROM jsonb_each(v_fs) k
               WHERE k.key <> ALL (v_ids)
                 AND ((k.value ->> 'stall') = ANY (v_ch_ids) OR (k.value ->> 'stall') = ANY (v_back_ids))
              UNION
              SELECT d.vehicle_id::text FROM ottoq_vehicle_dispatches d
               WHERE d.sim_run_id = s.sim_run_id AND d.actual_return_at > v_t0 AND d.actual_return_at <= v_cut
                 AND d.vehicle_id::text <> ALL (v_ids)
                 -- a car whose first charge was on a charger the check left out never competed for the ones it modelled
                 AND NOT (v_fs ? d.vehicle_id::text
                          AND NOT ((v_fs #>> ARRAY[d.vehicle_id::text, 'stall']) = ANY (v_ch_ids)
                                   OR (v_fs #>> ARRAY[d.vehicle_id::text, 'stall']) = ANY (v_back_ids)))) cand
        JOIN vehicles v ON v.id::text = cand.id AND v.home_depot_id = s.depot_id AND v.category = 'autonomous'
        CROSS JOIN LATERAL (SELECT v_fs -> cand.id AS f, (v_fs #>> ARRAY[cand.id, 'started_at'])::timestamptz AS plug_at,
                                   (v_fs #>> ARRAY[cand.id, 'soc_start'])::numeric AS soc_start) fs
        LEFT JOIN LATERAL (SELECT d.actual_return_at, d.soc_at_return_pct FROM ottoq_vehicle_dispatches d
                            WHERE d.sim_run_id = s.sim_run_id AND d.vehicle_id = v.id AND d.actual_return_at > v_t0
                              AND d.actual_return_at <= COALESCE(fs.plug_at, v_cut)
                            ORDER BY d.actual_return_at DESC LIMIT 1) rt ON true
        CROSS JOIN LATERAL (SELECT COALESCE(rt.soc_at_return_pct, fs.soc_start) AS soc,
                                   public.ottoq_effective_target_soc_at(v.id, v_t0) AS tgt) b
        CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
        CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(v_model, 'dcfc', wh.who, v.battery_capacity_kwh, b.soc, b.tgt,
                                                             v_kw_d, v.inlet_max_kw, v_ev -> 'dcfc') AS cd,
                                   public.ottoq_charge_clock(v_model, 'l2', wh.who, v.battery_capacity_kwh, b.soc, b.tgt,
                                                             v_kw_l, v.inlet_max_kw, v_ev -> 'l2') AS cl) ck
        LEFT JOIN LATERAL (SELECT vn.dispatch_due_at, vn.urgency FROM ottoq_visit_needs vn
                            WHERE vn.vehicle_id = v.id AND vn.sim_run_id = s.sim_run_id
                              AND vn.arrived_at <= COALESCE(rt.actual_return_at, fs.plug_at) + interval '2 minutes'
                            ORDER BY vn.arrived_at DESC, vn.created_at DESC LIMIT 1) vn ON true
       WHERE COALESCE(rt.actual_return_at, fs.plug_at) IS NOT NULL AND b.soc IS NOT NULL AND b.soc < b.tgt - 1
         AND v.battery_capacity_kwh IS NOT NULL) z;

  RETURN jsonb_build_object(
    'v', 1, 'order_id', p_order_id, 'window_min', COALESCE(p_window_min, 90), 'observed_min', v_obs,
    'run_status', v_status, 'cut', v_cut,
    'cars', v_cars, 'inbound', v_inb, 'appeared', v_app, 'chargers', v_ch, 'back', v_back,
    'faults', v_faults, 'unmodeled_sessions', v_unmod);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_queue_board(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0614: the charge line as the agent needs it to order it, read-only. The head 24 cars in the kernel's own order,
  -- each with what it owes (to rule 9's one target, ottoq_effective_target_soc_at), the minutes that charge takes on
  -- each kind of charger here, its whole wait against its contract's queue limit, its other open work, the kernel's own
  -- rule for its kind, and whether it can plug into each kind at all. Then the chargers: free and down by kind, and the
  -- in-use ones that free soonest. 0620: every minute is the learned clock (0619 charge_time_v1, on the depot's fastest
  -- charger of the kind); 'contention' sets the cars waiting against the chargers free now and freeing within 15
  -- minutes; 'arriving' lists the cars coming home (ottoq_charge_line_inbound); 'check' states the bar an order meets.
  -- 0621: 'track_record' says how the agent's orders did in what actually happened (ottoq_charge_order_track_record).
  -- 0622: every minute is the depot's charge clock (ottoq_charge_clock on ottoq_charge_clock_model, with this run's own
  -- charges): each car's minutes are its own (its class, model and past charges), 'clock' names the levels used, a
  -- charger in use frees by what is left of its charge (ottoq_charge_clock_remaining), and 'check.charge_clock' says
  -- which clock this is and how each class charges against the depot's typical car.
  WITH k AS (
    SELECT * FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock) WHERE kernel_pos <= 24
  ), kw AS (
    SELECT max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'dcfc') AS dcfc_kw,
           max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'l2')   AS l2_kw
      FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc','l2')
  ), m AS (
    SELECT public.ottoq_charge_clock_model(p_depot_id) AS ct,
           public.ottoq_learned_estimate(p_depot_id, 'return_v1') AS rt
  ), ev AS (
    SELECT public.ottoq_charge_clock_run_evidence((SELECT ct FROM m), p_sim_run_id, p_clock) AS j
  ), cars AS (
    SELECT k.kernel_pos, jsonb_build_object(
             'vehicle_id', v.id, 'name', COALESCE(v.display_name, v.id::text),
             'operator', fo.name,
             'soc', round(k.soc, 1),
             'target', round(public.ottoq_effective_target_soc_at(v.id, p_clock), 0),
             'kwh_owed', round(COALESCE(v.battery_capacity_kwh, 0)
                               * GREATEST(public.ottoq_effective_target_soc_at(v.id, p_clock) - k.soc, 0) / 100.0, 1),
             'min_on_dcfc', round((ck.cd ->> 'm')::numeric, 0),
             'min_on_l2', round((ck.cl ->> 'm')::numeric, 0),
             'clock', ck.cd ->> 'lvl',
             'wait_min', round(k.wait_min, 0),
             'contract_wait_limit_min', sla.max_queue_wait_minutes,
             'over_limit_min', CASE WHEN sla.max_queue_wait_minutes IS NOT NULL
                                    THEN GREATEST(round(k.wait_min - sla.max_queue_wait_minutes, 0), 0) END,
             'urgency', vn.urgency,
             'due_in_min', CASE WHEN vn.dispatch_due_at IS NOT NULL
                                THEN round(extract(epoch FROM (vn.dispatch_due_at - p_clock)) / 60.0, 0) END,
             'other_work', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                       'svc', a ->> 'svc', 'min', a -> 'est_min',
                                       'where', CASE WHEN a ->> 'concurrency' = 'bay' THEN 'bay' ELSE 'in_place' END)
                                       ORDER BY a ->> 'svc')
                                       FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                                      WHERE a ->> 'svc' NOT IN ('charge', 'readiness_check')
                                        AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')), '[]'::jsonb),
             'rule_kind', CASE WHEN k.soc < 45 OR k.immediate THEN 'dcfc' ELSE 'l2' END,
             'dcfc_ok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc'),
             'l2_ok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2'),
             'holds_charger', k.holds_charger,
             'kernel_pos', k.kernel_pos) AS j
      FROM k JOIN vehicles v ON v.id = k.vehicle_id
      LEFT JOIN fleet_operators fo ON fo.id = v.fleet_operator_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock((SELECT ct FROM m), 'dcfc', wh.who, v.battery_capacity_kwh, k.soc,
                                   public.ottoq_effective_target_soc_at(v.id, p_clock), (SELECT dcfc_kw FROM kw),
                                   v.inlet_max_kw, (SELECT j -> 'dcfc' FROM ev)) AS cd,
                                 public.ottoq_charge_clock((SELECT ct FROM m), 'l2', wh.who, v.battery_capacity_kwh, k.soc,
                                   public.ottoq_effective_target_soc_at(v.id, p_clock), (SELECT l2_kw FROM kw),
                                   v.inlet_max_kw, (SELECT j -> 'l2' FROM ev)) AS cl) ck
      LEFT JOIN LATERAL (SELECT s.max_queue_wait_minutes FROM ottoq_fleet_operator_slas s
                          WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status = 'active'
                            AND s.effective_from <= p_clock AND (s.effective_until IS NULL OR s.effective_until > p_clock)
                          ORDER BY s.version DESC LIMIT 1) sla ON true
      LEFT JOIN LATERAL (SELECT vn.urgency, vn.dispatch_due_at, vn.atoms FROM ottoq_visit_needs vn
                          WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                            AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                          ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) vn ON true
  ), st AS (
    SELECT s.id, s.stall_type::text AS kind, COALESCE(s.display_name, s.stall_code) AS name, s.connector_max_kw,
           s.current_vehicle_id,
           COALESCE(c.station_state = 'Faulted', false) AS faulted,
           (s.current_vehicle_id IS NULL
            AND NOT (s.reserved_by IS NOT NULL AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > p_clock)
            AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '90 seconds'
            AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                             WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                               AND b.state IN ('held','active','done','interrupted') AND b.during @> p_clock)) AS free
      FROM stalls s LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc','l2')
  ), soon AS (
    SELECT st.kind, st.name, COALESCE(v.display_name, v.id::text) AS car,
           round((public.ottoq_charge_clock_remaining(
                    (SELECT ct FROM m), st.kind, public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model),
                    v.battery_capacity_kwh, ses.soc_start, v.current_soc, public.ottoq_effective_target_soc_at(v.id, p_clock),
                    st.connector_max_kw, v.inlet_max_kw, extract(epoch FROM (p_clock - ses.started_at)) / 60.0,
                    (SELECT j FROM ev) -> st.kind) ->> 'm')::numeric, 0) AS in_min
      FROM st JOIN vehicles v ON v.id = st.current_vehicle_id
      LEFT JOIN LATERAL (SELECT os.soc_start, os.started_at FROM ocpp_sessions os
                          WHERE os.stall_id = st.id AND os.status = 'active' AND os.vehicle_id = v.id
                          ORDER BY os.started_at DESC LIMIT 1) ses ON true
     WHERE v.current_state::text IN ('charging_dcfc', 'charging_l2')
  ), inb AS (
    SELECT i.*, COALESCE(v.display_name, v.id::text) AS name
      FROM public.ottoq_charge_line_inbound(p_sim_run_id, p_depot_id, p_clock, 180, (SELECT rt FROM m)) i
      JOIN vehicles v ON v.id = i.vehicle_id
  ), ln AS (
    SELECT count(*) AS waiting FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock)
  ), cn AS (
    SELECT (SELECT waiting FROM ln) AS waiting,
           (SELECT count(*) FROM st WHERE st.free) AS free_now,
           (SELECT count(*) FROM soon WHERE soon.in_min <= 15) AS freeing_15
  )
  SELECT jsonb_build_object(
    'pin_wait_min', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90),
    'ttl_ticks', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15),
    'chargers', jsonb_build_object(
      'free', jsonb_build_object('dcfc', (SELECT count(*) FROM st WHERE st.kind = 'dcfc' AND st.free),
                                 'l2',   (SELECT count(*) FROM st WHERE st.kind = 'l2' AND st.free)),
      'down', jsonb_build_object('dcfc', (SELECT count(*) FROM st WHERE st.kind = 'dcfc' AND st.faulted),
                                 'l2',   (SELECT count(*) FROM st WHERE st.kind = 'l2' AND st.faulted)),
      'total', jsonb_build_object('dcfc', (SELECT count(*) FROM st WHERE st.kind = 'dcfc'),
                                  'l2',   (SELECT count(*) FROM st WHERE st.kind = 'l2')),
      'kw', jsonb_build_object('dcfc', (SELECT dcfc_kw FROM kw), 'l2', (SELECT l2_kw FROM kw)),
      'freeing_soonest', COALESCE((SELECT jsonb_agg(jsonb_build_object('kind', x.kind, 'stall', x.name, 'car', x.car,
                                                                       'in_min', x.in_min) ORDER BY x.in_min, x.name)
                                     FROM (SELECT * FROM soon ORDER BY soon.in_min NULLS LAST, soon.name LIMIT 8) x),
                                  '[]'::jsonb)),
    'waiting', (SELECT waiting FROM ln),
    -- 0620: how tight the line is: none = every car waiting can plug in now; tight = it can within 15 minutes;
    -- congested = it cannot. The order matters most when the line is congested.
    'contention', (SELECT jsonb_build_object(
                     'waiting', cn.waiting, 'free_now', cn.free_now, 'freeing_15_min', cn.freeing_15,
                     'arriving_60_min', (SELECT count(*) FROM inb WHERE inb.eta_min <= 60),
                     'pressure', CASE WHEN cn.waiting <= cn.free_now THEN 'none'
                                      WHEN cn.waiting <= cn.free_now + cn.freeing_15 THEN 'tight'
                                      ELSE 'congested' END)
                     FROM cn),
    -- 0620: the cars coming home, soonest first: a car driving home (returning) or one the depot forecasts will be
    -- called home for its reserve (forecast)
    'arriving', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', x.name, 'eta_min', round(x.eta_min, 0),
                                                              'soc', round(x.soc_at_arrival, 0), 'source', x.source)
                                           ORDER BY x.eta_min, x.name)
                            FROM (SELECT * FROM inb ORDER BY inb.eta_min, inb.name LIMIT 12) x), '[]'::jsonb),
    -- 0620: the bar the kernel's check sets, and the learned clock it times every charge by
    'check', jsonb_build_object(
      'futures', GREATEST(1, LEAST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_futures', 12), 12), 64))::int,
      'win_frac', LEAST(GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_win_frac', 0.8), 0.8), 0.5), 1),
      'charge_time_factors', (SELECT jsonb_object_agg(c.key, (c.value ->> 'factor')::numeric)
                                FROM m, jsonb_each(COALESCE(m.ct #> '{params,cells}', '{}'::jsonb)) c
                               WHERE (c.value ->> 'usable')::boolean),
      -- 0622: which clock times the line, and each class against the depot's typical charge of the same kind and band
      'charge_clock', (SELECT jsonb_build_object(
                         'model', m.ct ->> 'model', 'estimate_id', m.ct -> 'estimate_id', 'fitted_at', m.ct -> 'fitted_at',
                         'class_vs_typical', (SELECT jsonb_object_agg(x.cls, x.j) FROM (
                             SELECT split_part(c.key, '|', 2) AS cls,
                                    jsonb_object_agg(split_part(c.key, '|', 1), round(exp((c.value ->> 'off')::numeric), 2)) AS j
                               FROM jsonb_each(COALESCE(m.ct #> '{params,class_cells}', '{}'::jsonb)) c
                              WHERE array_length(string_to_array(c.key, '|'), 1) = 2
                              GROUP BY split_part(c.key, '|', 2)) x),
                         'this_run_charges', (SELECT jsonb_object_agg(e.key, e.value -> 'n') FROM ev, jsonb_each(COALESCE(ev.j, '{}'::jsonb)) e))
                         FROM m),
      'return_model', (SELECT jsonb_build_object('reserve_soc', m.rt #> '{params,threshold_soc}',
                                                 'drain_pct_per_min', m.rt #> '{params,drain_pct_per_min}',
                                                 'drive_home_min', m.rt #> '{params,trip_min}',
                                                 'returns_not_forecast', m.rt #> '{params,other_share}')
                         FROM m WHERE COALESCE((m.rt ->> 'usable')::boolean, false))),
    'cars', COALESCE((SELECT jsonb_agg(cars.j ORDER BY cars.kernel_pos) FROM cars), '[]'::jsonb),
    'last_order', (
      SELECT jsonb_build_object('order_id', x.order_id, 'status', x.status, 'offered', x.n_offered,
                                'accepted', x.n_accepted, 'dropped', x.dropped, 'projection', x.projection - 'per',
                                'age_ticks', COALESCE((SELECT r.tick_count FROM ottoq_sim_runs r
                                                        WHERE r.sim_run_id = p_sim_run_id), x.recorded_tick) - x.recorded_tick)
        FROM ottoq_agent_charge_orders x WHERE x.sim_run_id = p_sim_run_id
       ORDER BY x.order_id DESC LIMIT 1),
    'usage', public.ottoq_agent_charge_order_usage(p_sim_run_id, 3),
    -- 0621: the agent's orders replayed with what actually happened: by outcome, by move, and what made the check wrong
    'track_record', public.ottoq_charge_order_track_record(p_sim_run_id, p_depot_id, 7))
$function$;

-- ══ (d) the check's charge forecasts against what came, without the window's survivorship ═══════════════════════════════
CREATE FUNCTION public.ottoq_charge_clock_calibration(p_depot_id uuid, p_since timestamptz DEFAULT now() - interval '7 days')
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0622: every charge the check timed (a car in its line or one it saw coming) that began inside a graded order's window,
  -- once: the check's last forecast before the charge began. Kept only when it would have finished inside the window at
  -- the forecast's 90th percentile (start + forecast x exp(1.2816 sd) <= observed minutes): a charge that starts late
  -- and runs long is never seen to finish, so keeping only those that did biases a window's sample short. A kept charge
  -- that had not finished by the cut ran past its 90th percentile: counted as overran, outside the band. By kind, by
  -- class and by the clock levels used (cls and lv on 0622 states; a 0621 state's car is placed by its class now).
  WITH h AS (
    SELECT h.order_id, h.sim_run_id, h.sim_clock, h.observed_min, h.realized, s.state
      FROM ottoq_charge_order_hindsight h JOIN ottoq_charge_order_snapshots s ON s.order_id = h.order_id
     WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
  ), c AS (
    SELECT h.sim_run_id, h.sim_clock, h.observed_min, x.value AS e, h.realized #> ARRAY['cars', x.value ->> 'id'] AS r,
           NULL::jsonb AS ri
      FROM h CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h.state -> 'cars', '[]'::jsonb)) x
    UNION ALL
    SELECT h.sim_run_id, h.sim_clock, h.observed_min, x.value, h.realized #> ARRAY['inbound', x.value ->> 'id'],
           h.realized #> ARRAY['inbound', x.value ->> 'id']
      FROM h CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h.state -> 'inbound', '[]'::jsonb)) x
  ), f AS (
    SELECT c.sim_run_id, c.sim_clock, c.observed_min, c.e ->> 'id' AS vid, c.r ->> 'k0' AS kind,
           (c.r ->> 's0')::numeric AS s0, (c.r ->> 'm')::numeric AS m, COALESCE((c.r ->> 'cen')::boolean, true) AS cen,
           CASE WHEN c.r ->> 'k0' = 'dcfc' THEN COALESCE((c.ri ->> 'md')::numeric, (c.e ->> 'md')::numeric)
                ELSE COALESCE((c.ri ->> 'ml')::numeric, (c.e ->> 'ml')::numeric) END AS fc,
           CASE WHEN c.r ->> 'k0' = 'dcfc' THEN COALESCE((c.ri ->> 'sd')::numeric, (c.e ->> 'sd')::numeric)
                ELSE COALESCE((c.ri ->> 'sl')::numeric, (c.e ->> 'sl')::numeric) END AS sd,
           c.e ->> 'cls' AS cls, COALESCE(c.e ->> 'lv', 'v1') AS lv
      FROM c
     WHERE c.r ->> 'k0' IN ('dcfc', 'l2') AND jsonb_typeof(c.r -> 'm') = 'number' AND jsonb_typeof(c.r -> 's0') = 'number'
  ), g AS (
    SELECT DISTINCT ON (f.vid, f.sim_run_id, f.sim_clock + make_interval(secs => f.s0 * 60)) f.*
      FROM f
     WHERE f.fc > 0 AND f.m > 0 AND f.s0 >= 0
       AND f.s0 + f.fc * exp(1.2816 * COALESCE(f.sd, 0)) <= f.observed_min
     ORDER BY f.vid, f.sim_run_id, f.sim_clock + make_interval(secs => f.s0 * 60), f.sim_clock DESC
  ), z AS (
    SELECT g.kind, g.cen, g.lv, COALESCE(g.cls, v.vehicle_class_code, '?') AS cls,
           ln(g.m / g.fc) AS lr, CASE WHEN g.sd > 0 THEN ln(g.m / g.fc) / g.sd END AS z
      FROM g LEFT JOIN vehicles v ON v.id::text = g.vid
  ), a AS (
    SELECT z.kind, z.cls, z.lv, z.cen, z.lr, z.z, 'kind' AS by_, z.kind AS key FROM z
    UNION ALL SELECT z.kind, z.cls, z.lv, z.cen, z.lr, z.z, 'class', z.kind || '|' || z.cls FROM z
    UNION ALL SELECT z.kind, z.cls, z.lv, z.cen, z.lr, z.z, 'level', z.kind || '|' || z.lv FROM z
  ), s AS (
    SELECT a.by_, a.key, jsonb_build_object(
             'charges', count(*), 'finished', count(*) FILTER (WHERE NOT a.cen), 'overran', count(*) FILTER (WHERE a.cen),
             'factor_off_by', round(exp(avg(a.lr) FILTER (WHERE NOT a.cen))::numeric, 3),
             'z_mean', round((avg(a.z) FILTER (WHERE NOT a.cen))::numeric, 3),
             'z_sd', round((stddev_samp(a.z) FILTER (WHERE NOT a.cen))::numeric, 3),
             'in_80pct_band', round((count(*) FILTER (WHERE NOT a.cen AND abs(a.z) <= 1.2816))::numeric / NULLIF(count(*), 0), 3)) AS j
      FROM a GROUP BY a.by_, a.key
  )
  SELECT jsonb_build_object(
    'since', p_since,
    'rule', 'one per charge (the check''s last forecast before it began); kept when it would finish inside the window at '
            'the forecast''s 90th percentile; one not finished by the cut is overran, outside the band',
    'by_kind', COALESCE((SELECT jsonb_object_agg(s.key, s.j) FROM s WHERE s.by_ = 'kind'), '{}'::jsonb),
    'by_class', COALESCE((SELECT jsonb_object_agg(s.key, s.j) FROM s WHERE s.by_ = 'class'), '{}'::jsonb),
    'by_level', COALESCE((SELECT jsonb_object_agg(s.key, s.j) FROM s WHERE s.by_ = 'level'), '{}'::jsonb))
$fn$;

-- ══ (e) the clock's residuals against every recorded covariate ══════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_clock_audit(p_depot_id uuid, p_since timestamptz DEFAULT now() - interval '7 days',
                                               p_model jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0622: the depot's clock (or p_model) and 0619's on the depot's completed fine-tick charges recorded since p_since:
  -- out of sample when 30 or more were recorded after the clock was fitted, else in sample, and said so. For each kind:
  -- each clock's mean log error, mean absolute log error and share inside its own 80% band; then, on what the clock
  -- leaves unexplained, each recorded covariate's adjusted eta squared (groups of 5 or more, the rest pooled):
  -- 1 - (1 - SSB/SST)(N - 1)/(N - G). The clock models class, model, vehicle and band; any other covariate at 0.05 or
  -- more is a variable the clock misses, and a modelled one at 0.05 or more is a level gone stale.
  WITH m AS (
    SELECT COALESCE(p_model, public.ottoq_charge_clock_model(p_depot_id)) AS j2,
           public.ottoq_learned_estimate(p_depot_id, 'charge_time_v1') AS j1
  ), e AS (
    SELECT l.session_id, l.sim_run_id AS run, l.charger_type AS kind, public.ottoq_charge_time_band(l.soc_start) AS band,
           w.j AS who, l.stall_id, l.ambient_temp_c, l.started_at, l.soc_end,
           ln((l.duration_min / est.m)::numeric) AS lr,
           public.ottoq_charge_clock(m.j2, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                     l.vehicle_kw, NULL) AS c2,
           public.ottoq_charge_clock(m.j1, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                     l.vehicle_kw, NULL) AS c1,
           l.recorded_at > COALESCE((m.j2 ->> 'fitted_at')::timestamptz, '-infinity'::timestamptz) AS oos
      FROM m, public.ottoq_charge_duration_ledger l
      JOIN public.vehicles v ON v.id = l.vehicle_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                      l.vehicle_kw) AS m) est
     WHERE l.depot_id = p_depot_id AND l.recorded_at >= p_since AND l.stopped_reason = 'completed'
       AND l.charger_type IN ('dcfc', 'l2') AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0
       AND l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1
  ), pop AS (
    SELECT e.kind, count(*) FILTER (WHERE e.oos) >= 30 AS use_oos FROM e GROUP BY e.kind
  ), r AS (
    SELECT e.*, p.use_oos, e.lr - (e.c2 ->> 'f')::numeric AS res2, e.lr - (e.c1 ->> 'f')::numeric AS res1,
           (e.c2 ->> 'sd')::numeric AS sd2, (e.c1 ->> 'sd')::numeric AS sd1
      FROM e JOIN pop p USING (kind)
     WHERE e.oos OR NOT p.use_oos
  ), acc AS (
    SELECT r.kind, jsonb_build_object(
             'charges', count(*), 'out_of_sample', bool_and(r.use_oos),
             'clock', jsonb_build_object(
               'model', (SELECT m.j2 ->> 'model' FROM m), 'estimate_id', (SELECT m.j2 -> 'estimate_id' FROM m),
               'mean_log_error', round(avg(r.res2), 4), 'mean_abs_log_error', round(avg(abs(r.res2)), 4),
               'in_80pct_band', round((count(*) FILTER (WHERE r.sd2 > 0 AND abs(r.res2 / r.sd2) <= 1.2816))::numeric / count(*), 3)),
             'v1', jsonb_build_object(
               'estimate_id', (SELECT m.j1 -> 'estimate_id' FROM m),
               'mean_log_error', round(avg(r.res1), 4), 'mean_abs_log_error', round(avg(abs(r.res1)), 4),
               'in_80pct_band', round((count(*) FILTER (WHERE r.sd1 > 0 AND abs(r.res1 / r.sd1) <= 1.2816))::numeric / count(*), 3))) AS j
      FROM r GROUP BY r.kind
  ), cv AS (
    SELECT r.kind, x.cov, x.val, r.res2
      FROM r CROSS JOIN LATERAL (VALUES
        ('class', r.who ->> 'cls'), ('model', r.who ->> 'mdl'), ('vehicle', r.who ->> 'veh'), ('band', r.band),
        ('run', r.run::text), ('charger', r.stall_id::text),
        ('ambient_c', CASE WHEN r.ambient_temp_c IS NULL THEN 'unknown' ELSE (5 * floor(r.ambient_temp_c / 5))::int::text END),
        ('sim_hour', extract(hour FROM r.started_at)::int::text),
        ('to_full', CASE WHEN r.soc_end >= 99 THEN 'yes' ELSE 'no' END)) x(cov, val)
  ), g0 AS (
    SELECT cv.kind, cv.cov, cv.val, count(*) AS n FROM cv GROUP BY cv.kind, cv.cov, cv.val
  ), cv2 AS (
    SELECT cv.kind, cv.cov, CASE WHEN g0.n >= 5 THEN cv.val ELSE '(small groups)' END AS val, cv.res2
      FROM cv JOIN g0 USING (kind, cov, val)
  ), g AS (
    SELECT cv2.kind, cv2.cov, cv2.val, count(*) AS n, avg(cv2.res2) AS m FROM cv2 GROUP BY cv2.kind, cv2.cov, cv2.val
  ), t AS (
    SELECT cv2.kind, cv2.cov, count(*) AS n, avg(cv2.res2) AS m,
           sum(cv2.res2 * cv2.res2) - count(*) * avg(cv2.res2) * avg(cv2.res2) AS sst
      FROM cv2 GROUP BY cv2.kind, cv2.cov
  ), eta AS (
    SELECT t.kind, t.cov, t.n, count(g.val) AS groups, sum(g.n * (g.m - t.m) ^ 2) AS ssb, max(t.sst) AS sst
      FROM t JOIN g USING (kind, cov) GROUP BY t.kind, t.cov, t.n
  ), adj AS (
    SELECT eta.*, CASE WHEN eta.sst > 0 THEN eta.ssb / eta.sst END AS eta2,
           CASE WHEN eta.sst > 0 AND eta.n > eta.groups
                THEN 1 - (1 - eta.ssb / eta.sst) * (eta.n - 1) / (eta.n - eta.groups) END AS adj_eta2
      FROM eta
  ), cov AS (
    SELECT adj.kind, jsonb_agg(jsonb_build_object(
             'covariate', adj.cov, 'modelled', adj.cov IN ('class', 'model', 'vehicle', 'band'),
             'groups', adj.groups, 'eta2', round(adj.eta2, 4), 'adj_eta2', round(adj.adj_eta2, 4),
             'worst_groups', (SELECT jsonb_agg(jsonb_build_object('group', w.val, 'n', w.n, 'mean_log_error', round(w.m, 3))
                                               ORDER BY abs(w.m) DESC)
                                FROM (SELECT g.* FROM g WHERE g.kind = adj.kind AND g.cov = adj.cov
                                       ORDER BY abs(g.m) DESC, g.val LIMIT 3) w))
             ORDER BY adj.adj_eta2 DESC NULLS LAST, adj.cov) AS j
      FROM adj GROUP BY adj.kind
  )
  SELECT jsonb_build_object(
    'since', p_since,
    'by_kind', COALESCE((SELECT jsonb_object_agg(acc.kind, acc.j || jsonb_build_object('covariates', COALESCE(cov.j, '[]'::jsonb)))
                           FROM acc LEFT JOIN cov USING (kind)), '{}'::jsonb))
$fn$;

-- ══ (f) the assessment ═══════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_arbiter_self_assessment_v2(p_depot_id uuid, p_since timestamptz DEFAULT now() - interval '7 days')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0622: 0621's self-assessment, with the charge clock's calibration taken from ottoq_charge_clock_calibration in place
   of the window-biased forecast sums (0621's charge_clock_* areas are replaced), the clock's audit
   (ottoq_charge_clock_audit) and its findings, and the depot's outflow: how many cars per order left after it and came
   back inside its window, which the simulator does not model. Findings for a person (rule 10); read-only. */
DECLARE
  v_a     jsonb := public.ottoq_arbiter_self_assessment(p_depot_id, p_since);
  v_cal   jsonb := public.ottoq_charge_clock_calibration(p_depot_id, p_since);
  v_aud   jsonb := public.ottoq_charge_clock_audit(p_depot_id, p_since, NULL);
  v_out   jsonb;
  v_areas jsonb;
  x       record;
BEGIN
  SELECT COALESCE(jsonb_agg(a.value), '[]'::jsonb) INTO v_areas
    FROM jsonb_array_elements(COALESCE(v_a -> 'improvement_areas', '[]'::jsonb)) a
   WHERE a.value ->> 'area' NOT LIKE 'charge\_clock\_%';

  -- the clock's calibration on the check's own forecasts, by kind and by class
  FOR x IN SELECT c.key AS k, c.value AS j FROM jsonb_each(COALESCE(v_cal -> 'by_kind', '{}'::jsonb)) c
            WHERE (c.value ->> 'charges')::int >= 10
  LOOP
    IF abs(ln(COALESCE((x.j ->> 'factor_off_by')::numeric, 1))) > 0.15 OR COALESCE((x.j ->> 'z_sd')::numeric, 0) > 1.5
       OR COALESCE((x.j ->> 'in_80pct_band')::numeric, 1) < 0.6 THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'charge_clock_' || x.k, 'kind', 'calibration', 'weight', (x.j ->> 'charges')::int,
        'finding', 'The check''s charge forecasts on ' || x.k || ' were off by a factor of ' || (x.j ->> 'factor_off_by')
                   || ' (z mean ' || COALESCE(x.j ->> 'z_mean', '?') || ', sd ' || COALESCE(x.j ->> 'z_sd', '?') || '), '
                   || round(100 * COALESCE((x.j ->> 'in_80pct_band')::numeric, 0)) || '% inside an 80% band, '
                   || (x.j ->> 'overran') || ' of ' || (x.j ->> 'charges') || ' past their 90th percentile. One forecast '
                   || 'per charge; charges too late to finish inside the window left out.',
        'evidence', x.j);
    END IF;
  END LOOP;
  FOR x IN SELECT c.key AS k, c.value AS j FROM jsonb_each(COALESCE(v_cal -> 'by_class', '{}'::jsonb)) c
            WHERE (c.value ->> 'finished')::int >= 10 AND abs(COALESCE((c.value ->> 'z_mean')::numeric, 0)) > 0.5
  LOOP
    v_areas := v_areas || jsonb_build_object(
      'area', 'charge_clock_' || replace(x.k, '|', '_'), 'kind', 'calibration', 'weight', (x.j ->> 'charges')::int,
      'finding', 'Charges of class ' || split_part(x.k, '|', 2) || ' on ' || split_part(x.k, '|', 1) || ' ran '
                 || round(100 * ((x.j ->> 'factor_off_by')::numeric - 1)) || '% against the check''s clock (z mean '
                 || (x.j ->> 'z_mean') || '): the class level is stale or missing for them.',
      'evidence', x.j);
  END LOOP;

  -- the clock's audit: a covariate it does not model that explains what it leaves, or a modelled level gone stale
  FOR x IN SELECT k.key AS kind, c.value AS j, (k.value ->> 'charges')::int AS n, k.value AS acc
             FROM jsonb_each(COALESCE(v_aud -> 'by_kind', '{}'::jsonb)) k
             CROSS JOIN LATERAL jsonb_array_elements(COALESCE(k.value -> 'covariates', '[]'::jsonb)) c
            WHERE (k.value ->> 'charges')::int >= 30 AND COALESCE((c.value ->> 'adj_eta2')::numeric, 0) >= 0.05
  LOOP
    v_areas := v_areas || jsonb_build_object(
      'area', CASE WHEN (x.j ->> 'modelled')::boolean THEN 'charge_clock_stale_' ELSE 'charge_clock_misses_' END
              || (x.j ->> 'covariate') || '_' || x.kind,
      'kind', CASE WHEN (x.j ->> 'modelled')::boolean THEN 'calibration' ELSE 'capability_gap' END,
      'weight', round(x.n * (x.j ->> 'adj_eta2')::numeric),
      'finding', CASE WHEN (x.j ->> 'modelled')::boolean
        THEN 'The clock models ' || (x.j ->> 'covariate') || ', yet ' || (x.j ->> 'covariate') || ' still explains '
             || round(100 * (x.j ->> 'adj_eta2')::numeric) || '% of what it leaves on ' || x.kind
             || ': the level has gone stale since the fit (the nightly refit should absorb it; if it persists, the '
             || 'half-life is too long).'
        ELSE 'On ' || x.kind || ', ' || (x.j ->> 'covariate') || ' explains ' || round(100 * (x.j ->> 'adj_eta2')::numeric)
             || '% of what the clock leaves unexplained, and the clock does not model it. A level for it would let the '
             || 'clock see it.' END,
      'evidence', x.j || jsonb_build_object('charges', x.n, 'accuracy', x.acc - 'covariates'));
  END LOOP;
  FOR x IN SELECT k.key AS kind, k.value AS j FROM jsonb_each(COALESCE(v_aud -> 'by_kind', '{}'::jsonb)) k
            WHERE (k.value ->> 'charges')::int >= 30 AND (k.value ->> 'out_of_sample')::boolean
              AND (k.value #>> '{clock,mean_abs_log_error}')::numeric > (k.value #>> '{v1,mean_abs_log_error}')::numeric
  LOOP
    v_areas := v_areas || jsonb_build_object(
      'area', 'charge_clock_worse_than_v1_' || x.kind, 'kind', 'calibration', 'weight', (x.j ->> 'charges')::int,
      'finding', 'Out of sample on ' || x.kind || ', the clock''s mean absolute log error is '
                 || (x.j #>> '{clock,mean_abs_log_error}') || ' against 0619''s ' || (x.j #>> '{v1,mean_abs_log_error}')
                 || ': the levels are fitting noise or a level has gone stale.',
      'evidence', x.j - 'covariates');
  END LOOP;

  -- the outflow the simulator does not model: cars that leave after the order and come back inside its window
  SELECT jsonb_build_object(
           'orders', count(DISTINCT h.order_id),
           'appeared_returned', count(*),
           'per_order', round(count(*)::numeric / NULLIF(count(DISTINCT h.order_id), 0), 2),
           'left_after_the_order', count(*) FILTER (WHERE d.dispatched_at > h.sim_clock),
           'left_before', count(*) FILTER (WHERE d.dispatched_at <= h.sim_clock),
           'dispatch_not_found', count(*) FILTER (WHERE d.dispatched_at IS NULL),
           'mean_eta_min', round(avg((ap.value ->> 'eta')::numeric), 1),
           'by_trigger', (SELECT jsonb_object_agg(t.trig, t.n) FROM (
                            SELECT COALESCE(d2.return_trigger, 'unknown') AS trig, count(*) AS n
                              FROM ottoq_charge_order_hindsight h2
                              CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h2.realized -> 'appeared', '[]'::jsonb)) ap2
                              LEFT JOIN LATERAL (SELECT dd.return_trigger FROM ottoq_vehicle_dispatches dd
                                                  WHERE dd.sim_run_id = h2.sim_run_id AND dd.vehicle_id::text = ap2.value ->> 'id'
                                                    AND dd.actual_return_at > h2.sim_clock
                                                    AND dd.actual_return_at <= h2.sim_clock + make_interval(secs => h2.observed_min * 60)
                                                  ORDER BY dd.actual_return_at LIMIT 1) d2 ON true
                             WHERE h2.depot_id IS NOT DISTINCT FROM p_depot_id AND h2.graded_at >= p_since
                               AND ap2.value ->> 'how' = 'returned'
                             GROUP BY 1) t))
    INTO v_out
    FROM ottoq_charge_order_hindsight h
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h.realized -> 'appeared', '[]'::jsonb)) ap
    LEFT JOIN LATERAL (SELECT dd.dispatched_at FROM ottoq_vehicle_dispatches dd
                        WHERE dd.sim_run_id = h.sim_run_id AND dd.vehicle_id::text = ap.value ->> 'id'
                          AND dd.actual_return_at > h.sim_clock
                          AND dd.actual_return_at <= h.sim_clock + make_interval(secs => h.observed_min * 60)
                        ORDER BY dd.actual_return_at LIMIT 1) d ON true
   WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since AND ap.value ->> 'how' = 'returned';
  IF COALESCE((v_out ->> 'per_order')::numeric, 0) >= 1 THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'outflow_return_cycle', 'kind', 'capability_gap', 'weight', (v_out ->> 'appeared_returned')::int,
      'finding', (v_out ->> 'per_order') || ' cars per order came home inside the window that the check never saw coming; '
                 || (v_out ->> 'left_after_the_order') || ' of ' || (v_out ->> 'appeared_returned')
                 || ' had left after the order, a mean of ' || (v_out ->> 'mean_eta_min') || ' minutes before they came back. '
                 || 'The simulator has no departures: a car that finishes its charge leaves, works its battery down to the '
                 || 'reserve and rejoins the line inside the same window. Modelling the outflow (when ready cars leave) and '
                 || 'the return at the learned reserve would let the check see them; its objective would then have to count '
                 || 'a faster turnaround as a gain, not as more cars in the line.',
      'evidence', v_out);
  END IF;

  SELECT COALESCE(jsonb_agg(a.value ORDER BY (a.value ->> 'weight')::numeric DESC NULLS LAST, a.value ->> 'area'), '[]'::jsonb)
    INTO v_areas FROM jsonb_array_elements(v_areas) a;
  RETURN (v_a - 'improvement_areas') || jsonb_build_object(
    'v', 2, 'charge_clock', v_cal, 'clock_audit', v_aud, 'outflow', v_out, 'improvement_areas', v_areas);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_arbiter_assess(p_depot_id uuid, p_days integer DEFAULT 7)
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: the day's self-assessment of the check at a depot, written to ottoq_arbiter_assessments; NULL when nothing was
   graded in the window. A finding for a person, never a change (rule 10). 0622: the assessment is
   ottoq_arbiter_self_assessment_v2 (the clock's own calibration and audit, and the outflow). */
DECLARE v jsonb; v_since timestamptz := now() - make_interval(days => GREATEST(COALESCE(p_days, 7), 1)); v_id bigint;
BEGIN
  v := public.ottoq_arbiter_self_assessment_v2(p_depot_id, v_since);
  IF COALESCE((v ->> 'graded')::int, 0) = 0 THEN RETURN NULL; END IF;
  INSERT INTO ottoq_arbiter_assessments (depot_id, since, n_graded, n_decisions, assessment, improvement_areas, code_md5)
  VALUES (p_depot_id, v_since, (v ->> 'graded')::int, (v ->> 'decisions')::int, v - 'improvement_areas',
          COALESCE(v -> 'improvement_areas', '[]'::jsonb),
          md5(pg_get_functiondef('public.ottoq_arbiter_self_assessment(uuid,timestamptz)'::regprocedure)
              || pg_get_functiondef('public.ottoq_arbiter_self_assessment_v2(uuid,timestamptz)'::regprocedure)))
  RETURNING assessment_id INTO v_id;
  RETURN v_id;
END $fn$;

-- ══ grants ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock_who(uuid, text, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock_model(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock(jsonb, text, jsonb, numeric, numeric, numeric, numeric, numeric, jsonb)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock_remaining(jsonb, text, jsonb, numeric, numeric, numeric, numeric, numeric,
                                                              numeric, numeric, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock_run_evidence(jsonb, uuid, timestamptz) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock_calibration(uuid, timestamptz) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock_audit(uuid, timestamptz, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_arbiter_self_assessment_v2(uuid, timestamptz) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_charge_time_v2_params(uuid, timestamptz, interval, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_fit_charge_time_v2(uuid, timestamptz, interval, numeric, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_time_v2_params(uuid, timestamptz, interval, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_fit_charge_time_v2(uuid, timestamptz, interval, numeric, text) TO service_role;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE v_m jsonb; v_n int; v_bad int;
BEGIN
  -- on the depot's 0619 fit, the clock is 0619's minutes and 0620's spread
  v_m := public.ottoq_learned_estimate('11111111-1111-1111-1111-111111111111'::uuid, 'charge_time_v1');
  SELECT count(*),
         count(*) FILTER (WHERE (c.j ->> 'm')::numeric IS DISTINCT FROM
                                public.ottoq_charge_minutes_learned_with(v_m, g.kind, g.batt, g.s0, g.s1, g.kw, g.inlet)
                             OR (c.j ->> 'sd')::numeric IS DISTINCT FROM public.ottoq_charge_time_log_sd(v_m, g.kind, g.s0))
    INTO v_n, v_bad
    FROM (SELECT k.kind, b.batt, s0, s1, w.kw, i.inlet
            FROM (VALUES ('dcfc'), ('l2')) k(kind)
            CROSS JOIN (VALUES (60::numeric), (75), (85), (133)) b(batt)
            CROSS JOIN generate_series(0, 95, 5) s0
            CROSS JOIN (VALUES (80::numeric), (90), (100)) t(s1)
            CROSS JOIN (VALUES (19.2::numeric), (150), (350)) w(kw)
            CROSS JOIN (VALUES (100::numeric), (150), (250)) i(inlet)) g
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(v_m, g.kind, '{"cls": "x", "mdl": "x/y", "veh": "z"}'::jsonb,
                                                         g.batt, g.s0, g.s1, g.kw, g.inlet, NULL) AS j) c;
  IF v_n <> 4320 OR v_bad > 0 THEN
    RAISE EXCEPTION '0622 V1: on the v1 fit the clock is not 0619''s minutes and 0620''s spread: % of % differ', v_bad, v_n;
  END IF;
  RAISE NOTICE '0622 V1: on the depot''s v1 fit (estimate %) the clock returns 0619''s minutes and 0620''s spread on % cases',
    v_m -> 'estimate_id', v_n;
END $v1$;

DO $v2$
DECLARE
  c_run   constant uuid := 'd9d49732-cf28-42c3-aac9-9c3f606a2c92';
  v_start timestamptz;
  v_p     jsonb;
  v_m2    jsonb;
  v_m1    jsonb;
  r       record;
  v_t0    timestamptz := clock_timestamp();
BEGIN
  SELECT started_at INTO v_start FROM ottoq_sim_runs WHERE sim_run_id = c_run AND status = 'completed';
  IF v_start IS NULL OR NOT EXISTS (SELECT 1 FROM ottoq_charge_duration_ledger WHERE sim_run_id = c_run) THEN
    RAISE NOTICE '0622 V2/V3: run d9d49732 is not here; the gate and the session level are executed by the tests';
    RETURN;
  END IF;
  -- the clock that would have been fitted the moment the run began, and the v1 fit the run actually used
  v_p := public.ottoq_charge_time_v2_params('11111111-1111-1111-1111-111111111111'::uuid, v_start, interval '21 days', 3);
  v_m2 := jsonb_build_object('params', v_p);
  SELECT jsonb_build_object('params', e.params, 'estimate_id', e.estimate_id) INTO v_m1
    FROM ottoq_learned_estimates e
   WHERE e.depot_id = '11111111-1111-1111-1111-111111111111' AND e.model = 'charge_time_v1' AND e.fitted_at <= v_start
   ORDER BY e.estimate_id DESC LIMIT 1;
  FOR r IN
    WITH c AS (
      SELECT l.charger_type AS kind, ln((l.duration_min / est.m)::numeric) AS lr, wh.who, l.started_at,
             public.ottoq_charge_clock(v_m1, l.charger_type, wh.who, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                       l.vehicle_kw, NULL) AS c1,
             public.ottoq_charge_clock(v_m2, l.charger_type, wh.who, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                       l.vehicle_kw,
                                       public.ottoq_charge_clock_run_evidence(v_m2, c_run, l.started_at) -> l.charger_type) AS c2
        FROM ottoq_charge_duration_ledger l
        JOIN vehicles v ON v.id = l.vehicle_id
        CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
        CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                        l.vehicle_kw) AS m) est
       WHERE l.sim_run_id = c_run AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2')
         AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0
    )
    SELECT c.kind, count(*) AS n,
           round(avg(c.lr - (c.c1 ->> 'f')::numeric), 3) AS bias1, round(avg(abs(c.lr - (c.c1 ->> 'f')::numeric)), 3) AS mae1,
           round(avg(c.lr - (c.c2 ->> 'f')::numeric), 3) AS bias2, round(avg(abs(c.lr - (c.c2 ->> 'f')::numeric)), 3) AS mae2,
           round((count(*) FILTER (WHERE abs(c.lr - (c.c1 ->> 'f')::numeric) <= 1.2816 * (c.c1 ->> 'sd')::numeric))::numeric / count(*), 3) AS band1,
           round((count(*) FILTER (WHERE abs(c.lr - (c.c2 ->> 'f')::numeric) <= 1.2816 * (c.c2 ->> 'sd')::numeric))::numeric / count(*), 3) AS band2
      FROM c GROUP BY c.kind ORDER BY c.kind
  LOOP
    RAISE NOTICE '0622 V2 % (% charges of d9d49732, out of sample): v1 bias %, mean abs log error %, % in its 80%% band; v2 bias %, mean abs log error %, % in its band',
      r.kind, r.n, r.bias1, r.mae1, r.band1, r.bias2, r.mae2, r.band2;
    IF r.kind = 'dcfc' AND (r.mae2 >= r.mae1 OR r.band2 < 0.6) THEN
      RAISE EXCEPTION '0622 V2: on the next run''s fast charges the new clock is not better than 0619''s (mean abs log error % against %, % in its band): not applied',
        r.mae2, r.mae1, r.band2;
    END IF;
  END LOOP;
  RAISE NOTICE '0622 V2: the gate passed (% ms)', round(extract(epoch FROM clock_timestamp() - v_t0) * 1000);

  -- V3, on the same fit and run: what is left of a charge at half way, with the charge's own progress and without
  IF v_m2 #> '{params,session,dcfc}' IS NULL THEN
    RAISE EXCEPTION '0622 V3: the fit has no session level for fast chargers';
  END IF;
  FOR r IN
    WITH s AS (
      SELECT l.*, wh.who FROM ottoq_charge_duration_ledger l JOIN vehicles v ON v.id = l.vehicle_id
        CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
       WHERE l.sim_run_id = c_run AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2')
         AND l.soc_end - l.soc_start >= 8
    ), mid AS (
      SELECT s.*, m.t_at, m.soc_at
        FROM s CROSS JOIN LATERAL (
          SELECT mm.sim_clock_at AS t_at, (mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric AS soc_at
            FROM ottoq_ocpp_messages mm
           WHERE mm.ocpp_session_id = s.session_id AND mm.message_type = 'MeterValues'
             AND (mm.payload -> 'sampledValue' -> 1 ->> 'measurand') = 'SoC'
             AND (mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric >= (s.soc_start + s.soc_end) / 2.0
           ORDER BY mm.message_at LIMIT 1) m
    ), p AS (
      SELECT mid.charger_type AS kind, extract(epoch FROM (mid.ended_at - mid.t_at)) / 60.0 AS act,
             (public.ottoq_charge_clock_remaining(v_m2, mid.charger_type, mid.who, mid.battery_kwh, mid.soc_start, mid.soc_at,
                mid.soc_end, mid.charger_kw, mid.vehicle_kw, extract(epoch FROM (mid.t_at - mid.started_at)) / 60.0, NULL)) AS with_s,
             (public.ottoq_charge_clock(v_m2, mid.charger_type, mid.who, mid.battery_kwh, mid.soc_at, mid.soc_end, mid.charger_kw,
                mid.vehicle_kw, NULL)) AS without_s
        FROM mid WHERE mid.ended_at > mid.t_at AND mid.soc_at < mid.soc_end
    )
    SELECT p.kind, count(*) AS n, count(*) FILTER (WHERE (p.with_s ->> 'session')::boolean) AS used,
           round(avg(abs(ln(p.act / NULLIF((p.with_s ->> 'm')::numeric, 0)))) FILTER (WHERE p.act > 0 AND (p.with_s ->> 'm')::numeric > 0), 3) AS mae_with,
           round(avg(abs(ln(p.act / NULLIF((p.without_s ->> 'm')::numeric, 0)))) FILTER (WHERE p.act > 0 AND (p.without_s ->> 'm')::numeric > 0), 3) AS mae_without
      FROM p GROUP BY p.kind ORDER BY p.kind
  LOOP
    RAISE NOTICE '0622 V3 % (% charges, the session level used on %): what is left at half way, mean abs log error % with the charge''s own progress, % without',
      r.kind, r.n, r.used, r.mae_with, r.mae_without;
    IF r.kind = 'dcfc' AND r.mae_with > r.mae_without THEN
      RAISE EXCEPTION '0622 V3: the session level makes the fast-charge remaining time worse (% against %)', r.mae_with, r.mae_without;
    END IF;
  END LOOP;
END $v2$;

-- the first fit, at apply, and the nightly one
SELECT public.ottoq_fit_charge_time_v2('11111111-1111-1111-1111-111111111111'::uuid, NULL, interval '21 days', 3,
                                       '0622: the first fit, at apply');
SELECT cron.schedule('ottoq-learn-charge-clock-nightly', '22 11 * * *',
  $cron$SELECT public.ottoq_fit_charge_time_v2('11111111-1111-1111-1111-111111111111'::uuid, NULL, interval '21 days', 3, 'nightly');$cron$);

DO $v4$
DECLARE v_m jsonb; r record; v_state jsonb; v_board jsonb; t0 timestamptz; v_ms_state numeric; v_ms_board numeric;
BEGIN
  v_m := public.ottoq_charge_clock_model('11111111-1111-1111-1111-111111111111'::uuid);
  IF v_m ->> 'model' = 'charge_time_v2' THEN
    RAISE NOTICE '0622 V4: the depot''s clock is charge_time_v2 estimate % (% charges, % runs): class cells %, model cells %, cars %, session kinds %',
      v_m -> 'estimate_id', v_m -> 'n_evidence', v_m -> 'n_runs',
      (SELECT count(*) FROM jsonb_object_keys(v_m #> '{params,class_cells}')),
      (SELECT count(*) FROM jsonb_object_keys(v_m #> '{params,model_cells}')),
      (SELECT count(*) FROM jsonb_object_keys(v_m #> '{params,vehicle_cells}')),
      (SELECT count(*) FROM jsonb_object_keys(v_m #> '{params,session}'));
  ELSE
    RAISE NOTICE '0622 V4: the first fit is not usable (too few charges of a kind here); the depot keeps its % clock',
      COALESCE(v_m ->> 'model', 'base');
  END IF;
  SELECT x.sim_run_id, x.depot_id, x.sim_clock_current INTO r
    FROM ottoq_sim_runs x WHERE x.status = 'running' AND x.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY x.started_at DESC LIMIT 1;
  IF r.sim_run_id IS NULL THEN
    RAISE NOTICE '0622 V4: no twin run is running; the readers are executed by the tests';
    RETURN;
  END IF;
  t0 := clock_timestamp();
  v_state := public.ottoq_charge_line_state(r.sim_run_id, r.depot_id, r.sim_clock_current);
  v_ms_state := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  t0 := clock_timestamp();
  v_board := public.ottoq_agent_charge_queue_board(r.sim_run_id, r.depot_id, r.sim_clock_current);
  v_ms_board := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_state -> 'cars') c WHERE c.value ->> 'cls' IS NULL OR c.value ->> 'lv' IS NULL) THEN
    RAISE EXCEPTION '0622 V4: a car in the state carries no class or clock level';
  END IF;
  RAISE NOTICE '0622 V4 on running run %: state % ms (% cars, % coming home, % chargers; levels %), board % ms (clock %, classes %)',
    r.sim_run_id, v_ms_state, jsonb_array_length(v_state -> 'cars'), jsonb_array_length(v_state -> 'inbound'),
    jsonb_array_length(v_state -> 'chargers'),
    (SELECT jsonb_object_agg(z.lv, z.n) FROM (SELECT c.value ->> 'lv' AS lv, count(*) AS n
                                              FROM jsonb_array_elements(v_state -> 'cars') c GROUP BY 1) z),
    v_ms_board, v_board #> '{check,charge_clock,model}', v_board #> '{check,charge_clock,class_vs_typical}';
END $v4$;

DO $v5$
DECLARE r record; n int := 0; v_now jsonb;
BEGIN
  FOR r IN
    SELECT h.order_id, h.window_min, h.realized
      FROM ottoq_charge_order_hindsight h JOIN ottoq_sim_runs x ON x.sim_run_id = h.sim_run_id
     WHERE h.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND h.observed_min = h.window_min
       AND x.status = 'completed' AND h.graded_at < x.ended_at
     ORDER BY h.order_id DESC LIMIT 5
  LOOP
    v_now := public.ottoq_charge_order_realized(r.order_id, r.window_min);
    IF (v_now - 'run_status') IS DISTINCT FROM (r.realized - 'run_status') THEN
      RAISE EXCEPTION '0622 V5: order % no longer reads as it was graded: %', r.order_id,
        (SELECT jsonb_object_agg(k.key, jsonb_build_array(r.realized -> k.key, v_now -> k.key))
           FROM jsonb_object_keys(v_now) k(key) WHERE (v_now -> k.key) IS DISTINCT FROM (r.realized -> k.key));
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE '0622 V5: % graded orders of d9d49732 read exactly as they were graded under this file''s realized reader', n;
END $v5$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0622_the_kernel_learns_each_cars_charge_clock_from_its_own_charges', false, false,
  'A charge clock learned in levels from the depot''s own charges (pooled band, class, make and model, class and band, '
  'car, run, car in run, and the charge in progress), recency-weighted and shrunk by its evidence, read by the agent''s '
  'charge-order check, board and grader through one function; on a v1 model every reader is unchanged (V1, V5). A '
  'calibration without the window''s survivorship, an audit of the clock''s residuals by covariate, and the outflow '
  'finding join the nightly assessment. FALSE/FALSE: the tick path is untouched and orders exist only on operator_demo '
  'runs (0615).',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
