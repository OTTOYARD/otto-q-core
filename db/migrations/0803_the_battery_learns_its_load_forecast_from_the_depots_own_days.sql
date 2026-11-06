-- migration-version: PENDING
-- migration-name:    the_battery_learns_its_load_forecast_from_the_depots_own_days
--
-- 0803  **The battery learns its load forecast from the depot's own days.** (B1, the production battery planner's first
--        piece; G524)
--
-- ══ §0 WHY NOW ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-11-05: "let's not sleep on the agent/AI with BESS usage angle (Forward planning/analyzing, etc.)"; and
--   2026-11-06 (read by 13:20 UTC): "Yes, just keep building", to a report whose asks included the go-ahead for the
--   production battery planner. This file is that planner's first piece: the forecast it plans on, learned each night
--   from what the depot drew. Rule 10 lets production OTTO-Q update its estimates overnight from the day's real data and
--   never its rules: a forecast model refit each night is an estimate.
--
-- ══ §1 WHAT THE RESEARCH LAB FOUND (lab/research/p2_capacity/planner_36h_lab_2026-11-06.md, 2026-11-06) ═══════════════
--
--   On six 36-hour lab days billed from 6 PM (the battery in steady state), a planner that budgets the battery over the
--   whole horizon (a linear program, battery_lp.py) fed a learned forecast plus its 80th-percentile out-of-sample miss
--   saved $226 a day on the day plan as it runs, on all six seeds ($164-300), and its billed half hour stood 252-456 kW
--   under the day plan's. The day plan's own forecast of the EV load, max(known, queue, last hour), is high by 1,062 kW on
--   the next half hour out of sample (its known term charges every car coming home from its arrival whether or not a post
--   is free, G524), and the learned forecast's error there is 88 kW. A truer forecast inside the day plan moved nothing
--   (-$1.23 a day): the gain is the planner's, and the planner needs the forecast. Production's optimizer is that planner
--   (ottoq-intelligence app/optimizers/energy_mpc.py, through the energy MPC bridge, followed under energy_mpc_follow);
--   what production does not have is the forecast. This file builds it, in the database, from the depot's own days.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_bess_forecast_log, evidence (no foreign key to runs, 0340's pattern; append-only; registered, so 0748
--       guards it against TRUNCATE): one row a tick while the new dial bess_forecast_learning is on (catalogued 0..1,
--       default 0, a person's dial): the day plan's forecast inputs for the next 8 hours (the cars on a charger now, its
--       known term, its queue, the building, the sun, and the EV rule it decided on) and the site snapshot it read (EV,
--       building, solar, grid), with the run's origin (run_by).
--   (b) One anchored insertion in public.ottoq_energy_orchestrate, before its last RETURN: with the dial on, the tick's
--       row is written from the plan the orchestrator just solved (no second solve), inside its own block, so a failure is
--       a warning and never a stopped tick. With the dial off it reads one dial and does nothing else.
--   (c) public.ottoq_forecast_ev_on_charger_kw: the first of ottoq_forecast_ev_known_kw's two loops, verbatim (the cars on
--       a charger now, held at their rate until done), which the learned forecast reads apart from the second.
--   (d) public.ottoq_bess_forecast_models, append-only, depot-scoped (like ottoq_charge_clock_fits), and
--       public.ottoq_bess_forecast_refit(depot, quantile 0.8, lambda 10, window 28 days): from the depot's logged ticks of
--       operator demo and production runs (harness runs left out), for every tick and each half hour h ahead (0-7), a
--       ridge regression on the research lab's features predicting the mean EV charging over that half hour (at least 6
--       snapshots), standardised, the intercept unpenalised; its upper band is the quantile of every fold's misses when
--       the fold (a run's local day) was left out of the fit; and the depot's pre-battery load and EV load by half hour of
--       the local day (mean and the quantile across days), for the hours beyond. Usable with 3 folds and 200 examples at
--       every h ahead. Helpers: public.ottoq_linsolve (Gaussian elimination, partial pivoting) and
--       public.ottoq_ridge_from_stats (the fit from raw sums, so a fold's fit is the total less the fold).
--   (e) public.ottoq_bess_forecast_model(depot) (the latest usable fit) and public.ottoq_bess_learned_forecast(run, depot,
--       clock): the next 8 half hours' EV (mean, and mean plus band) and pre-battery load from the day plan's own terms,
--       and the 48 half hours from now by the depot's day.
--   (f) The nightly refit, cron 'ottoq-learn-bess-forecast-nightly' at 26 11 * * * UTC (5:26 AM CST, 6:26 AM CDT),
--       beside the other nightly learners (11:20, 11:22, 11:24 UTC). No examples, no row.
--   Nothing reads the forecast yet: the day plan decides as before. The next pieces put it in front of the planner.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; the orchestrator is the body production carries (prosrc md5 8f425cda, 0797's)
--   or the one 0799 leaves (db31a8c6); none of this file's objects, dial or cron job exists. The pre-image to
--   ottoq_schema_snapshots as '0803_pre'. The anchor matches once, read with bare newlines.
--   V1 the orchestrator less its insertion is its pre-image. V2 the solver and the fit on known answers: a 3 x 3 system,
--   and an exact linear target recovered with lambda 0. V3 on synthetic ticks rolled back with their rows (a run that is
--   not one, three local days of a known daily wave): the refit writes a usable model whose out-of-sample miss is small
--   against the wave, and the forecast reader returns 8 half hours and 48 beyond. V4 the patched orchestrator is byte for
--   byte the body the research lab ran, on either base.
--   In the research lab (2026-11-06, between 13:47 and 13:52 UTC): on the 2,592 ticks of the six 36-hour base days the
--   refit, each seed held out, wrote the models forecast_learn.py saved (16,200 examples each; weights within 4e-11, band
--   offsets within 5e-12 kW), and the reader gave battery_lp.py's forecast within 0.05 kW at six clocks. This file ran on
--   copies of the lab template with the orchestrator as production has it and as 0799 leaves it (ottoq_lab_0803 and
--   0803b), every check passing; and a 36-hour lab day with the dial on (seed 424242, 13:57-14:06 UTC) wrote one row a
--   tick (432), every car-facing line of its scorecard and all 864 energy commands the base day's.
--   The tick reads the site snapshot before its own: the site-energy step runs after the orchestrator, so each row's
--   snapshot_at is the previous tick's (the first row has none) and the refit's targets read every snapshot but the last.
--   Its forecast terms are the orchestrator's (mid-tick), not the research lab's audit (after the tick): on that day they
--   differed by a median 81 kW over the 8 half hours on the cars on a charger. The model learns and is read on the same
--   terms, so the forecast is consistent with itself; the lab's planner study read the audit's.
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: with the dial off the orchestrator decides exactly as before (one
--   dial read more); with it on, it writes evidence rows no atom reads and calls only STABLE reads (the day plan when the
--   orchestrator did not solve one, and the charge-rate function the known term already calls).
--
-- ROLLBACK: SELECT cron.unschedule('ottoq-learn-bess-forecast-nightly');
--   EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0803_pre';
--   DROP FUNCTION public.ottoq_bess_learned_forecast(uuid,uuid,timestamptz,jsonb,bigint), public.ottoq_bess_forecast_model(uuid),
--     public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[]),
--     public.ottoq_ridge_from_stats(double precision,double precision,double precision[],double precision[],double precision[],double precision),
--     public.ottoq_linsolve(double precision[],double precision[]),
--     public.ottoq_bess_forecast_log_tick(uuid,uuid,timestamptz,bigint,jsonb),
--     public.ottoq_forecast_ev_on_charger_kw(uuid,uuid,timestamptz,integer,numeric);
--   the two tables are evidence: keep them (0749), or drop them under ottoq.evidence_truncate_unlock with a reason;
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'bess_forecast_learning';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0803_the_battery_learns_its_load_forecast_from_the_depots_own_days'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0803 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0803_the_battery_learns_its_load_forecast_from_the_depots_own_days') THEN
    RAISE EXCEPTION '0803 P1: already applied';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'))
     NOT IN ('8f425cda7b4b8486b8b44594b9bfe11f', 'db31a8c652ef44f147926651d0e48557') THEN
    RAISE EXCEPTION '0803 P1: public.ottoq_energy_orchestrate is neither the body 0797 left (8f425cda) nor 0799''s (db31a8c6)';
  END IF;
  IF to_regclass('public.ottoq_bess_forecast_log') IS NOT NULL OR to_regclass('public.ottoq_bess_forecast_models') IS NOT NULL
     OR to_regproc('public.ottoq_bess_forecast_refit') IS NOT NULL OR to_regproc('public.ottoq_bess_learned_forecast') IS NOT NULL
     OR to_regproc('public.ottoq_forecast_ev_on_charger_kw') IS NOT NULL OR to_regproc('public.ottoq_linsolve') IS NOT NULL THEN
    RAISE EXCEPTION '0803 P1: an object of this file already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bess_forecast_learning') THEN
    RAISE EXCEPTION '0803 P1: the dial bess_forecast_learning is already catalogued';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-learn-bess-forecast-nightly') THEN
    RAISE EXCEPTION '0803 P1: the cron job ottoq-learn-bess-forecast-nightly already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0803_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure;

