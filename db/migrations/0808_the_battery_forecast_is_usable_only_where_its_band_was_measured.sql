-- migration-version: PENDING
-- migration-name:    the_battery_forecast_is_usable_only_where_its_band_was_measured
--
-- 0808  **The battery's forecast is usable only where its band was measured.** (G529; B1, the production battery planner)
--
-- ══ §0 WHY NOW ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0803 (applied 2026-11-06 17:53:21 UTC) learns the depot's load forecast from its own days: one row per tick in
--   ottoq_bess_forecast_log, and a nightly refit (cron 802, 5:26 AM CT) that writes a model the planner may read once it
--   is usable. The first demo run since then (640e4fab, 2026-11-06 19:14-20:59 UTC, 5.26 sim-hours) logged 1,249 rows for
--   1,249 ticks. That run is one fold, and the usable bar wants three, so the next two demo runs decide when the first
--   usable model appears. Read against that, the bar would call a model usable whose band at the longer half hours was
--   never measured, if those runs are short (G529). No model has been written yet (0 rows, read 21:07:59 UTC), and
--   the planner is off, so nothing has acted on this; this file fixes it before the first model is judged.
--
-- ══ §1 WHAT IS WRONG (FINDINGS G529) ═════════════════════════════════════════════════════════════════════════════════
--
--   A model's upper band at h half hours ahead is the p_quantile of the out-of-sample misses at h: each fold's examples
--   graded by a fit on the other folds. A fold has examples at h only where its run went on 30h + 30 minutes past the
--   example's clock (6 snapshots in that half hour), so a short run reaches the first half hours only. The bar counts
--   folds over all half hours (3) and examples per half hour (200), but never folds per half hour. A half hour that one
--   fold reached therefore has no left-out fit (under 10 examples once that fold is left out), so it has no misses, and
--   its band is COALESCE(NULL, 0) = 0 kW. The point forecast is then stored as the upper band, with cv.n = 0, and the
--   model is still called usable. The planner reads that band as its forecast for the next 4 hours (0804).
--   In the research lab, ottoq_lab with production's refit (prosrc md5 06e7c6cb): three synthetic runs at 15-second ticks,
--   one of 6 hours and two of 1 hour, on three days. The refit returned usable, 3 folds, 8,808 examples. At 1 to 4 hours
--   ahead (h = 2..7) it had 0 out-of-sample misses and a band of 0.0 kW.
--   Production's first run reached every half hour ahead (h = 7: 478 examples, the last from 9:43 AM CT sim). The
--   defect depends on how long the next runs are, not on this one.
--
-- ══ §2 WHAT THIS CHANGES (one function, four anchored edits; no decision reads a model while bess_planner_enabled is 0) ═
--
--   ottoq_bess_forecast_refit:
--   (1) usable also needs, at every half hour ahead, the band read from the out-of-sample misses of 3 folds, at least
--       200 of them. A model that misses the bar is still written, as not usable, as a model with too few folds is
--       today.
--   (2) each half hour's record gains 'folds' (the folds with examples there), and its cv gains 'folds' (the folds
--       graded out of sample there). Nothing reads them but people. ottoq_bess_learned_forecast reads h, mu, sd, w and
--       offset_kw by name.
--   (3) its comment says so.
--   ottoq_bess_forecast_models is append-only. A model judged under the old bar could not be re-judged, and as the
--   latest usable model it would stay in use. P1 therefore refuses while any usable model exists at the twin depot.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1: not applied; 0803 applied; the refit is the body 0803 left (prosrc md5 06e7c6cb, read
--   2026-11-06 21:04 UTC); no usable forecast model at the twin depot. Pre-image to ottoq_schema_snapshots as
--   '0808_pre'. Each anchor matches once.
--   V0 (before the change, on production's own body): the synthetic runs of §1 are inserted under fixed synthetic run
--   ids, refit, and rolled back. The model is usable, with 0 misses and a band of 0 at h = 2..7. This is the defect,
--   shown where it lives.
--   V1 the body less its changes is its pre-image.
--   V2 the same runs, rolled back. Not usable, with cv.folds 0 at h = 2..7. Three runs of 4 1/2 hours are usable, with
--   every half hour graded by 3 folds.
--   V3 the patched body is byte for byte the one the lab ran (md5 a142840c).
--   In the research lab (2026-11-06 21:08-21:12 UTC):
--   (a) on the six 36-hour lab days (ottoq_lab_0803m), the refit is usable before and after, with the same 19,440
--       examples, the same profile, and 0 of 8 half hours differing apart from the two new keys. This holds folded by
--       run's day (12 folds) and by run (6). Every half hour was graded by every fold, with at least 2,304 misses.
--   (b) the synthetic cases V0 and V2 run.
--   (c) a run of exactly 4 hours still reaches h = 7: 6 snapshots into (clock + 3 1/2 h, clock + 4 h] need only the
--       run's first half hour of clocks.
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: the refit runs from cron 802 and by hand, and no certified arm
--   reads a model (bess_planner_enabled is 0 by default and in every arm).
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0808_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0808_the_battery_forecast_is_usable_only_where_its_band_was_measured'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0808 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0808_the_battery_forecast_is_usable_only_where_its_band_was_measured') THEN
    RAISE EXCEPTION '0808 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0803_the_battery_learns_its_load_forecast_from_the_depots_own_days') THEN
    RAISE EXCEPTION '0808 P1: 0803 (the learned forecast and its refit) comes first';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'))
     IS DISTINCT FROM '06e7c6cbd5c120d7a45de985186fb41a' THEN
    RAISE EXCEPTION '0808 P1: public.ottoq_bess_forecast_refit is not the body 0803 left (06e7c6cb)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_models
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND usable) THEN
    RAISE EXCEPTION '0808 P1: a usable forecast model exists at the twin depot, judged under the old bar; the models are '
                    'append-only, so it would stay the latest usable one. Re-judge it by hand before this file';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0808_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure;

