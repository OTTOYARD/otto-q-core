-- migration-version: PENDING
-- migration-name:    the_battery_forecast_is_shrunk_as_far_as_its_own_misses_say_and_defers_to_the_day_plan_where_that_misses_less
--
-- 0809  **The battery's forecast is shrunk as far as its own misses say, and defers to the day plan where that misses
--       less.** (G530; B1, the production battery planner)
--
-- ══ §0 WHY NOW ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0803 learns the depot's load forecast from its own days and 0808 (applied 2026-11-07 05:45:53 UTC) calls a model
--   usable only where its band was measured. Three demo runs followed (3091816d, 5c19fd60 on normal_day, 73d71553), and
--   models 7 (the nightly refit, 11:26:00 UTC) and 8 (by hand, 11:42:44 UTC) came out usable: 5 folds, 23,881 examples
--   in model 8. At 11:43:39 UTC bess_planner_enabled and energy_mpc_follow went on at the twin depot under Chase's name
--   (delegated, rule 12), and the battery has planned on model 8 since run a0001fd6 started (11:43:54 UTC). Model 8's
--   own record says it plans on a worse forecast than the one it replaced at most of the hours it covers (G530).
--
-- ══ §1 WHAT IS WRONG (FINDINGS G530) ═════════════════════════════════════════════════════════════════════════════════
--
--   The battery reads the model's upper band at every half hour h < 8 (0804). Model 8's out-of-sample miss (MAE) against
--   the day plan's own EV forecast on the same examples, by half hour ahead:
--       h      0      1      2      3      4      5      6      7
--     model  261.4  443.8  433.2  356.7  367.6  276.7  252.2  364.7  kW
--     day   1620.8  344.5  324.2  339.5  346.1  282.3  176.2  154.9  kW
--   It wins at the next half hour, where the day plan carries G524's inflation, and loses at 6 of the 7 after it.
--   Read in the research lab (ottoq_lab_0809: production's 4,599 logged ticks of the five runs the model read, md5
--   015c14d5 equal to production's, and production's refit, which rebuilt model 8 exactly: every weight, band and miss):
--   the ridge is fitted at lam = 10, the research lab's value for six 36-hour lab days. The demo runs are 3 to 5 1/2
--   sim-hours, each from 8 AM, so the examples at a half hour ahead come from one narrow window of each run's day, and
--   ticks 15 seconds apart are near copies, while a fold is a run's day: thousands of rows, four or five independent
--   days. At lam = 10 the fit learns each training day's quirks and misses the day left out. Giving it the day plan's
--   own EV forecast as a tenth feature changes nothing (h = 1: 443.8 to 429.0 kW; h = 2..7 within 4 kW), so the defect
--   is the fit, not its inputs.
--   The battery plans on the 80% upper band, and what grades a band is its own loss: the 0.8 pinball loss of each miss
--   less the band (lower is better). Out of sample on production's evidence:
--       h        0      1      2      3      4      5      6      7     sum
--     lam 10   71.7  132.3  127.9  103.1  125.6   94.8   79.3  123.9   858.6 kW
--     day     240.7   95.9  102.1  100.8   93.4   80.2   61.6   50.4   825.1
--     chosen   62.0   80.2   86.7   77.9   69.4   47.9   37.1   35.9   497.1  (lam per h from 10, 10^2, ..., 10^9)
--   Chosen out of sample by a nested split (the regularization picked on the other folds alone), the sum is 551.2 kW:
--   35.8% under lam = 10 and 33.2% under the day plan. The bands narrow from model 8's 217 to 823 kW to 119 to 352 kW.
--   The point miss (MAE) stays above the day plan's at h = 1..3 (360, 386, 356 against 345, 324, 340 kW); the battery
--   reads the band, and there the model is the better forecast at every half hour. On the six 36-hour lab days lam = 10
--   is the best at every half hour and the nested split picks it 96 times in 96, so the change leaves the lab's model as
--   it was. On the normal_day run (5c19fd60) the depot's mean EV draw 1 to 3 hours ahead was 0 to 173 kW, and every
--   forecast, the day plan's included, ran 1,100 to 1,700 kW above it on average. That is the next finding, not this one.
--
-- ══ §2 WHAT THIS CHANGES (two functions, nine anchored edits; a run reads it only where bess_planner_enabled is 1) ═══
--
--   ottoq_bess_forecast_refit (five edits):
--   (1) each fold's misses are read at nine regularizations, p_lam x 10^k for k = 0..8 (10 to 10^9 from the nightly
--       call), each on the same misses: a fold whose fit fails at one is left out at all;
--   (2) at each half hour ahead the fit on every fold takes the regularization whose band had the least pinball loss,
--       to the watt, a tie to the lighter, and the band is read from that one's misses;
--   (3) the day plan's own EV forecast is graded on the same misses with its own band (the p_quantile of its misses).
--       Where its loss is less, the record's source is 'day_plan'; otherwise 'learned';
--   (4) each half hour's record gains 'lam', 'source' and 'rule_offset_kw', and its cv gains 'loss_kw', 'rule_loss_kw'
--       and 'loss_by_lam', which only people read; the comment says so. Usable is judged as 0808 judges it.
--   ottoq_bess_learned_forecast (four edits): at a half hour whose source is 'day_plan' the EV forecast is the day plan's
--   own (forecast.ev_kw) and its band adds rule_offset_kw; the result lists each half hour's source. A model written
--   before this file has no source and reads as the model, so models 7 and 8 read as they do today.
--   Nothing else reads a model (catalog read 2026-11-07: the refit, the evaluator, and the request builder through the
--   evaluator, which reads model_id, pre_upper_kw and profile). The models are append-only: 8 stays in use until the
--   next refit (cron 802 at 5:26 AM CT, or by hand).
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1: not applied; 0808 applied; the refit at a142840c (0808's) and the evaluator at 7af83d4a
--   (0803's), read 2026-11-07. Pre-images to ottoq_schema_snapshots as '0809_pre'. Each anchor matches once.
--   V0 (production's own bodies, the depot's own evidence of the last 28 days from runs not running or paused, so a live
--   run adds no ticks between V0 and V2; rolled back): when it makes a usable model, at least one half hour ahead misses
--   more than the day plan. This is the defect, shown where it lives.
--   V1 each body less its changes is its pre-image.
--   V2 the same evidence after the change, rolled back: usable as before, with the same folds and examples; at every half
--   hour the record's source has the lesser loss, and the loss is no more than the one at p_lam.
--   V3 synthetic runs, three of 4 1/2 hours on three days, rolled back:
--   (a) the EV level differs by day; the day plan knows it and the features do not: 'day_plan' at every half hour;
--   (b) the same days with the features knowing and the day plan blind (a flat 2,000 kW): 'learned' at every half hour,
--       at lam 10^3 or less;
--   (c) the features carry a decoy, a level per day unrelated to the EV level, and the day plan is blind: at every half
--       hour the regularization chosen is heavier than p_lam, and the summed loss is under 80% of the one at p_lam.
--   V4 the evaluator on a synthetic model (rolled back) whose even half hours are 'day_plan': there the EV forecast is the
--   day plan's and its band adds rule_offset_kw; at the odd ones it is the model's, with offset_kw.
--   V5 the patched bodies are byte for byte the ones the lab ran (refit 8c8c7e73bb7749c2b2ad3af47d28377a,
--   evaluator c28dd8e88706a812e51ad011c4523a44).
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. A run reads a model only through the battery planner, where
--   bess_planner_enabled reads 1: at the twin depot (depot scope) since 2026-11-07 11:43:39 UTC. Certification is off
--   (rule 12). When it resumes, a pair at the twin depot reads the depot's dial unless its arm pins it at run scope, and
--   then what it reads is the latest model, which the nightly refit replaces whatever this file says: a property of the
--   switch-on, not of this file.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0809_pre';
--   DELETE FROM public.ottoq_cert_lineage
--    WHERE name = '0809_the_battery_forecast_is_shrunk_as_far_as_its_own_misses_say_and_defers_to_the_day_plan_where_that_misses_less'.
--   A model written after this file keeps its new keys; the old evaluator ignores them and reads every half hour as the
--   model.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0809 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0809_the_battery_forecast_is_shrunk_as_far_as_its_own_misses_say_and_defers_to_the_day_plan_where_that_misses_less') THEN
    RAISE EXCEPTION '0809 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0808_the_battery_forecast_is_usable_only_where_its_band_was_measured') THEN
    RAISE EXCEPTION '0809 P1: 0808 (the band measured at every half hour) comes first';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'))
     IS DISTINCT FROM 'a142840ca1fd8c5e787c76a19936d3ab' THEN
    RAISE EXCEPTION '0809 P1: public.ottoq_bess_forecast_refit is not the body 0808 left (a142840c)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_bess_learned_forecast(uuid,uuid,timestamptz,jsonb,bigint)'))
     IS DISTINCT FROM '7af83d4a826e63b1b50b89110f1e9cad' THEN
    RAISE EXCEPTION '0809 P1: public.ottoq_bess_learned_forecast is not the body 0803 left (7af83d4a)';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0809_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure,
                 'public.ottoq_bess_learned_forecast(uuid,uuid,timestamptz,jsonb,bigint)'::regprocedure);