-- ══ (a) the log ═════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_bess_forecast_log (
  log_id        bigserial PRIMARY KEY,
  depot_id      uuid NOT NULL,
  sim_run_id    uuid,
  run_by        text,
  data_source   text,
  tick_seq      bigint,
  sim_clock     timestamptz NOT NULL,
  snapshot_at   timestamptz,
  ev_drawn_kw   numeric,
  site_base_kw  numeric,
  site_solar_kw numeric,
  grid_kw       numeric,
  ev_persist_kw numeric,
  on_charger_kw numeric[],
  known_kw      numeric[],
  queue_kw      numeric[],
  base_kw       numeric[],
  solar_kw      numeric[],
  rule_ev_kw    numeric[],
  logged_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_bess_forecast_log_once UNIQUE (depot_id, sim_run_id, sim_clock)
);
CREATE INDEX ottoq_bess_forecast_log_depot_logged ON public.ottoq_bess_forecast_log (depot_id, logged_at);
COMMENT ON TABLE public.ottoq_bess_forecast_log IS
  '0803: the battery forecast''s evidence, one row a tick while bess_forecast_learning is on: the day plan''s forecast '
  'inputs for the next 8 hours (the cars on a charger now, the known term, the queue, the building, the sun, and the EV '
  'rule it decided on, each per half hour) and the site snapshot it read (EV, building, solar, grid), with the run''s '
  'origin. The nightly refit (ottoq_bess_forecast_refit) learns from it what the depot then drew. Evidence, not engine: '
  'it must outlive its run, so it carries no foreign key to ottoq_sim_runs (0340''s pattern). Append-only.';

CREATE TABLE public.ottoq_bess_forecast_models (
  model_id      bigserial PRIMARY KEY,
  depot_id      uuid NOT NULL,
  fitted_at     timestamptz NOT NULL DEFAULT now(),
  note          text,
  usable        boolean NOT NULL,
  quantile      numeric NOT NULL,
  lam           numeric NOT NULL,
  fold_by       text NOT NULL,
  window_from   timestamptz,
  runs          uuid[] NOT NULL,
  n_folds       int NOT NULL,
  n_examples    int NOT NULL,
  features      text[] NOT NULL,
  per_half_hour jsonb NOT NULL,
  profile       jsonb,
  diagnostics   jsonb
);
CREATE INDEX ottoq_bess_forecast_models_depot ON public.ottoq_bess_forecast_models (depot_id, model_id DESC);
COMMENT ON TABLE public.ottoq_bess_forecast_models IS
  '0803: the battery''s learned load forecast, one row per refit (ottoq_bess_forecast_refit, nightly): for each half hour '
  'ahead (0-7) a ridge on the day plan''s own forecast terms and the hour of the day predicting the EV charging the depot '
  'then drew (mu, sd, w: standardised features, the intercept first), with the given quantile of its out-of-sample misses '
  '(each fold''s misses when it was left out of the fit) as offset_kw, its upper band, and cv the out-of-sample grades '
  'beside the day plan''s rule; and profile, the depot''s pre-battery and EV load by half hour of the local day (b 0-47, '
  'the half hour ending at (b + 1) x 30 minutes), for the hours beyond. An estimate refit from the depot''s own days, '
  'never a rule or a setting (rule 10). Depot-scoped, no run column, append-only, like ottoq_charge_clock_fits.';