-- the synthetic demo-like runs V0 and V2 refit: 15-second ticks, a daily EV wave with deterministic noise, and as
-- features the half hour's own mean ahead (a near-perfect predictor), as 0803 V3 builds them. Dropped at the end.
CREATE FUNCTION pg_temp.ottoq_0808_synth(p_run uuid, p_t0 timestamptz, p_ticks int) RETURNS int
LANGUAGE plpgsql AS $f$
DECLARE k int; t timestamptz; v_ev double precision; v_m numeric[];
BEGIN
  FOR k IN 1..p_ticks LOOP
    t := p_t0 + make_interval(secs => 15 * (k - 1));
    v_ev := 500 + 300 * sin(2 * pi() * (extract(epoch FROM t) / 3600.0) / 24) + 60 * sin(1000.0 * k + length(p_run::text));
    SELECT array_agg(round((500 + 300 * sin(2 * pi() * (extract(epoch FROM t) / 3600.0 + (30 * hh + 15) / 60.0) / 24))::numeric, 0)
                     ORDER BY hh) INTO v_m FROM generate_series(0, 15) hh;
    INSERT INTO public.ottoq_bess_forecast_log (depot_id, sim_run_id, run_by, data_source, tick_seq, sim_clock,
           snapshot_at, ev_drawn_kw, site_base_kw, site_solar_kw, grid_kw, ev_persist_kw, on_charger_kw, known_kw,
           queue_kw, base_kw, solar_kw, rule_ev_kw)
    VALUES ('11111111-1111-1111-1111-111111111111', p_run, 'operator_demo', 'sim', k, t, t, v_ev, 50, 0, 50 + v_ev, v_ev,
            v_m, v_m, array_fill(0::numeric, ARRAY[16]), array_fill(50::numeric, ARRAY[16]),
            array_fill(0::numeric, ARRAY[16]), v_m);
  END LOOP;
  RETURN p_ticks;
END $f$;

-- ── V0: the defect, on production's own body ──
DO $v0$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  c_runs CONSTANT uuid[] := ARRAY['00000000-0000-0000-0808-0000000000a1', '00000000-0000-0000-0808-0000000000a2',
                                  '00000000-0000-0000-0808-0000000000a3']::uuid[];
  v_res jsonb; v_m record; v_bad int;