-- what V0 read, for V2
CREATE TEMP TABLE _0809_v0 (runs uuid[], usable boolean, folds int, examples int, per_half_hour jsonb) ON COMMIT DROP;

-- ── V0: the defect, on production's own bodies and the depot's own evidence ──
DO $v0$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_res jsonb; v_per jsonb; v_worse int := 0; v_runs uuid[];
BEGIN
  -- the nightly call's evidence (28 days, these origins) less any run still running or paused
  v_runs := ARRAY(SELECT DISTINCT l.sim_run_id FROM public.ottoq_bess_forecast_log l
                   WHERE l.depot_id = c_twin AND l.sim_run_id IS NOT NULL AND l.logged_at >= now() - interval '28 days'
                     AND l.run_by = ANY(ARRAY['operator_demo', 'production_live'])
                     AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs s
                                      WHERE s.sim_run_id = l.sim_run_id AND s.status IN ('running', 'paused'))
                   ORDER BY 1);
  BEGIN
    v_res := public.ottoq_bess_forecast_refit(c_twin, 0.8, 10, '28 days', '0809 V0 (rolled back)', v_runs, 'run_day');
    IF COALESCE((v_res->>'usable')::boolean, false) THEN
      SELECT per_half_hour INTO v_per FROM public.ottoq_bess_forecast_models WHERE model_id = (v_res->>'model_id')::bigint;
      SELECT count(*) INTO v_worse FROM jsonb_array_elements(v_per) x
       WHERE (x->'cv'->>'mae_kw')::numeric > (x->'cv'->>'rule_mae_kw')::numeric;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0809', MESSAGE = 'roll back the refit';
  EXCEPTION WHEN SQLSTATE 'P0809' THEN
    NULL;
  END;
  IF COALESCE((v_res->>'usable')::boolean, false) THEN
    IF v_worse = 0 THEN
      RAISE EXCEPTION '0809 V0: the refit as it stands did not miss more than the day plan at any half hour (%)', v_res;
    END IF;
    RAISE NOTICE '0809 V0: before the change, % misses more than the day plan at % of 8 half hours', v_res, v_worse;
  ELSE
    RAISE NOTICE '0809 V0: no usable model from the depot''s evidence (%); V3 shows the change on synthetic runs', v_res;
  END IF;
  INSERT INTO _0809_v0 VALUES (v_runs, COALESCE((v_res->>'usable')::boolean, false), (v_res->>'folds')::int,
                               (v_res->>'examples')::int, v_per);
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_models WHERE note = '0809 V0 (rolled back)') THEN
    RAISE EXCEPTION '0809 V0: the refit was not rolled back';
  END IF;