CREATE OR REPLACE FUNCTION public.ottoq_bess_forecast_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF COALESCE(current_setting('ottoq.bess_forecast_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION '% is append-only evidence: % refused (0803). Set ottoq.bess_forecast_unlock = on in the transaction '
                  'to override, and say why in a migration.', TG_TABLE_NAME, TG_OP USING ERRCODE = '42501';
END;
$function$;
CREATE TRIGGER ottoq_bess_forecast_log_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_bess_forecast_log
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_bess_forecast_append_only();
CREATE TRIGGER ottoq_bess_forecast_models_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_bess_forecast_models
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_bess_forecast_append_only();

ALTER TABLE public.ottoq_bess_forecast_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_bess_forecast_models ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ottoq_bess_forecast_log, public.ottoq_bess_forecast_models FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_bess_forecast_log, public.ottoq_bess_forecast_models TO anon, authenticated, service_role;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_bess_forecast_log', 'sim_run_id', 'evidence',
        '0803: the battery forecast''s evidence, one row a tick (the day plan''s forecast inputs and the site snapshot it '
        'read). Evidence, not engine: the nightly refit learns from the depot''s past days, so a row must outlive its run. '
        'NO foreign key, for 0340/0364''s reason.');
SELECT public.ottoq_guard_evidence_table('public.ottoq_bess_forecast_models'::regclass);

-- ══ (c) the cars on a charger now ═══════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_forecast_ev_on_charger_kw(p_sim_run_id uuid, p_depot_id uuid,
    p_sim_clock timestamp with time zone, p_horizon_ticks integer DEFAULT 16, p_tick_min numeric DEFAULT 30)
 RETURNS numeric[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0803: the first of ottoq_forecast_ev_known_kw's two loops, verbatim (the currently-active charging sessions, each held
   at its rate until done), without the second (the cars coming home, each charged from its arrival whether or not a post
   is free). The learned forecast reads the two apart: graded on the research lab's days the second loop is what puts the
   day plan's next half hour 1,000 kW and more high (G524). p_depot_id is unused, as it is in the parent. */
DECLARE
  v_load numeric[]; h int; r RECORD;
  v_rate numeric; v_dur_min numeric;
BEGIN
  v_load := array_fill(0::numeric, ARRAY[p_horizon_ticks]);
  FOR r IN
    SELECT ottoq_sim_compute_charge_rate(
             p_soc_pct := v.current_soc, p_battery_temp_c := COALESCE(s.ambient_temp_c,22)+5,
             p_ambient_temp_c := COALESCE(s.ambient_temp_c,22), p_charger_max_kw := ch.max_kw,
             p_vehicle_max_kw := v.inlet_max_kw, p_battery_capacity_kwh := v.battery_capacity_kwh,
             p_battery_soh_pct := 95, p_noise_seed := 1, p_noise_salt := s.vehicle_id::text) AS rate,
           GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-v.current_soc)/100.0*COALESCE(v.battery_capacity_kwh,75)) AS kwh
    FROM ocpp_sessions s JOIN stalls st ON st.id=s.stall_id
    JOIN ottoq_ocpp_chargers ch ON ch.charger_id=st.ocpp_charger_id
    JOIN vehicles v ON v.id=s.vehicle_id
    WHERE s.status='active' AND s.sim_run_id=p_sim_run_id
    ORDER BY st.id   /* 0054: stall identity, never per-run session UUIDs */
  LOOP
    v_rate := GREATEST(r.rate, 1); v_dur_min := r.kwh / v_rate * 60.0;
    FOR h IN 1..p_horizon_ticks LOOP
      IF (h-1)*p_tick_min < v_dur_min THEN v_load[h] := v_load[h] + v_rate; END IF;
    END LOOP;
  END LOOP;
  RETURN v_load;
END;
$function$;

-- ══ (a, b) one tick's row ═══════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_bess_forecast_log_tick(p_sim_run_id uuid, p_depot_id uuid,
    p_sim_clock timestamp with time zone, p_tick_seq bigint DEFAULT NULL, p_day_plan jsonb DEFAULT NULL)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0803: write this tick's row of the battery forecast's evidence. p_day_plan is the plan the orchestrator just solved
   (its 'forecast' arrays are what the battery decided on); without one the plan is solved here (STABLE, a read). Returns
   the row's id, or NULL when there is no plan (no battery) or the tick is already logged. Changes no decision. */
DECLARE
  c_n CONSTANT int := 16;   -- 8 hours of half hours: the day plan's shortest horizon
  v_plan jsonb := p_day_plan; v_f jsonb; s record; v_act numeric[]; v_id bigint; v_run_by text;
BEGIN
  IF v_plan IS NULL OR NOT COALESCE((v_plan->>'ok')::boolean, false) OR v_plan->'forecast' IS NULL THEN
    v_plan := public.ottoq_bess_day_plan(p_sim_run_id, p_depot_id, p_sim_clock, NULL);
  END IF;
  IF NOT COALESCE((v_plan->>'ok')::boolean, false) THEN
    RETURN NULL;
  END IF;
  v_f := v_plan->'forecast';
  SELECT run_by INTO v_run_by FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  SELECT e.timestamp AS at, COALESCE(e.total_ev_charging_kw,0) AS ev,
         COALESCE(e.building_load_kw,0) + COALESCE(e.lighting_load_kw,0) AS base,
         COALESCE(e.solar_generation_kw,0) AS solar,
         COALESCE(e.grid_import_kw,0) - COALESCE(e.grid_export_kw,0) AS grid, e.data_source
    INTO s
    FROM site_energy_snapshots e
   WHERE e.depot_id = p_depot_id AND e.sim_run_id = p_sim_run_id AND e.timestamp <= p_sim_clock
   ORDER BY e.timestamp DESC LIMIT 1;
  v_act := public.ottoq_forecast_ev_on_charger_kw(p_sim_run_id, p_depot_id, p_sim_clock, c_n, 30);
  INSERT INTO public.ottoq_bess_forecast_log (depot_id, sim_run_id, run_by, data_source, tick_seq, sim_clock, snapshot_at,
         ev_drawn_kw, site_base_kw, site_solar_kw, grid_kw, ev_persist_kw, on_charger_kw, known_kw, queue_kw, base_kw,
         solar_kw, rule_ev_kw)
  VALUES (p_depot_id, p_sim_run_id, v_run_by, s.data_source, p_tick_seq, p_sim_clock, s.at, s.ev, s.base, s.solar, s.grid,
          (v_plan->>'ev_persist_kw')::numeric,
          ARRAY(SELECT round(x, 0) FROM unnest(v_act) WITH ORDINALITY u(x, o) ORDER BY o),
          ARRAY(SELECT x::numeric FROM jsonb_array_elements_text(v_f->'ev_known_kw') WITH ORDINALITY u(x, o) WHERE o <= c_n ORDER BY o),
          ARRAY(SELECT x::numeric FROM jsonb_array_elements_text(v_f->'ev_queue_kw') WITH ORDINALITY u(x, o) WHERE o <= c_n ORDER BY o),
          ARRAY(SELECT x::numeric FROM jsonb_array_elements_text(v_f->'base_kw')     WITH ORDINALITY u(x, o) WHERE o <= c_n ORDER BY o),
          ARRAY(SELECT x::numeric FROM jsonb_array_elements_text(v_f->'solar_kw')    WITH ORDINALITY u(x, o) WHERE o <= c_n ORDER BY o),
          ARRAY(SELECT x::numeric FROM jsonb_array_elements_text(v_f->'ev_kw')       WITH ORDINALITY u(x, o) WHERE o <= c_n ORDER BY o))
  ON CONFLICT ON CONSTRAINT ottoq_bess_forecast_log_once DO NOTHING
  RETURNING log_id INTO v_id;
  RETURN v_id;
END;
$function$;

-- ══ (d) the fit ═════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_linsolve(p_a double precision[], p_b double precision[])
 RETURNS double precision[]
 LANGUAGE plpgsql
 IMMUTABLE STRICT
AS $function$
/* 0803: A x = b for a small dense A (n x n, row-major), by Gaussian elimination with partial pivoting: the ridge's
   normal equations (10 x 10). NULL when A is singular to working precision. */
DECLARE
  n int := array_length(p_b, 1); a double precision[] := p_a; b double precision[] := p_b;
  x double precision[]; i int; j int; k int; p int; m double precision; t double precision; s double precision;