BEGIN
  BEGIN
    PERFORM pg_temp.ottoq_0808_synth(c_runs[1], '2026-01-05 14:00+00', 1440);   -- 6 hours from 8 AM CST
    PERFORM pg_temp.ottoq_0808_synth(c_runs[2], '2026-01-06 14:00+00', 240);    -- 1 hour
    PERFORM pg_temp.ottoq_0808_synth(c_runs[3], '2026-01-07 14:00+00', 240);    -- 1 hour
    v_res := public.ottoq_bess_forecast_refit(c_twin, 0.8, 10, '28 days', '0808 V0 (rolled back)', c_runs, 'run_day');
    SELECT * INTO v_m FROM public.ottoq_bess_forecast_models WHERE model_id = (v_res->>'model_id')::bigint;
    SELECT count(*) INTO v_bad FROM jsonb_array_elements(v_m.per_half_hour) x
     WHERE (x->>'h')::int >= 2 AND (x->'cv'->>'n')::int = 0 AND (x->>'offset_kw')::numeric = 0;
    IF NOT v_m.usable OR v_m.n_folds <> 3 OR v_bad <> 6 THEN
      RAISE EXCEPTION '0808 V0: the old bar did not show the defect (usable %, folds %, half hours with no misses and no '
                      'band at h >= 2: % of 6)', v_m.usable, v_m.n_folds, v_bad;
    END IF;
    RAISE NOTICE '0808 V0: before the change, % (6 of 6 half hours at h >= 2 with no misses and a band of 0)', v_res;
    RAISE EXCEPTION USING ERRCODE = 'P0808', MESSAGE = 'roll back the synthetic ticks';
  EXCEPTION WHEN SQLSTATE 'P0808' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_log WHERE sim_run_id = ANY(c_runs))
     OR EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_models WHERE note = '0808 V0 (rolled back)') THEN
    RAISE EXCEPTION '0808 V0: the synthetic rows were not rolled back';
  END IF;
END $v0$;

CREATE TEMP TABLE _0808_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0808_patch VALUES
(1,
$o$   runs by p_run_by logged within p_window. Usable with 3 folds and 200 examples at every h ahead. An estimate (rule 10). */$o$,
$n$   runs by p_run_by logged within p_window. Usable with 3 folds and 200 examples at every h ahead, and (0808) with the band
   at every h read from the out-of-sample misses of 3 folds, 200 of them: a half hour that no left-out fold reached has
   no band, and a model without one is not usable. An estimate (rule 10). */$n$),
(2,
$o$      'h', r.h, 'n', r.n::int, 'mu', to_jsonb(v_fit.mu), 'sd', to_jsonb(v_fit.sd), 'w', to_jsonb(v_fit.w),$o$,
$n$      'h', r.h, 'n', r.n::int, 'folds', (SELECT count(DISTINCT fold) FROM _bf_ex WHERE h = r.h),
      'mu', to_jsonb(v_fit.mu), 'sd', to_jsonb(v_fit.sd), 'w', to_jsonb(v_fit.w),$n$),