END $v0$;

CREATE TEMP TABLE _0809_patch_refit (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0809_patch_refit VALUES
(1,
$o$   no band, and a model without one is not usable. An estimate (rule 10). */$o$,
$n$   no band, and a model without one is not usable. (0809, G530) Each fold's misses are read at nine regularizations,
   p_lam times 10^0 to 10^8, and at each h the fit on every fold takes the one whose band had the least p_quantile
   pinball loss out of sample (to the watt, a tie to the lighter), with the band from its own misses: the evidence sets
   how far the fit is shrunk. The day plan's own EV forecast is graded on the same misses with its own band; where its
   loss is less, the record's source is 'day_plan' and the battery reads that forecast there. An estimate (rule 10). */$n$),
(2,
$o$  v_off double precision; v_usable boolean; v_id bigint; v_prof jsonb; v_sql text; v_from timestamptz;$o$,
$n$  v_off double precision; v_usable boolean; v_id bigint; v_prof jsonb; v_sql text; v_from timestamptz;
  v_lams double precision[]; v_lam double precision; v_lam_h double precision; v_roff double precision;   -- 0809
  v_loss numeric; v_rloss numeric; v_scan jsonb; v_src text;$n$),
(3,
$o$  v_from := CASE WHEN p_runs IS NULL THEN now() - p_window END;$o$,
$n$  v_from := CASE WHEN p_runs IS NULL THEN now() - p_window END;
  v_lams := ARRAY(SELECT p_lam::double precision * power(10::double precision, k) FROM generate_series(0, 8) k ORDER BY k);$n$),
(4,
$o$  -- each fold's misses with that fold left out of the fit
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
  END LOOP;$o$,
$n$  -- each fold's misses with that fold left out of the fit, at each regularization tried (0809: p_lam times 10^0 to
  -- 10^8); a fold whose fit fails at one of them is left out at all of them, so each is graded on the same misses
  CREATE TEMP TABLE _bf_res (h int, fold text, y double precision, yhat double precision, rule double precision,
                             lam double precision) ON COMMIT DROP;
  FOR f IN SELECT s.h, s.fold, t.n - s.n AS n, t.sy - s.sy AS sy,
                  (SELECT array_agg(a - b ORDER BY o) FROM unnest(t.sx, s.sx) WITH ORDINALITY u(a, b, o)) AS sx,
                  (SELECT array_agg(a - b ORDER BY o) FROM unnest(t.sxy, s.sxy) WITH ORDINALITY u(a, b, o)) AS sxy,
                  (SELECT array_agg(a - b ORDER BY o) FROM unnest(t.sxx, s.sxx) WITH ORDINALITY u(a, b, o)) AS sxx
             FROM _bf_stats s JOIN _bf_tot t USING (h) ORDER BY s.h, s.fold
  LOOP
    IF f.n < 10 THEN CONTINUE; END IF;
    FOREACH v_lam IN ARRAY v_lams LOOP
      v_fit := public.ottoq_ridge_from_stats(f.n, f.sy, f.sx, f.sxy, f.sxx, v_lam);
      IF v_fit.w IS NULL THEN
        DELETE FROM _bf_res WHERE h = f.h AND fold = f.fold;
        EXIT;
      END IF;
      INSERT INTO _bf_res
      SELECT e.h, e.fold, e.y,
             v_fit.w[1] + (e.x1 - v_fit.mu[1]) / v_fit.sd[1] * v_fit.w[2] + (e.x2 - v_fit.mu[2]) / v_fit.sd[2] * v_fit.w[3]
             + (e.x3 - v_fit.mu[3]) / v_fit.sd[3] * v_fit.w[4] + (e.x4 - v_fit.mu[4]) / v_fit.sd[4] * v_fit.w[5]
             + (e.x5 - v_fit.mu[5]) / v_fit.sd[5] * v_fit.w[6] + (e.x6 - v_fit.mu[6]) / v_fit.sd[6] * v_fit.w[7]
             + (e.x7 - v_fit.mu[7]) / v_fit.sd[7] * v_fit.w[8] + (e.x8 - v_fit.mu[8]) / v_fit.sd[8] * v_fit.w[9]
             + (e.x9 - v_fit.mu[9]) / v_fit.sd[9] * v_fit.w[10],
             e.rule, v_lam
        FROM _bf_ex e WHERE e.h = f.h AND e.fold = f.fold;
    END LOOP;
  END LOOP;
  CREATE INDEX ON _bf_res (h, lam);$n$),
(5,
$o$  -- the fit on every fold, the band from the out-of-sample misses
  FOR r IN SELECT * FROM _bf_tot ORDER BY h LOOP
    v_fit := public.ottoq_ridge_from_stats(r.n, r.sy, r.sx, r.sxy, r.sxx, p_lam::double precision);
    SELECT percentile_cont(p_quantile::double precision) WITHIN GROUP (ORDER BY y - yhat) INTO v_off
      FROM _bf_res WHERE h = r.h;
    v_per := v_per || jsonb_build_array(jsonb_build_object(
      'h', r.h, 'n', r.n::int, 'folds', (SELECT count(DISTINCT fold) FROM _bf_ex WHERE h = r.h),
      'mu', to_jsonb(v_fit.mu), 'sd', to_jsonb(v_fit.sd), 'w', to_jsonb(v_fit.w),
      'offset_kw', COALESCE(v_off, 0),
      'cv', (SELECT jsonb_build_object('n', count(*), 'folds', count(DISTINCT fold), 'mae_kw', round(avg(abs(yhat - y))::numeric, 1),
                                       'bias_kw', round(avg(yhat - y)::numeric, 1),
                                       'rule_mae_kw', round(avg(abs(rule - y))::numeric, 1),
                                       'rule_bias_kw', round(avg(rule - y)::numeric, 1),
                                       'upper_coverage', round(avg(CASE WHEN y <= yhat + COALESCE(v_off, 0) THEN 1 ELSE 0 END)::numeric, 3))
               FROM _bf_res WHERE h = r.h)));
  END LOOP;$o$,
$n$  -- the fit on every fold, the band from the out-of-sample misses: (0809, G530) at the regularization whose band missed
  -- least out of sample, scored by the band's own loss (the p_quantile pinball loss of each miss less the band) to the
  -- watt, a tie to the lighter; and the day plan's own EV forecast graded on the same misses with its own band
  FOR r IN SELECT * FROM _bf_tot ORDER BY h LOOP
    v_scan := NULL; v_lam_h := NULL;
    SELECT jsonb_object_agg(z.lam::text, z.loss), (array_agg(z.lam ORDER BY z.loss, z.lam))[1]
      INTO v_scan, v_lam_h
      FROM (SELECT x.lam, round(avg(GREATEST(p_quantile::double precision * (x.y - x.yhat - o.off),
                                             (p_quantile::double precision - 1) * (x.y - x.yhat - o.off)))::numeric, 3) AS loss
              FROM _bf_res x
              JOIN (SELECT lam, percentile_cont(p_quantile::double precision) WITHIN GROUP (ORDER BY y - yhat) AS off
                      FROM _bf_res WHERE h = r.h GROUP BY lam) o ON o.lam = x.lam
             WHERE x.h = r.h
             GROUP BY x.lam) z;
    v_lam_h := COALESCE(v_lam_h, p_lam::double precision);
    v_fit := public.ottoq_ridge_from_stats(r.n, r.sy, r.sx, r.sxy, r.sxx, v_lam_h);
    SELECT percentile_cont(p_quantile::double precision) WITHIN GROUP (ORDER BY y - yhat),
           percentile_cont(p_quantile::double precision) WITHIN GROUP (ORDER BY y - rule)
      INTO v_off, v_roff
      FROM _bf_res WHERE h = r.h AND lam = v_lam_h;
    SELECT round(avg(GREATEST(p_quantile::double precision * (y - yhat - v_off),
                              (p_quantile::double precision - 1) * (y - yhat - v_off)))::numeric, 3),
           round(avg(GREATEST(p_quantile::double precision * (y - rule - v_roff),
                              (p_quantile::double precision - 1) * (y - rule - v_roff)))::numeric, 3)
      INTO v_loss, v_rloss
      FROM _bf_res WHERE h = r.h AND lam = v_lam_h;
    v_src := CASE WHEN v_rloss < v_loss THEN 'day_plan' ELSE 'learned' END;
    v_per := v_per || jsonb_build_array(jsonb_build_object(
      'h', r.h, 'n', r.n::int, 'folds', (SELECT count(DISTINCT fold) FROM _bf_ex WHERE h = r.h),
      'mu', to_jsonb(v_fit.mu), 'sd', to_jsonb(v_fit.sd), 'w', to_jsonb(v_fit.w),
      'offset_kw', COALESCE(v_off, 0), 'lam', v_lam_h, 'source', v_src, 'rule_offset_kw', COALESCE(v_roff, 0),
      'cv', (SELECT jsonb_build_object('n', count(*), 'folds', count(DISTINCT fold), 'mae_kw', round(avg(abs(yhat - y))::numeric, 1),
                                       'bias_kw', round(avg(yhat - y)::numeric, 1),
                                       'rule_mae_kw', round(avg(abs(rule - y))::numeric, 1),
                                       'rule_bias_kw', round(avg(rule - y)::numeric, 1),
                                       'upper_coverage', round(avg(CASE WHEN y <= yhat + COALESCE(v_off, 0) THEN 1 ELSE 0 END)::numeric, 3),
                                       'loss_kw', v_loss, 'rule_loss_kw', v_rloss, 'loss_by_lam', v_scan)
               FROM _bf_res WHERE h = r.h AND lam = v_lam_h)));
  END LOOP;$n$);

CREATE TEMP TABLE _0809_patch_eval (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0809_patch_eval VALUES
(1,
$o$   p_day_plan as the orchestrator solved it, else solved here. NULL when no model is usable. */$o$,
$n$   p_day_plan as the orchestrator solved it, else solved here. NULL when no model is usable. (0809, G530) At a half hour
   whose record says source 'day_plan' the day plan's own EV forecast missed less out of sample than the model, so the
   EV forecast there is the day plan's (forecast.ev_kw) and its band the day plan's own (rule_offset_kw); 'source' lists
   each half hour's. A model written before 0809 has no source and reads as the model. */$n$),
(2,
$o$  v_beyond jsonb := '[]'::jsonb; v_lt timestamp; v_b int; v_t timestamptz;$o$,
$n$  v_beyond jsonb := '[]'::jsonb; v_lt timestamp; v_b int; v_t timestamptz;
  v_src jsonb := '[]'::jsonb; v_rule boolean;   -- 0809$n$),
(3,
$o$    z := (ph->'w'->>0)::double precision;
    FOR i IN 1..9 LOOP
      z := z + (x[i] - (ph->'mu'->>(i - 1))::double precision) / (ph->'sd'->>(i - 1))::double precision
               * (ph->'w'->>i)::double precision;
    END LOOP;
    v_ev := GREATEST(0, z);
    v_mean := v_mean || to_jsonb(round(v_ev::numeric, 1));
    v_pre_m := v_pre_m || to_jsonb(round(GREATEST(0, v_base + v_ev - v_solar)::numeric, 1));
    v_ev := GREATEST(0, z + COALESCE((ph->>'offset_kw')::double precision, 0));$o$,
$n$    v_rule := COALESCE(ph->>'source', 'learned') = 'day_plan';   -- 0809 (G530)
    IF v_rule THEN
      z := COALESCE((v_f->'ev_kw'->>h)::double precision, 0);
    ELSE
      z := (ph->'w'->>0)::double precision;
      FOR i IN 1..9 LOOP
        z := z + (x[i] - (ph->'mu'->>(i - 1))::double precision) / (ph->'sd'->>(i - 1))::double precision
                 * (ph->'w'->>i)::double precision;
      END LOOP;
    END IF;
    v_src := v_src || to_jsonb(CASE WHEN v_rule THEN 'day_plan' ELSE 'learned' END);
    v_ev := GREATEST(0, z);
    v_mean := v_mean || to_jsonb(round(v_ev::numeric, 1));
    v_pre_m := v_pre_m || to_jsonb(round(GREATEST(0, v_base + v_ev - v_solar)::numeric, 1));
    v_ev := GREATEST(0, z + COALESCE((ph->>(CASE WHEN v_rule THEN 'rule_offset_kw' ELSE 'offset_kw' END))::double precision, 0));$n$),
(4,
$o$                            'profile', v_beyond);$o$,
$n$                            'profile', v_beyond, 'source', v_src);$n$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure);
  FOR p IN SELECT * FROM _0809_patch_refit ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0809: refit anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0809: the refit is not stored as patched';
  END IF;

  v_def := pg_get_functiondef('public.ottoq_bess_learned_forecast(uuid,uuid,timestamptz,jsonb,bigint)'::regprocedure);
  FOR p IN SELECT * FROM _0809_patch_eval ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0809: evaluator anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_bess_learned_forecast(uuid,uuid,timestamptz,jsonb,bigint)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0809: the evaluator is not stored as patched';
  END IF;
END $patch$;

-- ── V1: each body less its changes is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  v_body := (SELECT prosrc FROM pg_proc
              WHERE oid = 'public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure);
  FOR p IN SELECT * FROM _0809_patch_refit ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'a142840ca1fd8c5e787c76a19936d3ab' THEN
    RAISE EXCEPTION '0809 V1: the refit less its changes is not its pre-image (md5 %)', md5(v_body);
  END IF;
  v_body := (SELECT prosrc FROM pg_proc
              WHERE oid = 'public.ottoq_bess_learned_forecast(uuid,uuid,timestamptz,jsonb,bigint)'::regprocedure);
  FOR p IN SELECT * FROM _0809_patch_eval ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '7af83d4a826e63b1b50b89110f1e9cad' THEN
    RAISE EXCEPTION '0809 V1: the evaluator less its changes is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the same evidence after the change ──
DO $v2$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v0 record; v_res jsonb; v_per jsonb; v_bad int; v_sum numeric; v_sum_base numeric; v_sum_day numeric; v_src text;
BEGIN
  SELECT * INTO v0 FROM _0809_v0;
  IF NOT v0.usable THEN
    RAISE NOTICE '0809 V2: no usable model from the depot''s evidence before the change; V3 carries the check';
    RETURN;
  END IF;
  BEGIN
    v_res := public.ottoq_bess_forecast_refit(c_twin, 0.8, 10, '28 days', '0809 V2 (rolled back)', v0.runs, 'run_day');
    SELECT per_half_hour INTO v_per FROM public.ottoq_bess_forecast_models WHERE model_id = (v_res->>'model_id')::bigint;
    RAISE EXCEPTION USING ERRCODE = 'P0809', MESSAGE = 'roll back the refit';
  EXCEPTION WHEN SQLSTATE 'P0809' THEN
    NULL;
  END;
  IF NOT COALESCE((v_res->>'usable')::boolean, false) OR (v_res->>'folds')::int IS DISTINCT FROM v0.folds
     OR (v_res->>'examples')::int IS DISTINCT FROM v0.examples THEN
    RAISE EXCEPTION '0809 V2: after the change the model is not usable on the same evidence (% against usable, % folds, % '
                    'examples)', v_res, v0.folds, v0.examples;
  END IF;
  SELECT count(*) FILTER (WHERE (x->>'source') NOT IN ('learned', 'day_plan')
                             OR ((x->>'source') = 'day_plan') IS DISTINCT FROM
                                ((x->'cv'->>'rule_loss_kw')::numeric < (x->'cv'->>'loss_kw')::numeric)
                             OR (x->'cv'->>'loss_kw')::numeric > (x->'cv'->'loss_by_lam'->>'10')::numeric
                             OR jsonb_typeof(x->'cv'->'loss_by_lam') IS DISTINCT FROM 'object'
                             OR (SELECT count(*) FROM jsonb_object_keys(x->'cv'->'loss_by_lam')) <> 9),
         sum(LEAST((x->'cv'->>'loss_kw')::numeric, (x->'cv'->>'rule_loss_kw')::numeric)),
         sum((x->'cv'->'loss_by_lam'->>'10')::numeric),
         sum((x->'cv'->>'rule_loss_kw')::numeric),
         string_agg((x->>'h') || ':' || (x->>'source') || '@' || (x->>'lam'), ' ' ORDER BY (x->>'h')::int)
    INTO v_bad, v_sum, v_sum_base, v_sum_day, v_src
    FROM jsonb_array_elements(v_per) x;
  IF v_bad <> 0 OR v_sum > v_sum_base THEN
    RAISE EXCEPTION '0809 V2: % half hours whose record does not hold, or a summed loss % over the % at lam 10', v_bad, v_sum,
      v_sum_base;
  END IF;
  RAISE NOTICE '0809 V2: after the change % ; summed 0.8 pinball loss % kW against % at lam 10 and % for the day plan; %',
    v_res, v_sum, v_sum_base, v_sum_day, v_src;
END $v2$;

-- synthetic runs for V3: 15-second ticks for 4 1/2 hours from 8 AM CST, the EV draw a day level plus a daily wave plus
-- deterministic noise, and the features and the day plan's forecast as the case says. Dropped at the end.
CREATE FUNCTION pg_temp.ottoq_0809_synth(p_run uuid, p_t0 timestamptz, p_level double precision,
                                         p_decoy double precision, p_case text) RETURNS int
LANGUAGE plpgsql AS $f$
DECLARE k int; t timestamptz; v_ev double precision; v_m numeric[]; v_flat numeric[]; v_q numeric[]; v_rule numeric[];
        v_on numeric[];
BEGIN
  FOR k IN 1..1080 LOOP
    t := p_t0 + make_interval(secs => 15 * (k - 1));
    v_ev := p_level + 100 * sin(2 * pi() * (extract(epoch FROM t) / 3600.0) / 24) + 30 * sin(1000.0 * k);
    SELECT array_agg(round((p_level + 100 * sin(2 * pi() * (extract(epoch FROM t) / 3600.0 + (30 * hh + 15) / 60.0) / 24))::numeric, 0)
                     ORDER BY hh) INTO v_m FROM generate_series(0, 15) hh;
    v_flat := array_fill(500::numeric, ARRAY[16]);
    v_q := CASE WHEN p_case = 'c' THEN array_fill(round((p_decoy + 5 * sin(7.0 * k))::numeric, 0), ARRAY[16])
                ELSE array_fill(0::numeric, ARRAY[16]) END;
    v_on := CASE WHEN p_case = 'b' THEN v_m ELSE v_flat END;
    v_rule := CASE WHEN p_case = 'a' THEN v_m ELSE array_fill(2000::numeric, ARRAY[16]) END;
    INSERT INTO public.ottoq_bess_forecast_log (depot_id, sim_run_id, run_by, data_source, tick_seq, sim_clock,
           snapshot_at, ev_drawn_kw, site_base_kw, site_solar_kw, grid_kw, ev_persist_kw, on_charger_kw, known_kw,
           queue_kw, base_kw, solar_kw, rule_ev_kw)
    VALUES ('11111111-1111-1111-1111-111111111111', p_run, 'operator_demo', 'sim', k, t, t, v_ev, 50, 0, 50 + v_ev, 500,
            v_on, v_on, v_q, array_fill(50::numeric, ARRAY[16]), array_fill(0::numeric, ARRAY[16]), v_rule);
  END LOOP;
  RETURN 1080;
END $f$;

-- ── V3: the three synthetic cases ──
DO $v3$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  c_a CONSTANT uuid[] := ARRAY['00000000-0000-0000-0809-0000000000a1', '00000000-0000-0000-0809-0000000000a2',
                               '00000000-0000-0000-0809-0000000000a3']::uuid[];
  c_b CONSTANT uuid[] := ARRAY['00000000-0000-0000-0809-0000000000b1', '00000000-0000-0000-0809-0000000000b2',
                               '00000000-0000-0000-0809-0000000000b3']::uuid[];
  c_c CONSTANT uuid[] := ARRAY['00000000-0000-0000-0809-0000000000c1', '00000000-0000-0000-0809-0000000000c2',
                               '00000000-0000-0000-0809-0000000000c3']::uuid[];
  c_day CONSTANT timestamptz[] := ARRAY['2026-02-02 14:00+00', '2026-02-03 14:00+00', '2026-02-04 14:00+00']::timestamptz[];
  c_level CONSTANT double precision[] := ARRAY[400, 700, 1000];
  v_res jsonb; v_per jsonb; v_n int; v_sum numeric; v_sum_base numeric; v_note text := '';
  i int;
BEGIN
  BEGIN
    -- (a) the day plan knows the day's level, the features do not
    FOR i IN 1..3 LOOP PERFORM pg_temp.ottoq_0809_synth(c_a[i], c_day[i], c_level[i], 0, 'a'); END LOOP;
    v_res := public.ottoq_bess_forecast_refit(c_twin, 0.8, 10, '28 days', '0809 V3 (rolled back)', c_a, 'run_day');
    SELECT per_half_hour INTO v_per FROM public.ottoq_bess_forecast_models WHERE model_id = (v_res->>'model_id')::bigint;
    SELECT count(*) FILTER (WHERE x->>'source' = 'day_plan') INTO v_n FROM jsonb_array_elements(v_per) x;
    IF NOT (v_res->>'usable')::boolean OR v_n <> 8 THEN
      RAISE EXCEPTION '0809 V3 (a): the day plan knew the level and the record defers to it at % of 8 half hours (%)', v_n, v_res;
    END IF;
    v_note := v_note || format('(a) day_plan at %s of 8; ', v_n);
    -- (b) the features know, the day plan is blind
    FOR i IN 1..3 LOOP PERFORM pg_temp.ottoq_0809_synth(c_b[i], c_day[i] + interval '7 days', c_level[i], 0, 'b'); END LOOP;
    v_res := public.ottoq_bess_forecast_refit(c_twin, 0.8, 10, '28 days', '0809 V3 (rolled back)', c_b, 'run_day');
    SELECT per_half_hour INTO v_per FROM public.ottoq_bess_forecast_models WHERE model_id = (v_res->>'model_id')::bigint;
    SELECT count(*) FILTER (WHERE x->>'source' = 'learned' AND (x->>'lam')::numeric <= 1000) INTO v_n
      FROM jsonb_array_elements(v_per) x;
    IF NOT (v_res->>'usable')::boolean OR v_n <> 8 THEN
      RAISE EXCEPTION '0809 V3 (b): the features knew the level and the record keeps the model at lam <= 10^3 at % of 8 half '
                      'hours (%)', v_n, v_res;
    END IF;
    v_note := v_note || format('(b) learned at lam <= 10^3 at %s of 8; ', v_n);
    -- (c) a decoy: the queue carries a level per day unrelated to the EV level; the day plan is blind
    FOR i IN 1..3 LOOP
      PERFORM pg_temp.ottoq_0809_synth(c_c[i], c_day[i] + interval '14 days', (ARRAY[600, 700, 800])[i],
                                       (ARRAY[100, 0, 50])[i], 'c');
    END LOOP;
    v_res := public.ottoq_bess_forecast_refit(c_twin, 0.8, 10, '28 days', '0809 V3 (rolled back)', c_c, 'run_day');
    SELECT per_half_hour INTO v_per FROM public.ottoq_bess_forecast_models WHERE model_id = (v_res->>'model_id')::bigint;
    SELECT count(*) FILTER (WHERE (x->>'lam')::numeric > 10), sum((x->'cv'->>'loss_kw')::numeric),
           sum((x->'cv'->'loss_by_lam'->>'10')::numeric)
      INTO v_n, v_sum, v_sum_base FROM jsonb_array_elements(v_per) x;
    IF NOT (v_res->>'usable')::boolean OR v_n <> 8 OR v_sum >= 0.8 * v_sum_base THEN
      RAISE EXCEPTION '0809 V3 (c): with a decoy the regularization is heavier than lam 10 at % of 8 half hours and the summed '
                      'loss is % against % at lam 10 (%)', v_n, v_sum, v_sum_base, v_res;
    END IF;
    v_note := v_note || format('(c) heavier than lam 10 at %s of 8, summed loss %s kW against %s at lam 10', v_n, v_sum, v_sum_base);
    RAISE NOTICE '0809 V3: %', v_note;
    RAISE EXCEPTION USING ERRCODE = 'P0809', MESSAGE = 'roll back the synthetic ticks';
  EXCEPTION WHEN SQLSTATE 'P0809' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_log WHERE sim_run_id = ANY(c_a || c_b || c_c))
     OR EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_models WHERE note = '0809 V3 (rolled back)') THEN
    RAISE EXCEPTION '0809 V3: the synthetic rows were not rolled back';
  END IF;