BEGIN
  IF array_length(a, 1) <> n * n THEN RAISE EXCEPTION 'ottoq_linsolve: A is not % x %', n, n; END IF;
  FOR k IN 1..n LOOP
    p := k;
    FOR i IN k + 1..n LOOP
      IF abs(a[(i - 1) * n + k]) > abs(a[(p - 1) * n + k]) THEN p := i; END IF;
    END LOOP;
    IF abs(a[(p - 1) * n + k]) < 1e-300 THEN RETURN NULL; END IF;
    IF p <> k THEN
      FOR j IN 1..n LOOP
        t := a[(k - 1) * n + j]; a[(k - 1) * n + j] := a[(p - 1) * n + j]; a[(p - 1) * n + j] := t;
      END LOOP;
      t := b[k]; b[k] := b[p]; b[p] := t;
    END IF;
    FOR i IN k + 1..n LOOP
      m := a[(i - 1) * n + k] / a[(k - 1) * n + k];
      IF m <> 0 THEN
        FOR j IN k..n LOOP
          a[(i - 1) * n + j] := a[(i - 1) * n + j] - m * a[(k - 1) * n + j];
        END LOOP;
        b[i] := b[i] - m * b[k];
      END IF;
    END LOOP;
  END LOOP;
  x := array_fill(0::double precision, ARRAY[n]);
  FOR i IN REVERSE n..1 LOOP
    s := b[i];
    FOR j IN i + 1..n LOOP
      s := s - a[(i - 1) * n + j] * x[j];
    END LOOP;
    x[i] := s / a[(i - 1) * n + i];
  END LOOP;
  RETURN x;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_ridge_from_stats(p_n double precision, p_sy double precision,
    p_sx double precision[], p_sxy double precision[], p_sxx double precision[], p_lam double precision,
    OUT mu double precision[], OUT sd double precision[], OUT w double precision[])
 LANGUAGE plpgsql
 IMMUTABLE STRICT
AS $function$
/* 0803: the research lab's ridge (lab/research/p2_capacity/forecast_learn.py) from raw sums: with z = (x - mu) / sd (sd
   the population deviation plus 1e-9), solve (Z'Z + lam I') w = Z'y, I' the identity less the intercept's entry. Z'Z
   and Z'y come from n, sum x, sum xy and sum x x' (row-major), so a fold's fit is the total less the fold. */
DECLARE
  k int := array_length(p_sx, 1); d int := k + 1; i int; j int;
  a double precision[]; b double precision[];
BEGIN
  mu := array_fill(0::double precision, ARRAY[k]); sd := mu;
  FOR i IN 1..k LOOP
    mu[i] := p_sx[i] / p_n;
    sd[i] := sqrt(GREATEST(p_sxx[(i - 1) * k + i] / p_n - mu[i] * mu[i], 0)) + 1e-9;
  END LOOP;
  a := array_fill(0::double precision, ARRAY[d * d]); b := array_fill(0::double precision, ARRAY[d]);
  a[1] := p_n; b[1] := p_sy;
  FOR i IN 1..k LOOP
    a[i + 1] := (p_sx[i] - p_n * mu[i]) / sd[i];
    a[i * d + 1] := a[i + 1];
    b[i + 1] := (p_sxy[i] - mu[i] * p_sy) / sd[i];
    FOR j IN 1..k LOOP
      a[i * d + j + 1] := (p_sxx[(i - 1) * k + j] - mu[i] * p_sx[j] - mu[j] * p_sx[i] + p_n * mu[i] * mu[j])
                          / (sd[i] * sd[j]) + CASE WHEN i = j THEN p_lam ELSE 0 END;
    END LOOP;
  END LOOP;
  w := public.ottoq_linsolve(a, b);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_bess_forecast_refit(p_depot_id uuid, p_quantile numeric DEFAULT 0.8,
    p_lam numeric DEFAULT 10, p_window interval DEFAULT '28 days', p_note text DEFAULT NULL, p_runs uuid[] DEFAULT NULL,
    p_fold_by text DEFAULT 'run_day', p_run_by text[] DEFAULT ARRAY['operator_demo', 'production_live'])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
 SET client_min_messages TO 'warning'
AS $function$
/* 0803: fit the battery's learned load forecast from the depot's logged ticks (ottoq_bess_forecast_log) and write one row
   of ottoq_bess_forecast_models. The examples: every logged tick and each half hour h ahead (0-7); the target the mean EV
   charging over the snapshots in (clock + 30h, clock + 30h + 30 min] of the same run (at least 6 of them); the features
   those of the research lab's fit (forecast_learn.py): the cars on a charger now, the arrivals the known term adds, the
   queue, the last hour, the building, the sun, the hour of the day (sine, cosine) and the rule without the arrivals. A
   fold is a run ('run') or a run's local day ('run_day', the default: a production session can run for weeks). The upper
   band at h is p_quantile of every fold's misses when that fold was left out (out of sample, as the forecast misses on a
   day it never saw). p_runs fits those runs whatever their age and origin (the lab's held-out fits); else the ticks of
   runs by p_run_by logged within p_window. Usable with 3 folds and 200 examples at every h ahead. An estimate (rule 10). */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  v_runs uuid[]; v_folds int; v_nex int; r record; f record; v_fit record; v_per jsonb := '[]'::jsonb;
  v_off double precision; v_usable boolean; v_id bigint; v_prof jsonb; v_sql text; v_from timestamptz;