(3,
$o$      'cv', (SELECT jsonb_build_object('n', count(*), 'mae_kw', round(avg(abs(yhat - y))::numeric, 1),$o$,
$n$      'cv', (SELECT jsonb_build_object('n', count(*), 'folds', count(DISTINCT fold), 'mae_kw', round(avg(abs(yhat - y))::numeric, 1),$n$),
(4,
$o$              AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_per) x WHERE x->'w' = 'null'::jsonb);$o$,
$n$              AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_per) x WHERE x->'w' = 'null'::jsonb)
              -- 0808 (G529): and at every half hour ahead the band was read out of sample, from 3 folds' misses, 200 of them
              AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_per) x
                               WHERE COALESCE((x->'cv'->>'folds')::int, 0) < 3 OR COALESCE((x->'cv'->>'n')::int, 0) < 200);$n$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure);
  FOR p IN SELECT * FROM _0808_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0808: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0808: the refit is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the body less its changes is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  v_body := (SELECT prosrc FROM pg_proc
              WHERE oid = 'public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure);
  FOR p IN SELECT * FROM _0808_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '06e7c6cbd5c120d7a45de985186fb41a' THEN
    RAISE EXCEPTION '0808 V1: the refit less its changes is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the same runs after the change, and three runs long enough to reach every half hour ahead ──
DO $v2$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  c_short CONSTANT uuid[] := ARRAY['00000000-0000-0000-0808-0000000000a1', '00000000-0000-0000-0808-0000000000a2',
                                   '00000000-0000-0000-0808-0000000000a3']::uuid[];
  c_long CONSTANT uuid[] := ARRAY['00000000-0000-0000-0808-0000000000c1', '00000000-0000-0000-0808-0000000000c2',
                                  '00000000-0000-0000-0808-0000000000c3']::uuid[];
  v_a jsonb; v_c jsonb; v_ma record; v_mc record; v_bad int; v_graded int;
BEGIN
  BEGIN
    PERFORM pg_temp.ottoq_0808_synth(c_short[1], '2026-01-05 14:00+00', 1440);
    PERFORM pg_temp.ottoq_0808_synth(c_short[2], '2026-01-06 14:00+00', 240);
    PERFORM pg_temp.ottoq_0808_synth(c_short[3], '2026-01-07 14:00+00', 240);
    v_a := public.ottoq_bess_forecast_refit(c_twin, 0.8, 10, '28 days', '0808 V2 (rolled back)', c_short, 'run_day');
    SELECT * INTO v_ma FROM public.ottoq_bess_forecast_models WHERE model_id = (v_a->>'model_id')::bigint;
    SELECT count(*) INTO v_bad FROM jsonb_array_elements(v_ma.per_half_hour) x
     WHERE (x->>'h')::int >= 2 AND (x->'cv'->>'folds')::int = 0 AND (x->>'folds')::int = 1;
    IF v_ma.usable OR v_bad <> 6 THEN
      RAISE EXCEPTION '0808 V2: one long run and two short ones are usable (%), or the record does not say why (% of 6 half '
                      'hours at h >= 2 with one fold and none graded)', v_ma.usable, v_bad;
    END IF;
    PERFORM pg_temp.ottoq_0808_synth(c_long[1], '2026-02-02 14:00+00', 1080);   -- 4 1/2 hours from 8 AM CST
    PERFORM pg_temp.ottoq_0808_synth(c_long[2], '2026-02-03 14:00+00', 1080);
    PERFORM pg_temp.ottoq_0808_synth(c_long[3], '2026-02-04 14:00+00', 1080);
    v_c := public.ottoq_bess_forecast_refit(c_twin, 0.8, 10, '28 days', '0808 V2 (rolled back)', c_long, 'run_day');
    SELECT * INTO v_mc FROM public.ottoq_bess_forecast_models WHERE model_id = (v_c->>'model_id')::bigint;
    SELECT count(*) INTO v_graded FROM jsonb_array_elements(v_mc.per_half_hour) x
     WHERE (x->'cv'->>'folds')::int = 3 AND (x->'cv'->>'n')::int >= 200 AND (x->>'folds')::int = 3;
    IF NOT v_mc.usable OR v_graded <> 8 THEN
      RAISE EXCEPTION '0808 V2: three runs of 4 1/2 hours are not usable (%), or not every half hour was graded by 3 folds '
                      '(% of 8)', v_mc.usable, v_graded;
    END IF;
    RAISE NOTICE '0808 V2: one long run and two short ones %; three of 4 1/2 hours %', v_a, v_c;
    RAISE EXCEPTION USING ERRCODE = 'P0808', MESSAGE = 'roll back the synthetic ticks';
  EXCEPTION WHEN SQLSTATE 'P0808' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_log WHERE sim_run_id = ANY(c_short || c_long))
     OR EXISTS (SELECT 1 FROM public.ottoq_bess_forecast_models WHERE note = '0808 V2 (rolled back)') THEN
    RAISE EXCEPTION '0808 V2: the synthetic rows were not rolled back';
  END IF;
END $v2$;

-- ── V3: the patched body is byte for byte the one the research lab ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure)
     IS DISTINCT FROM 'a142840ca1fd8c5e787c76a19936d3ab' THEN
    RAISE EXCEPTION '0808 V3: the patched refit is not the one the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc
        WHERE oid = 'public.ottoq_bess_forecast_refit(uuid,numeric,numeric,interval,text,uuid[],text,text[])'::regprocedure);
  END IF;
END $v3$;

DROP FUNCTION pg_temp.ottoq_0808_synth(uuid, timestamptz, int);

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0808_the_battery_forecast_is_usable_only_where_its_band_was_measured', false, false,
        'G529. ottoq_bess_forecast_refit calls a model usable only when, at every half hour ahead, its band was read from '
        'the out-of-sample misses of 3 folds, 200 of them; a half hour one fold reached had a band of 0 and still passed. '
        'Each half hour records its folds. No certified arm reads a model (bess_planner_enabled is 0).',
        now());

COMMIT;