END $v3$;

-- ── V4: the evaluator reads the day plan where the record says so ──
DO $v4$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_id bigint; v_f jsonb; v_per jsonb; v_bad int;
BEGIN
  BEGIN
    SELECT jsonb_agg(jsonb_build_object('h', h, 'n', 600, 'folds', 3,
                                        'mu', to_jsonb(array_fill(0::double precision, ARRAY[9])),
                                        'sd', to_jsonb(array_fill(1::double precision, ARRAY[9])),
                                        'w', to_jsonb(ARRAY[300::double precision] || array_fill(0::double precision, ARRAY[9])),
                                        'offset_kw', 50, 'lam', 10, 'rule_offset_kw', 100,
                                        'source', CASE WHEN h % 2 = 0 THEN 'day_plan' ELSE 'learned' END,
                                        'cv', jsonb_build_object('n', 600, 'folds', 3)) ORDER BY h)
      INTO v_per FROM generate_series(0, 7) h;
    INSERT INTO public.ottoq_bess_forecast_models (depot_id, note, usable, quantile, lam, fold_by, runs, n_folds, n_examples,
           features, per_half_hour, profile)
    VALUES (c_twin, '0809 V4 (rolled back)', false, 0.8, 10, 'run_day', ARRAY[]::uuid[], 3, 4800,
            ARRAY['1', 'on_charger', 'arrivals', 'queue', 'last_hour', 'base', 'solar', 'sin_hour', 'cos_hour',
                  'rule_without_arrivals'], v_per, '[]'::jsonb)
    RETURNING model_id INTO v_id;
    v_f := public.ottoq_bess_learned_forecast('00000000-0000-0000-0809-0000000000e1', c_twin, '2026-02-02 15:00+00',
             jsonb_build_object('ok', true, 'ev_persist_kw', 500,
               'forecast', jsonb_build_object('ev_kw', to_jsonb(array_fill(1000, ARRAY[16])),
                                              'ev_known_kw', to_jsonb(array_fill(500, ARRAY[16])),
                                              'ev_queue_kw', to_jsonb(array_fill(0, ARRAY[16])),
                                              'base_kw', to_jsonb(array_fill(50, ARRAY[16])),
                                              'solar_kw', to_jsonb(array_fill(0, ARRAY[16])))),
             v_id);
    SELECT count(*) INTO v_bad FROM generate_series(0, 7) h
     WHERE (v_f->'ev_mean_kw'->>h)::numeric IS DISTINCT FROM (CASE WHEN h % 2 = 0 THEN 1000 ELSE 300 END)
        OR (v_f->'ev_upper_kw'->>h)::numeric IS DISTINCT FROM (CASE WHEN h % 2 = 0 THEN 1100 ELSE 350 END)
        OR (v_f->'pre_upper_kw'->>h)::numeric IS DISTINCT FROM (CASE WHEN h % 2 = 0 THEN 1150 ELSE 400 END)
        OR v_f->'source'->>h IS DISTINCT FROM (CASE WHEN h % 2 = 0 THEN 'day_plan' ELSE 'learned' END);
    IF v_bad <> 0 THEN
      RAISE EXCEPTION '0809 V4: the evaluator read % of 8 half hours wrong: %', v_bad, v_f;
    END IF;
    RAISE NOTICE '0809 V4: ev_mean % ev_upper % source %', v_f->'ev_mean_kw', v_f->'ev_upper_kw', v_f->'source';
    RAISE EXCEPTION USING ERRCODE = 'P0809', MESSAGE = 'roll back the synthetic model';
  EXCEPTION WHEN SQLSTATE 'P0809' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_models WHERE note = '0809 V4 (rolled back)') THEN
    RAISE EXCEPTION '0809 V4: the synthetic model was not rolled back';
  END IF;