BEGIN
  IF p_fold_by NOT IN ('run', 'run_day') THEN RAISE EXCEPTION 'ottoq_bess_forecast_refit: p_fold_by is run or run_day'; END IF;
  v_from := CASE WHEN p_runs IS NULL THEN now() - p_window END;
  DROP TABLE IF EXISTS _bf_log, _bf_snap, _bf_ex, _bf_stats, _bf_tot, _bf_res;

  CREATE TEMP TABLE _bf_log ON COMMIT DROP AS
    SELECT l.* FROM public.ottoq_bess_forecast_log l
     WHERE l.depot_id = p_depot_id AND l.sim_run_id IS NOT NULL
       AND (CASE WHEN p_runs IS NOT NULL THEN l.sim_run_id = ANY(p_runs)
                 ELSE l.logged_at >= v_from AND l.run_by = ANY(p_run_by) END);
  CREATE TEMP TABLE _bf_snap ON COMMIT DROP AS
    SELECT DISTINCT ON (sim_run_id, snapshot_at) sim_run_id, snapshot_at, ev_drawn_kw::double precision AS ev,
           (site_base_kw + ev_drawn_kw - site_solar_kw)::double precision AS pre
      FROM _bf_log WHERE snapshot_at IS NOT NULL
     ORDER BY sim_run_id, snapshot_at, log_id;
  CREATE INDEX ON _bf_snap (sim_run_id, snapshot_at);

  CREATE TEMP TABLE _bf_ex ON COMMIT DROP AS
  SELECT q.*, CASE p_fold_by WHEN 'run' THEN q.sim_run_id::text
                             ELSE q.sim_run_id::text || '/' || ((q.sim_clock AT TIME ZONE c_tz)::date)::text END AS fold
    FROM (
      SELECT l.log_id, l.sim_run_id, l.sim_clock, g.h, y.ev AS y, y.n AS n_snap,
             l.on_charger_kw[g.h + 1]::double precision AS x1,
             (l.known_kw[g.h + 1] - l.on_charger_kw[g.h + 1])::double precision AS x2,
             l.queue_kw[g.h + 1]::double precision AS x3,
             l.ev_persist_kw::double precision AS x4,
             COALESCE(l.base_kw[g.h + 1], 0)::double precision AS x5,
             COALESCE(l.solar_kw[g.h + 1], 0)::double precision AS x6,
             sin(2 * pi() * lh.hr / 24) AS x7,
             cos(2 * pi() * lh.hr / 24) AS x8,
             GREATEST(l.on_charger_kw[g.h + 1], l.queue_kw[g.h + 1], l.ev_persist_kw)::double precision AS x9,
             l.rule_ev_kw[g.h + 1]::double precision AS rule
        FROM _bf_log l
       CROSS JOIN generate_series(0, 7) AS g(h)
       CROSS JOIN LATERAL (
         SELECT extract(hour FROM (l.sim_clock + make_interval(mins => 30 * g.h)) AT TIME ZONE c_tz)
                + extract(minute FROM (l.sim_clock + make_interval(mins => 30 * g.h)) AT TIME ZONE c_tz) / 60.0 AS hr) lh
       CROSS JOIN LATERAL (
         SELECT avg(s.ev) AS ev, count(*) AS n FROM _bf_snap s
          WHERE s.sim_run_id = l.sim_run_id
            AND s.snapshot_at >  l.sim_clock + make_interval(mins => 30 * g.h)
            AND s.snapshot_at <= l.sim_clock + make_interval(mins => 30 * g.h + 30)) y
       WHERE l.on_charger_kw[g.h + 1] IS NOT NULL AND l.known_kw[g.h + 1] IS NOT NULL
         AND l.queue_kw[g.h + 1] IS NOT NULL AND l.rule_ev_kw[g.h + 1] IS NOT NULL AND l.ev_persist_kw IS NOT NULL
    ) q
   WHERE q.n_snap >= 6;
  CREATE INDEX ON _bf_ex (h, fold);

  SELECT array_agg(DISTINCT sim_run_id), count(DISTINCT fold), count(*) INTO v_runs, v_folds, v_nex FROM _bf_ex;
  IF v_nex IS NULL OR v_nex = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_examples', 'logged_ticks', (SELECT count(*) FROM _bf_log));
  END IF;

  -- the raw sums per half hour ahead and fold
  v_sql := format('CREATE TEMP TABLE _bf_stats ON COMMIT DROP AS SELECT h, fold, count(*)::double precision AS n, '
                  'sum(y) AS sy, ARRAY[%s] AS sx, ARRAY[%s] AS sxy, ARRAY[%s] AS sxx FROM _bf_ex GROUP BY h, fold',
    (SELECT string_agg(format('sum(x%s)', i), ', ' ORDER BY i) FROM generate_series(1, 9) i),
    (SELECT string_agg(format('sum(x%s * y)', i), ', ' ORDER BY i) FROM generate_series(1, 9) i),
    (SELECT string_agg(format('sum(x%s * x%s)', i, j), ', ' ORDER BY i, j) FROM generate_series(1, 9) i, generate_series(1, 9) j));
  EXECUTE v_sql;
  CREATE TEMP TABLE _bf_tot ON COMMIT DROP AS
    SELECT h, sum(n) AS n, sum(sy) AS sy,
           (SELECT array_agg(v ORDER BY o) FROM (SELECT o, sum(x) AS v FROM _bf_stats s2, unnest(s2.sx) WITH ORDINALITY u(x, o) WHERE s2.h = s.h GROUP BY o) z) AS sx,
           (SELECT array_agg(v ORDER BY o) FROM (SELECT o, sum(x) AS v FROM _bf_stats s2, unnest(s2.sxy) WITH ORDINALITY u(x, o) WHERE s2.h = s.h GROUP BY o) z) AS sxy,
           (SELECT array_agg(v ORDER BY o) FROM (SELECT o, sum(x) AS v FROM _bf_stats s2, unnest(s2.sxx) WITH ORDINALITY u(x, o) WHERE s2.h = s.h GROUP BY o) z) AS sxx
      FROM _bf_stats s GROUP BY h;

  -- each fold's misses with that fold left out of the fit
  CREATE TEMP TABLE _bf_res (h int, fold text, y double precision, yhat double precision, rule double precision) ON COMMIT DROP;
  FOR f IN SELECT s.h, s.fold, t.n - s.n AS n, t.sy - s.sy AS sy,
                  (SELECT array_agg(a - b ORDER BY o) FROM unnest(t.sx, s.sx) WITH ORDINALITY u(a, b, o)) AS sx,
                  (SELECT array_agg(a - b ORDER BY o) FROM unnest(t.sxy, s.sxy) WITH ORDINALITY u(a, b, o)) AS sxy,
                  (SELECT array_agg(a - b ORDER BY o) FROM unnest(t.sxx, s.sxx) WITH ORDINALITY u(a, b, o)) AS sxx
             FROM _bf_stats s JOIN _bf_tot t USING (h) ORDER BY s.h, s.fold
  LOOP
    IF f.n < 10 THEN CONTINUE; END IF;
    v_fit := public.ottoq_ridge_from_stats(f.n, f.sy, f.sx, f.sxy, f.sxx, p_lam::double precision);
    IF v_fit.w IS NULL THEN CONTINUE; END IF;
    INSERT INTO _bf_res
    SELECT e.h, e.fold, e.y,
           v_fit.w[1] + (e.x1 - v_fit.mu[1]) / v_fit.sd[1] * v_fit.w[2] + (e.x2 - v_fit.mu[2]) / v_fit.sd[2] * v_fit.w[3]
           + (e.x3 - v_fit.mu[3]) / v_fit.sd[3] * v_fit.w[4] + (e.x4 - v_fit.mu[4]) / v_fit.sd[4] * v_fit.w[5]
           + (e.x5 - v_fit.mu[5]) / v_fit.sd[5] * v_fit.w[6] + (e.x6 - v_fit.mu[6]) / v_fit.sd[6] * v_fit.w[7]
           + (e.x7 - v_fit.mu[7]) / v_fit.sd[7] * v_fit.w[8] + (e.x8 - v_fit.mu[8]) / v_fit.sd[8] * v_fit.w[9]
           + (e.x9 - v_fit.mu[9]) / v_fit.sd[9] * v_fit.w[10],
           e.rule
      FROM _bf_ex e WHERE e.h = f.h AND e.fold = f.fold;
  END LOOP;

  -- the fit on every fold, the band from the out-of-sample misses
  FOR r IN SELECT * FROM _bf_tot ORDER BY h LOOP
    v_fit := public.ottoq_ridge_from_stats(r.n, r.sy, r.sx, r.sxy, r.sxx, p_lam::double precision);
    SELECT percentile_cont(p_quantile::double precision) WITHIN GROUP (ORDER BY y - yhat) INTO v_off
      FROM _bf_res WHERE h = r.h;
    v_per := v_per || jsonb_build_array(jsonb_build_object(
      'h', r.h, 'n', r.n::int, 'mu', to_jsonb(v_fit.mu), 'sd', to_jsonb(v_fit.sd), 'w', to_jsonb(v_fit.w),
      'offset_kw', COALESCE(v_off, 0),
      'cv', (SELECT jsonb_build_object('n', count(*), 'mae_kw', round(avg(abs(yhat - y))::numeric, 1),
                                       'bias_kw', round(avg(yhat - y)::numeric, 1),
                                       'rule_mae_kw', round(avg(abs(rule - y))::numeric, 1),
                                       'rule_bias_kw', round(avg(rule - y)::numeric, 1),
                                       'upper_coverage', round(avg(CASE WHEN y <= yhat + COALESCE(v_off, 0) THEN 1 ELSE 0 END)::numeric, 3))
               FROM _bf_res WHERE h = r.h)));
  END LOOP;

  -- the depot's pre-battery load (building + EV - sun) and EV alone by half hour of the local day, for the hours beyond
  WITH s AS (
    SELECT sim_run_id, (snapshot_at - interval '1 microsecond') AT TIME ZONE c_tz AS lt, pre, ev FROM _bf_snap),
  db AS (
    SELECT sim_run_id, lt::date AS d,
           floor((extract(hour FROM lt) * 60 + extract(minute FROM lt) + extract(second FROM lt) / 60.0) / 30)::int AS b,
           avg(pre) AS pre, avg(ev) AS ev
      FROM s GROUP BY 1, 2, 3 HAVING count(*) >= 4)
  SELECT jsonb_agg(jsonb_build_object('b', b, 'n_days', n,
                                      'pre_mean_kw', round(pre_mean::numeric, 1), 'pre_upper_kw', round(pre_q::numeric, 1),
                                      'ev_mean_kw', round(ev_mean::numeric, 1), 'ev_upper_kw', round(ev_q::numeric, 1))
                   ORDER BY b)
    INTO v_prof
    FROM (SELECT b, count(*) AS n, avg(pre) AS pre_mean, avg(ev) AS ev_mean,
                 percentile_cont(p_quantile::double precision) WITHIN GROUP (ORDER BY pre) AS pre_q,
                 percentile_cont(p_quantile::double precision) WITHIN GROUP (ORDER BY ev) AS ev_q
            FROM db GROUP BY b) z;

  v_usable := v_folds >= 3 AND (SELECT min(n) FROM _bf_tot) >= 200 AND (SELECT count(*) FROM _bf_tot) = 8
              AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_per) x WHERE x->'w' = 'null'::jsonb);
  INSERT INTO public.ottoq_bess_forecast_models (depot_id, note, usable, quantile, lam, fold_by, window_from, runs, n_folds,
         n_examples, features, per_half_hour, profile, diagnostics)
  VALUES (p_depot_id, p_note, v_usable, p_quantile, p_lam, p_fold_by, v_from, v_runs, v_folds, v_nex,
          ARRAY['1', 'on_charger', 'arrivals', 'queue', 'last_hour', 'base', 'solar', 'sin_hour', 'cos_hour',
                'rule_without_arrivals'],
          v_per, v_prof,
          jsonb_build_object('logged_ticks', (SELECT count(*) FROM _bf_log), 'snapshots', (SELECT count(*) FROM _bf_snap),
                             'run_by', CASE WHEN p_runs IS NULL THEN to_jsonb(p_run_by) END))
  RETURNING model_id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'model_id', v_id, 'usable', v_usable, 'runs', cardinality(v_runs),
                            'folds', v_folds, 'examples', v_nex);
END;
$function$;

-- ══ (e) the forecast the battery reads ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_bess_forecast_model(p_depot_id uuid)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  /* 0803: the depot's latest usable learned load forecast, or NULL */
  SELECT model_id FROM public.ottoq_bess_forecast_models
   WHERE depot_id = p_depot_id AND usable ORDER BY model_id DESC LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_bess_learned_forecast(p_sim_run_id uuid, p_depot_id uuid,
    p_sim_clock timestamp with time zone, p_day_plan jsonb DEFAULT NULL, p_model_id bigint DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0803: the depot's learned load forecast at this moment: for each of the next 8 half hours the EV charging the model
   predicts from the day plan's own terms (mean, and mean plus its band; never below zero), the pre-battery load they make
   with the day plan's building and sun (never below zero, as the research lab's planner read it), and for the 48 half
   hours from now the depot's learned load by half hour of the day (the hours beyond; NULL where the depot has no day yet).
   p_day_plan as the orchestrator solved it, else solved here. NULL when no model is usable. */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  v_mid bigint := COALESCE(p_model_id, public.ottoq_bess_forecast_model(p_depot_id));
  m record; v_plan jsonb := p_day_plan; v_f jsonb; v_act numeric[]; v_persist double precision;
  h int; i int; v_hr double precision; x double precision[]; z double precision; ph jsonb; v_ev double precision;
  v_on double precision; v_known double precision; v_queue double precision; v_base double precision; v_solar double precision;
  v_mean jsonb := '[]'::jsonb; v_up jsonb := '[]'::jsonb; v_pre_m jsonb := '[]'::jsonb; v_pre_u jsonb := '[]'::jsonb;
  v_beyond jsonb := '[]'::jsonb; v_lt timestamp; v_b int; v_t timestamptz;