END $v4$;

-- ── V5: the patched bodies are byte for byte the ones the research lab ran ──
DO $v5$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure)
     IS DISTINCT FROM '8c8c7e73bb7749c2b2ad3af47d28377a' THEN
    RAISE EXCEPTION '0809 V5: the patched refit is not the one the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc
        WHERE oid = 'public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure);
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_bess_learned_forecast(uuid,uuid,timestamptz,jsonb,bigint)'::regprocedure)
     IS DISTINCT FROM 'c28dd8e88706a812e51ad011c4523a44' THEN
    RAISE EXCEPTION '0809 V5: the patched evaluator is not the one the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc
        WHERE oid = 'public.ottoq_bess_learned_forecast(uuid,uuid,timestamptz,jsonb,bigint)'::regprocedure);
  END IF;
END $v5$;

DROP FUNCTION pg_temp.ottoq_0809_synth(uuid, timestamptz, double precision, double precision, text);

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0809_the_battery_forecast_is_shrunk_as_far_as_its_own_misses_say_and_defers_to_the_day_plan_where_that_misses_less',
        false, false,
        'G530. ottoq_bess_forecast_refit reads each fold''s misses at nine regularizations (p_lam x 10^0..10^8) and at each '
        'half hour fits at the one whose band had the least pinball loss out of sample; the day plan''s own EV forecast is '
        'graded on the same misses, and where it missed less the record says source day_plan and '
        'ottoq_bess_learned_forecast reads it there. A run reads a model only where bess_planner_enabled is 1 (the twin '
        'depot since 2026-11-07 11:43:39 UTC); certification is off (rule 12).',
        now());

COMMIT;