BEGIN
  IF v_mid IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO m FROM public.ottoq_bess_forecast_models WHERE model_id = v_mid AND depot_id = p_depot_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF v_plan IS NULL OR NOT COALESCE((v_plan->>'ok')::boolean, false) OR v_plan->'forecast' IS NULL THEN
    v_plan := public.ottoq_bess_day_plan(p_sim_run_id, p_depot_id, p_sim_clock, NULL);
  END IF;
  IF NOT COALESCE((v_plan->>'ok')::boolean, false) THEN RETURN NULL; END IF;
  v_f := v_plan->'forecast';
  v_persist := COALESCE((v_plan->>'ev_persist_kw')::double precision, 0);
  v_act := public.ottoq_forecast_ev_on_charger_kw(p_sim_run_id, p_depot_id, p_sim_clock, 8, 30);
  FOR h IN 0..7 LOOP
    ph := m.per_half_hour -> h;
    v_on    := round(v_act[h + 1], 0)::double precision;   -- as the log keeps it
    v_known := COALESCE((v_f->'ev_known_kw'->>h)::double precision, 0);
    v_queue := COALESCE((v_f->'ev_queue_kw'->>h)::double precision, 0);
    v_base  := COALESCE((v_f->'base_kw'->>h)::double precision, 0);
    v_solar := COALESCE((v_f->'solar_kw'->>h)::double precision, 0);
    v_t := p_sim_clock + make_interval(mins => 30 * h);
    v_hr := extract(hour FROM v_t AT TIME ZONE c_tz) + extract(minute FROM v_t AT TIME ZONE c_tz) / 60.0;
    x := ARRAY[v_on, v_known - v_on, v_queue, v_persist, v_base, v_solar,
               sin(2 * pi() * v_hr / 24), cos(2 * pi() * v_hr / 24), GREATEST(v_on, v_queue, v_persist)];
    z := (ph->'w'->>0)::double precision;
    FOR i IN 1..9 LOOP
      z := z + (x[i] - (ph->'mu'->>(i - 1))::double precision) / (ph->'sd'->>(i - 1))::double precision
               * (ph->'w'->>i)::double precision;
    END LOOP;
    v_ev := GREATEST(0, z);
    v_mean := v_mean || to_jsonb(round(v_ev::numeric, 1));
    v_pre_m := v_pre_m || to_jsonb(round(GREATEST(0, v_base + v_ev - v_solar)::numeric, 1));
    v_ev := GREATEST(0, z + COALESCE((ph->>'offset_kw')::double precision, 0));
    v_up := v_up || to_jsonb(round(v_ev::numeric, 1));
    v_pre_u := v_pre_u || to_jsonb(round(GREATEST(0, v_base + v_ev - v_solar)::numeric, 1));
  END LOOP;
  -- the 48 half hours from now by the depot's day: half hour k covers (clock + 30k, clock + 30k + 30 min]
  FOR h IN 0..47 LOOP
    v_lt := (p_sim_clock + make_interval(mins => 30 * h + 30) - interval '1 microsecond') AT TIME ZONE c_tz;
    v_b := floor((extract(hour FROM v_lt) * 60 + extract(minute FROM v_lt) + extract(second FROM v_lt) / 60.0) / 30)::int;
    v_beyond := v_beyond || COALESCE((SELECT jsonb_build_object('pre_mean_kw', p->'pre_mean_kw', 'pre_upper_kw', p->'pre_upper_kw',
                                                                'ev_mean_kw', p->'ev_mean_kw', 'ev_upper_kw', p->'ev_upper_kw')
                                        FROM jsonb_array_elements(m.profile) p WHERE (p->>'b')::int = v_b), 'null'::jsonb);
  END LOOP;
  RETURN jsonb_build_object('model_id', v_mid, 'quantile', m.quantile, 'step_min', 30,
                            'ev_mean_kw', v_mean, 'ev_upper_kw', v_up, 'pre_mean_kw', v_pre_m, 'pre_upper_kw', v_pre_u,
                            'profile', v_beyond);
END;
$function$;

REVOKE ALL ON FUNCTION public.ottoq_bess_forecast_log_tick(uuid,uuid,timestamptz,bigint,jsonb),
                       public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[]),
                       public.ottoq_bess_forecast_append_only()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_bess_forecast_model(uuid),
                          public.ottoq_bess_learned_forecast(uuid,uuid,timestamptz,jsonb,bigint),
                          public.ottoq_forecast_ev_on_charger_kw(uuid,uuid,timestamptz,integer,numeric)
  TO anon, authenticated, service_role;

-- ══ the dial ════════════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bess_forecast_learning',
        '0803 (B1): 1 = the energy orchestrator writes one row a tick of the battery forecast''s evidence '
        '(ottoq_bess_forecast_log: the day plan''s forecast inputs and the site snapshot it read), which the nightly refit '
        '(ottoq_bess_forecast_refit) learns the depot''s load forecast from. It changes no decision. 0 = no row. '
        'A person''s dial (rule 10).',
        0, 0, 1, 'public.ottoq_energy_orchestrate', false);

-- ══ (b) the orchestrator's one insertion ════════════════════════════════════════════════════════════════════════════
CREATE TEMP TABLE _0803_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0803_patch VALUES
(1,
$o$  RETURN round(v_charge_cap,1);
END;
$o$,
$n$  /* 0803 (B1): the battery forecast's evidence, one row a tick while bess_forecast_learning is on: the plan the battery
     just acted on, its forecast inputs and the site snapshot it read (ottoq_bess_forecast_log). An estimate's data (rule
     10): it changes no decision, and a failure is a warning, never a stopped tick. */
  IF ottoq_policy_get(p_sim_run_id, 'bess_forecast_learning', 0) >= 0.5 THEN
    BEGIN
      PERFORM public.ottoq_bess_forecast_log_tick(p_sim_run_id, p_depot_id, p_sim_clock, p_tick_seq, v_day_plan);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0803: the battery forecast log failed at tick %: %', p_tick_seq, SQLERRM;
    END;
  END IF;
  RETURN round(v_charge_cap,1);
END;
$n$);

UPDATE _0803_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  FOR p IN SELECT * FROM _0803_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0803: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0803: the orchestrator is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the orchestrator less its insertion is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  v_body := (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  FOR p IN SELECT * FROM _0803_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) NOT IN ('8f425cda7b4b8486b8b44594b9bfe11f', 'db31a8c652ef44f147926651d0e48557') THEN
    RAISE EXCEPTION '0803 V1: the orchestrator less its insertion is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the solver and the fit on known answers ──
DO $v2$
DECLARE x double precision[]; v_fit record; n double precision := 0; sy double precision := 0;
  sx double precision[] := ARRAY[0, 0]::double precision[]; sxy double precision[] := ARRAY[0, 0]::double precision[];
  sxx double precision[] := ARRAY[0, 0, 0, 0]::double precision[]; i int; a double precision; b double precision;
  y double precision; v_b1 double precision; v_b2 double precision; v_b0 double precision;
BEGIN
  -- 2x + y - z = 8, -3x - y + 2z = -11, -2x + y + 2z = -3: x = 2, y = 3, z = -1
  x := public.ottoq_linsolve(ARRAY[2, 1, -1, -3, -1, 2, -2, 1, 2]::double precision[], ARRAY[8, -11, -3]::double precision[]);
  IF abs(x[1] - 2) > 1e-9 OR abs(x[2] - 3) > 1e-9 OR abs(x[3] + 1) > 1e-9 THEN
    RAISE EXCEPTION '0803 V2: ottoq_linsolve gave % for (2, 3, -1)', x;
  END IF;
  IF public.ottoq_linsolve(ARRAY[1, 2, 2, 4]::double precision[], ARRAY[1, 2]::double precision[]) IS NOT NULL THEN
    RAISE EXCEPTION '0803 V2: ottoq_linsolve solved a singular system';
  END IF;
  -- y = 5 + 3 a - 2 b exactly, on a grid; lambda 0 recovers it through the standardisation
  FOR i IN 0..39 LOOP
    a := i % 7; b := (i * 3) % 11; y := 5 + 3 * a - 2 * b;
    n := n + 1; sy := sy + y;
    sx[1] := sx[1] + a; sx[2] := sx[2] + b; sxy[1] := sxy[1] + a * y; sxy[2] := sxy[2] + b * y;
    sxx[1] := sxx[1] + a * a; sxx[2] := sxx[2] + a * b; sxx[3] := sxx[3] + b * a; sxx[4] := sxx[4] + b * b;
  END LOOP;
  v_fit := public.ottoq_ridge_from_stats(n, sy, sx, sxy, sxx, 0);
  v_b1 := v_fit.w[2] / v_fit.sd[1]; v_b2 := v_fit.w[3] / v_fit.sd[2];
  v_b0 := v_fit.w[1] - v_b1 * v_fit.mu[1] - v_b2 * v_fit.mu[2];
  IF abs(v_b0 - 5) > 1e-6 OR abs(v_b1 - 3) > 1e-6 OR abs(v_b2 + 2) > 1e-6 THEN
    RAISE EXCEPTION '0803 V2: the fit recovered (%, %, %) for (5, 3, -2)', v_b0, v_b1, v_b2;
  END IF;
END $v2$;

-- ── V3: the refit and the reader on synthetic ticks, rolled back with their rows ──
DO $v3$
DECLARE
  c_run CONSTANT uuid := '00000000-0000-0000-0803-000000000003';
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  t0 timestamptz := '2026-01-05 12:05:00+00';   -- 6:05 AM CST
  k int; h int; t timestamptz; v_res jsonb; v_m record; v_fc jsonb; v_wave double precision;
  ev double precision[]; v_mae double precision;
BEGIN
  BEGIN
    -- three local days of a known daily wave, 5-minute ticks; the feature "on a charger now" is the half hour's own mean
    -- ahead (a perfect predictor), so the out-of-sample miss is small against the wave
    ev := array_fill(0::double precision, ARRAY[3 * 288 + 120]);
    FOR k IN 1..3 * 288 + 120 LOOP
      t := t0 + make_interval(mins => 5 * (k - 1));
      ev[k] := 500 + 300 * sin(2 * pi() * (extract(epoch FROM t) / 3600.0) / 24);
    END LOOP;
    FOR k IN 1..3 * 288 LOOP
      t := t0 + make_interval(mins => 5 * (k - 1));
      INSERT INTO public.ottoq_bess_forecast_log (depot_id, sim_run_id, run_by, data_source, tick_seq, sim_clock,
             snapshot_at, ev_drawn_kw, site_base_kw, site_solar_kw, grid_kw, ev_persist_kw, on_charger_kw, known_kw,
             queue_kw, base_kw, solar_kw, rule_ev_kw)
      SELECT c_twin, c_run, 'operator_demo', 'sim', k, t, t, ev[k], 50, 0, 50 + ev[k], ev[k],
             w.m, w.m, array_fill(0::numeric, ARRAY[16]), array_fill(50::numeric, ARRAY[16]),
             array_fill(0::numeric, ARRAY[16]), w.m
        FROM (SELECT array_agg(round((SELECT avg(ev[j]) FROM generate_series(k + 6 * hh + 1, k + 6 * hh + 6) j)::numeric, 0)
                               ORDER BY hh) AS m
                FROM generate_series(0, 15) hh) w;
    END LOOP;
    v_res := public.ottoq_bess_forecast_refit(c_twin, 0.8, 10, '28 days', '0803 V3 (rolled back)', ARRAY[c_run], 'run_day');
    IF NOT COALESCE((v_res->>'ok')::boolean, false) OR NOT COALESCE((v_res->>'usable')::boolean, false) THEN
      RAISE EXCEPTION '0803 V3: the refit on the synthetic days is not a usable model: %', v_res;
    END IF;
    SELECT * INTO v_m FROM public.ottoq_bess_forecast_models WHERE model_id = (v_res->>'model_id')::bigint;
    IF v_m.n_folds <> 4 OR jsonb_array_length(v_m.per_half_hour) <> 8 OR jsonb_array_length(v_m.profile) <> 48 THEN
      RAISE EXCEPTION '0803 V3: folds %, half hours %, profile bins % (4, 8, 48 expected)', v_m.n_folds,
        jsonb_array_length(v_m.per_half_hour), jsonb_array_length(v_m.profile);
    END IF;
    SELECT max((x->'cv'->>'mae_kw')::double precision) INTO v_mae FROM jsonb_array_elements(v_m.per_half_hour) x;
    IF v_mae > 30 THEN
      RAISE EXCEPTION '0803 V3: the out-of-sample miss on a known wave is % kW (30 allowed against a 300 kW wave)', v_mae;
    END IF;
    v_fc := public.ottoq_bess_learned_forecast(c_run, c_twin, t0 + interval '30 hours',
              jsonb_build_object('ok', true, 'ev_persist_kw', 500,
                                 'forecast', jsonb_build_object('ev_known_kw', to_jsonb(array_fill(500, ARRAY[16])),
                                                                'ev_queue_kw', to_jsonb(array_fill(0, ARRAY[16])),
                                                                'base_kw', to_jsonb(array_fill(50, ARRAY[16])),
                                                                'solar_kw', to_jsonb(array_fill(0, ARRAY[16])),
                                                                'ev_kw', to_jsonb(array_fill(500, ARRAY[16])))),
              (v_res->>'model_id')::bigint);
    IF v_fc IS NULL OR jsonb_array_length(v_fc->'pre_upper_kw') <> 8 OR jsonb_array_length(v_fc->'profile') <> 48
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_fc->'pre_upper_kw') x WHERE x::text::double precision < 0)
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_fc->'profile') x WHERE x = 'null'::jsonb) THEN
      RAISE EXCEPTION '0803 V3: the reader did not return 8 half hours and 48 beyond: %', v_fc;
    END IF;
    RAISE NOTICE '0803 V3: synthetic refit % (largest out-of-sample miss % kW), reader %', v_res, v_mae, v_fc->'pre_upper_kw';
    RAISE EXCEPTION USING ERRCODE = 'P0803', MESSAGE = 'roll back the synthetic ticks';
  EXCEPTION WHEN SQLSTATE 'P0803' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_log WHERE sim_run_id = c_run)
     OR EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_models WHERE note = '0803 V3 (rolled back)') THEN
    RAISE EXCEPTION '0803 V3: the synthetic rows were not rolled back';
  END IF;
END $v3$;

-- ── V4: the patched orchestrator is byte for byte the body the research lab ran ──
DO $v4$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure)
     NOT IN ('adcfcf4ea52b56d9f60b63be7c338fcd', '5d607e3cfc88c7cc5a459407b4445532') THEN
    RAISE EXCEPTION '0803 V4: the patched orchestrator is not the body the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  END IF;
END $v4$;

-- ══ (f) the nightly refit ═══════════════════════════════════════════════════════════════════════════════════════════
SELECT cron.schedule('ottoq-learn-bess-forecast-nightly', '26 11 * * *',
  $cron$SELECT public.ottoq_bess_forecast_refit('11111111-1111-1111-1111-111111111111'::uuid, 0.8, 10, interval '28 days', 'nightly');$cron$);

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0803_the_battery_learns_its_load_forecast_from_the_depots_own_days', false, false,
        'B1. The battery''s load forecast, learned each night from the depot''s own days: a per-tick evidence log behind '
        'bess_forecast_learning (default 0), a ridge per half hour ahead with its out-of-sample 80th-percentile band and '
        'the depot''s load by half hour of the day, refit nightly at 11:26 UTC. Nothing reads the forecast yet. With the '
        'dial off the orchestrator decides as before; with it on it writes evidence no atom reads.',
        now());

COMMIT;
