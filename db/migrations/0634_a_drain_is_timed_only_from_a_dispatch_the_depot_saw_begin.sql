-- migration-version: 20261009102518
-- migration-name:    a_drain_is_timed_only_from_a_dispatch_the_depot_saw_begin
--
-- 0634  **A car's drain is timed only from a dispatch the depot saw begin.**
--       The return fit learns how fast each class of car drains from its reserve returns: the battery a car left with,
--       the battery at its recall, over the minutes between. A run's first cars are already at work when it starts: the
--       twin primes them with a dispatch back-dated part of the way into its trip (twin.ottoq_sim_prime_deployment's
--       stagger) and sets their battery at the start, so their drain counted the back-dated minutes as driving and came
--       out slow. A quarter of the fit's reserve returns were such cars, the futures drained every car too slowly, and
--       cars came home early, the more so the further ahead. 0634 times a drain only from a dispatch the depot saw begin,
--       counts a car's work (the exposure for other calls home) only from when the depot saw it, and the arrival spread
--       reads the orders made with this drain once there are enough of them.
--
-- ══ §1 WHY (measured 2026-10-09 06:55-07:45 UTC, 1:55-2:45 AM CT) ═══════════════════════════════════════════════════════
--
--   (a) G371's long-horizon early bias (check 0423 §3; 0633 §1(d)): on b2efcc07 cars come home early by about 2% of the
--       horizon past 30 minutes (median -1.24 minutes past 60). It is not the order's window cutting late arrivals off:
--       with 20 minutes of the window to spare, the median is still -0.56, -0.93 and -1.17 minutes at 30-45, 45-60 and
--       60-75.
--   (b) It is the drain. From the battery at each order (the forecast's matches telemetry to 0.07 points) to the recall,
--       cars drained 1.0235 times the forecast's rate (median of 3,605 forecasts, about the same at every horizon), and
--       within each dispatch the last 15 minutes ran 3.2% faster than the first 15 by the battery at dispatched_at. The
--       telemetry says why: 30 of the run's 95 reserve returns have no reading for more than a minute after
--       dispatched_at (p90 12 minutes, max 43), and their battery falls half a point across that gap against 4 to 32
--       points expected. They are the run's primed cars: dispatched_at back-dated by the stagger, soc_at_dispatch_pct
--       the battery at the start, and every one's first reading on the run's first tick. Where the first reading comes
--       within half a minute, the drain from telemetry and from the dispatch agree (ratio 1.0006).
--   (c) In the fit, through b2efcc07's start (a fit through a past moment, G367): 345 of 1,422 timed reserve returns
--       (24%) began before their run's start. Without them the depot's drain is 0.7264%/min against 0.7160, its log
--       spread 0.066 against 0.092, and the classes' +0.9% (Zoox, 0.6476 -> 0.6534), +1.0% (Waymo, 0.7191 -> 0.7260)
--       and +1.4% (Tesla, 0.7474 -> 0.7575). Other calls home per hour of work 0.1086 -> 0.1132: the back-dated minutes
--       had counted as exposure.
--   (d) Out of sample on b2efcc07, its 3,703 graded forecast arrivals re-forecast at each car's drain from that fit
--       (the fit before the change reproduces the forecasts' drain exactly: ratio 1.0000, error unchanged): mean
--       absolute error 1.371 -> 1.266 minutes; median error 10-30 minutes -0.32 -> -0.13, 30-60 -0.76 -> -0.34, past 60
--       -1.35 -> -0.76; under 10 minutes 0.467 -> 0.472.
--   (e) What is left, +1.0% in rate and -0.76 minutes past 60: b2efcc07 ran at 25-30 C, and the twin's climate control
--       draws 0.15 kW a degree above 27 C (twin.ottoq_sim_compute_discharge_rate), about 1.4% of a car's draw at 30 C.
--       The drain does not read the air yet; named as the next build, not built here.
--   (f) The twin's prime stays as it is: a car already at work when tracking begins is what production sees at
--       go-live too, and the fit must read it right whatever wrote it. A dispatch's start is seen when it began at or
--       after its run's start (sim_clock_start); one that began before is not timed, and its work counts from the start.
--   (g) The arrival spread (0633) is the errors of the forecast as it stands. Its fit now reads the orders made by the
--       newest forecast among them (the return model's forecast_v, 1 before this file, 2 from it) once they alone give a
--       usable spread, and every order until then, so the drain's change reaches the spread as soon as it can.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) ottoq_return_model_params: a reserve return whose dispatch began before its run's start times no drain; every
--       return's work counts from the later of its dispatch and its run's start; the fit carries `forecast_v` 2 and
--       `n_primed`, the reserve returns that began before their run's start. Every other key is 0633's.
--   (b) ottoq_return_arrival_fit: reads the orders made by the newest forecast among them once they alone are usable
--       (4 bins, 30 returns), else every order, as 0633; it says which (`forecast_v`, `forecast_v_newest`).
--   (c) ottoq_fit_return_model: its code_md5 covers what the fit reads for the arrival spread (ottoq_return_arrival_fit
--       and ottoq_variance_curve_fit, 0633).
--   (d) The self-review: orders made with a return model before forecast_v 2, graded once the depot's has it, are
--       history for the arrivals (built), and it says so.
--   (e) return_v1 is refitted here.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running, no return fit running. P1 the four bodies are the ones 0633 left, 0633 is
--   applied, this file has not been. V1 each change by meaning in the stored definitions. V2 the gate, out of sample:
--   on the latest run with 20 graded orders or more forecasting cars by 0628's drain (b2efcc07 today; c4ee1572, the
--   production session's smoke test, has 2), the fit through its first order before the change and after it; each
--   forecast re-made at its car's drain from each; the mean absolute error no worse (within 0.5%) and the median error
--   past 30 minutes no further from zero. V3 the refit. V4 the self-review reads it. Executed by
--   tests/test_agent_drain_seen_sql.py on the miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0627, 0628 and 0633: the return model is read by the check on
--   an agent's charge order and the agent's board; no kernel decision, dial or seat reads it, and no certification arm
--   runs the agent or the charge order (0615). No dial: the drain read from back-dated minutes was a defect in the
--   evidence, not a choice (as 0630's run stop).
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0634_pre' AND object_kind = 'function',
--   then refit return_v1 (SELECT public.ottoq_fit_return_model('11111111-1111-1111-1111-111111111111')); the fit appended
--   here stays (evidence); DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0634_a_drain_is_timed_only_from_a_dispatch_the_depot_saw_begin'.

BEGIN;

-- ── P0: nothing in flight, no run running, no return fit running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0634 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0634 P0: a run is running; its check reads the forecast this changes. Apply between runs';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE pid <> pg_backend_pid() AND state = 'active' AND query ~ 'ottoq_fit_return_model\(') THEN
    RAISE EXCEPTION '0634 P0: a return fit is running (the nightly refit); apply after it';
  END IF;
END $inflight$;

-- ── P1: the bodies are the ones 0633 left; 0633 is applied; this file has not been ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)',                        '624b19d11ea621b00fa01677a16a3663'),
    ('public.ottoq_return_arrival_fit(uuid,timestamp with time zone,timestamp with time zone)',         '7e47919689ade4f80d5880480ecd34a4'),
    ('public.ottoq_fit_return_model(uuid,timestamp with time zone,interval,text)',                      '05f61d707a23cf26a39126289ae9a4b5'),
    ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)',                  'b52aac690bae3b77fb041c2849c18654'))
    AS t(sig, src_md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0634 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_variance_curve_fit(double precision[],double precision[],double precision[])') IS NULL THEN
    RAISE EXCEPTION '0634 P1: 0633 comes first (the arrival spread this reads)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0634_a_drain_is_timed_only_from_a_dispatch_the_depot_saw_begin') THEN
    RAISE EXCEPTION '0634 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0634_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)'::regprocedure,
                 'public.ottoq_return_arrival_fit(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure,
                 'public.ottoq_fit_return_model(uuid,timestamp with time zone,interval,text)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure);

-- what V2 compares against: the latest run with 20 graded orders or more that forecast cars by 0628's drain, the moment
-- of its first order, and the fit through that moment as it stood
CREATE TEMP TABLE _0634_gate ON COMMIT DROP AS
SELECT x.run, x.through,
       public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111', x.through, interval '21 days') AS p_old
  FROM (SELECT s.sim_run_id AS run, min(s.recorded_at) AS through
          FROM public.ottoq_charge_order_grades h
          JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
         WHERE h.depot_id = '11111111-1111-1111-1111-111111111111' AND jsonb_path_exists(s.state, '$.inbound[*].dr')
         GROUP BY s.sim_run_id
        HAVING count(DISTINCT s.order_id) >= 20                    -- a run's worth, not a smoke test's two orders
         ORDER BY max(s.recorded_at) DESC
         LIMIT 1) x;

-- ══ (a) (c) (d) the anchored patches: each anchor once, the stored definition after ═══════════════════════════════════════
CREATE TEMP TABLE _0634_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

INSERT INTO _0634_patch VALUES
('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', 1,
$old$   walk and drift fitted to it. Every other key is 0628's. */$old$,
$new$   walk and drift fitted to it. Every other key is 0628's.
   0634: a drain is timed only from a dispatch the depot saw begin: a reserve return whose dispatch began before its
   run's start (a car already at work when the run began, its dispatch back-dated and its battery set at the start)
   times none, and every return's work counts from the later of its dispatch and its run's start. And `forecast_v` 2,
   the forecast's version for the arrival spread (ottoq_return_arrival_fit), and `n_primed`, the reserve returns that
   began before their run's start. Every other key is 0633's. */$new$),
('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', 2,
$old$           extract(epoch FROM (x.returning_started_at - x.dispatched_at)) / 60.0 AS work_min,$old$,
$new$           -- 0634: the work the depot saw: from the dispatch, or from the run's start for a car already out then
           extract(epoch FROM (x.returning_started_at - GREATEST(x.dispatched_at, x.run_start))) / 60.0 AS work_min,
           COALESCE(x.dispatched_at < x.run_start, false) AS primed,                                    -- 0634$new$),
('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', 3,
$old$                   d.actual_return_at,
$old$,
$new$                   d.actual_return_at, r.sim_clock_start AS run_start,                                      -- 0634
$new$),
('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', 4,
$old$    SELECT vehicle_id, ln(((soc0 - soc_dec) / work_min)::float8) AS ld FROM low WHERE work_min >= 5 AND soc0 > soc_dec$old$,
$new$    -- 0634: a drain is timed only from a dispatch the depot saw begin
    SELECT vehicle_id, ln(((soc0 - soc_dec) / work_min)::float8) AS ld FROM low
     WHERE work_min >= 5 AND soc0 > soc_dec AND NOT primed$new$),
('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', 5,
$old$           'n_drain', (SELECT count(*) FROM drain),$old$,
$new$           'n_drain', (SELECT count(*) FROM drain),
           'n_primed', (SELECT count(*) FROM low WHERE primed),                                         -- 0634$new$),
('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', 6,
$old$                                      'arrival', public.ottoq_return_arrival_fit(p_depot, v_from, v_through));   -- 0633$old$,
$new$                                      'arrival', public.ottoq_return_arrival_fit(p_depot, v_from, v_through),    -- 0633
                                      'forecast_v', 2);                                                          -- 0634$new$),
('public.ottoq_fit_return_model(uuid,timestamp with time zone,interval,text)', 1,
$old$              || pg_get_functiondef('public.ottoq_return_model_params(uuid,timestamptz,interval)'::regprocedure)),$old$,
$new$              || pg_get_functiondef('public.ottoq_return_model_params(uuid,timestamptz,interval)'::regprocedure)
              -- 0634: and what it reads for the arrival spread (0633)
              || pg_get_functiondef('public.ottoq_return_arrival_fit(uuid,timestamptz,timestamptz)'::regprocedure)
              || pg_get_functiondef('public.ottoq_variance_curve_fit(float8[],float8[],float8[])'::regprocedure)),$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 1,
$old$    c_arr_act := 'Grade the next armed run''s orders: the futures now spread each arrival by its horizon as the depot''s '
                 'returns show.';
  END IF;$old$,
$new$    c_arr_act := 'Grade the next armed run''s orders: the futures now spread each arrival by its horizon as the depot''s '
                 'returns show.';
  END IF;
  -- 0634: orders made with a return model that timed drains from back-dated dispatches (forecast_v 1), graded once the
  -- depot's has forecast_v 2, are history for the arrivals until new orders are graded
  IF NOT v_arr_built
     AND COALESCE((public.ottoq_learned_estimate(p_depot_id, 'return_v1') #>> '{params,forecast_v}')::int, 1) >= 2
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_grades h
                       JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
                       JOIN public.ottoq_learned_estimates e ON e.estimate_id::text = s.state #>> '{models,return}'
                      WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
                        AND COALESCE((e.params ->> 'forecast_v')::int, 1) >= 2) THEN
    v_arr_built := true;
    c_arr_note := ' These orders were made before the futures timed each car''s drain only from a dispatch the depot saw '
                  'begin, so this is history until new orders are graded.';
    c_arr_act := 'Grade the next armed run''s orders: the futures now drain each car at the rate its returns show from '
                 'dispatches the depot saw begin.';
  END IF;$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0634_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0634_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0634 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    -- V1: the stored definition is the pre-image with exactly these replacements
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0634 V1: % is not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ (b) the arrival spread reads the orders of the forecast as it stands ════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_return_arrival_fit(p_depot uuid, p_from timestamptz, p_through timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $fn$
  -- 0633: return_v1's `arrival` (ottoq_return_model_params): the spread of the check's own arrival forecasts, from the
  -- depot's orders recorded in (p_from, p_through] and graded by p_through (a fit through a past moment reads the grades
  -- that stood by then, G367): every forecast arrival made by 0628's drain or later (the order's state carries a class's
  -- drain) that came home inside its window, at a horizon (minutes to the rung) above zero. Per log-spaced horizon bin
  -- with c_min_bin returns or more (a return is a car's one arrival, however many orders forecast it): the robust second
  -- moment of the error about the forecast's median, (1.4826 * the median absolute error)^2; and floor + walk * h +
  -- drift * h^2 fitted to the bins (ottoq_variance_curve_fit). Usable from c_min_bins bins and c_min_returns returns.
  -- 0634: and only the orders made by the newest forecast among them (the forecast_v of the return model each was made
  -- with; 1 before 0634) once they alone give a usable spread; until then every one, as 0633. A forecast that changes
  -- changes its errors, and the spread is the errors of the forecast as it stands.
DECLARE
  c_bins        constant int := 12;           -- log-spaced horizon bins from c_hz_lo to c_hz_hi minutes
  c_hz_lo       constant float8 := 0.3;
  c_hz_hi       constant float8 := 180;
  c_min_bin     constant int := 10;
  c_min_bins    constant int := 4;
  c_min_returns constant int := 30;
  v_h float8[]; v_v float8[]; v_n float8[]; v_bins jsonb; v_ret int; v_fc int; v_ord int; v_runs int; v_b float8[];
  v_vmax int; v_only boolean;                                                                           -- 0634
BEGIN
  WITH ar AS (
    SELECT h.order_id, h.sim_run_id AS run, s.sim_clock AS clock, ib.value AS e,
           (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
           COALESCE((e.params ->> 'forecast_v')::int, 1) AS fv                                          -- 0634
      FROM public.ottoq_charge_order_grades h
      JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
      LEFT JOIN public.ottoq_learned_estimates e ON e.estimate_id::text = s.state #>> '{models,return}'  -- 0634
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
     WHERE h.depot_id = p_depot AND s.recorded_at > p_from AND s.recorded_at <= p_through AND h.graded_at <= p_through
       AND jsonb_path_exists(s.state, '$.inbound[*].dr')
       AND ib.value ->> 'src' = 'forecast'
       AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
  ), g AS (
    SELECT ar.order_id, ar.run, ar.fv, (ar.e ->> 'eta')::float8 - COALESCE((ar.e ->> 'trip')::float8, 0) AS hz,
           ar.act - (ar.e ->> 'eta')::float8 AS err,
           (ar.e ->> 'id') || '@' || to_char(date_trunc('minute', ar.clock + make_interval(secs => ar.act * 60)
                                                                     + interval '30 seconds') AT TIME ZONE 'UTC',
                                             'YYYY-MM-DD HH24:MI') AS ret
      FROM ar WHERE ar.act IS NOT NULL AND (ar.e ->> 'eta') IS NOT NULL
  ), ga AS (
    SELECT g.*, width_bucket(ln(g.hz), ln(c_hz_lo), ln(c_hz_hi), c_bins) AS b FROM g WHERE g.hz > 0
  ), v AS (     -- 0634: the newest forecast among the orders, and whether its orders alone make a usable spread
    SELECT max(ga.fv) AS vmax FROM ga
  ), vo AS (
    SELECT (SELECT count(*) FROM (SELECT ga.b FROM ga, v WHERE ga.fv = v.vmax GROUP BY ga.b
                                   HAVING count(DISTINCT ga.ret) >= c_min_bin) x) >= c_min_bins
           AND (SELECT count(DISTINCT ga.ret) FROM ga, v WHERE ga.fv = v.vmax) >= c_min_returns AS ok
  ), gb AS (
    SELECT ga.* FROM ga, v, vo WHERE NOT vo.ok OR ga.fv = v.vmax
  ), bins AS (
    SELECT gb.b, count(DISTINCT gb.ret)::float8 AS w, count(*) AS n, avg(gb.hz) AS hz,
           power(1.4826 * percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(gb.err)), 2) AS v
      FROM gb GROUP BY gb.b HAVING count(DISTINCT gb.ret) >= c_min_bin
  )
  SELECT (SELECT array_agg(bins.hz ORDER BY bins.b) FROM bins), (SELECT array_agg(bins.v ORDER BY bins.b) FROM bins),
         (SELECT array_agg(bins.w ORDER BY bins.b) FROM bins),
         COALESCE((SELECT jsonb_agg(jsonb_build_object('hz', round(bins.hz::numeric, 2), 'v', round(bins.v::numeric, 4),
                                                       'returns', bins.w::int, 'forecasts', bins.n) ORDER BY bins.b)
                     FROM bins), '[]'::jsonb),
         (SELECT count(DISTINCT gb.ret) FROM gb), (SELECT count(*) FROM gb), (SELECT count(DISTINCT gb.order_id) FROM gb),
         (SELECT count(DISTINCT gb.run) FROM gb), (SELECT v.vmax FROM v), (SELECT vo.ok FROM vo)
    INTO v_h, v_v, v_n, v_bins, v_ret, v_fc, v_ord, v_runs, v_vmax, v_only;
  v_b := public.ottoq_variance_curve_fit(v_h, v_v, v_n);
  RETURN jsonb_build_object(
           'floor', round(v_b[1]::numeric, 4), 'walk', round(v_b[2]::numeric, 5), 'drift', round(v_b[3]::numeric, 7),
           'bins', v_bins, 'returns', v_ret, 'forecasts', v_fc, 'orders', v_ord, 'runs', v_runs,
           'centred', 'the forecast''s median',
           'fit', 'relative least squares: each bin by its returns over its variance squared',
           'from', CASE WHEN v_only THEN 'graded forecasts made by the newest forecast among them'
                        ELSE 'graded forecasts made by 0628''s drain or later' END,
           'forecast_v', CASE WHEN v_only THEN v_vmax END, 'forecast_v_newest', v_vmax,                    -- 0634
           'usable', COALESCE(cardinality(v_h), 0) >= c_min_bins AND v_ret >= c_min_returns AND v_b IS NOT NULL);
END
$fn$;

GRANT EXECUTE ON FUNCTION public.ottoq_return_arrival_fit(uuid, timestamptz, timestamptz) TO anon, authenticated, service_role;

-- ══ V1: each change by meaning in the stored definitions ═════════════════════════════════════════════════════════════════
DO $v1$
DECLARE v_p text; v_a text; v_f text; v_s text;
BEGIN
  v_p := pg_get_functiondef('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)'::regprocedure);
  v_a := pg_get_functiondef('public.ottoq_return_arrival_fit(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure);
  v_f := pg_get_functiondef('public.ottoq_fit_return_model(uuid,timestamp with time zone,interval,text)'::regprocedure);
  v_s := pg_get_functiondef('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure);
  IF strpos(v_p, 'GREATEST(x.dispatched_at, x.run_start)') = 0 OR strpos(v_p, 'AND NOT primed') = 0
     OR strpos(v_p, 'r.sim_clock_start AS run_start') = 0 OR strpos(v_p, '''forecast_v'', 2)') = 0
     OR strpos(v_p, '''n_primed'', (SELECT count(*) FROM low WHERE primed)') = 0 THEN
    RAISE EXCEPTION '0634 V1: the return fit does not time drains as meant';
  END IF;
  IF strpos(v_a, 'WHERE NOT vo.ok OR ga.fv = v.vmax') = 0 OR strpos(v_a, '''forecast_v_newest'', v_vmax') = 0 THEN
    RAISE EXCEPTION '0634 V1: the arrival spread does not read the newest forecast''s orders as meant';
  END IF;
  IF strpos(v_f, 'public.ottoq_return_arrival_fit(uuid,timestamptz,timestamptz)') = 0
     OR strpos(v_f, 'public.ottoq_variance_curve_fit(float8[],float8[],float8[])') = 0 THEN
    RAISE EXCEPTION '0634 V1: the fit''s code md5 does not cover the arrival spread';
  END IF;
  IF strpos(v_s, 'only from a dispatch the depot saw ''') = 0 THEN
    RAISE EXCEPTION '0634 V1: the self-review does not mark orders made before 0634 as history';
  END IF;
  RAISE NOTICE '0634 V1: the return fit times drains from dispatches the depot saw begin; the arrival spread reads the newest forecast''s orders; the fit''s md5 covers the spread; the self-review knows';
END $v1$;

-- ══ V2: the gate, out of sample on the latest run with 20 graded orders forecasting cars by 0628's drain ═══════════════
DO $v2$
DECLARE
  c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  g record; v_new jsonb; st record;
BEGIN
  SELECT * INTO g FROM _0634_gate;
  IF g.run IS NULL THEN
    RAISE NOTICE '0634 V2: no run has 20 graded orders forecasting cars by 0628''s drain; the gate is executed by the tests';
    RETURN;
  END IF;
  v_new := public.ottoq_return_model_params(c_twin, g.through, interval '21 days');
  WITH f AS (
    SELECT (ib.value ->> 'id')::uuid AS vid, (ib.value ->> 'eta')::float8 AS eta, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip,
           (ib.value ->> 'dr')::float8 AS dr,
           (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act
      FROM public.ottoq_charge_order_grades h
      JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
     WHERE s.sim_run_id = g.run AND ib.value ->> 'src' = 'forecast' AND (ib.value ->> 'dr') IS NOT NULL
       AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
  ), e AS (
    SELECT f.eta - f.trip AS hz, f.act - f.eta AS err_old,
           f.act - (f.trip + GREATEST(f.dr * (f.eta - f.trip) / NULLIF(n.dr, 0), 0)) AS err_new,
           f.dr AS dr_old, n.dr AS dr_new, o.dr AS dr_refit
      FROM f
      JOIN public.vehicles v ON v.id = f.vid
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) w
      CROSS JOIN LATERAL (SELECT (public.ottoq_return_car_drain(jsonb_build_object('params', v_new), w.who) ->> 'dr')::float8 AS dr) n
      CROSS JOIN LATERAL (SELECT (public.ottoq_return_car_drain(jsonb_build_object('params', g.p_old), w.who) ->> 'dr')::float8 AS dr) o
     WHERE f.act IS NOT NULL AND f.eta > f.trip AND n.dr > 0
  )
  SELECT count(*) AS n, avg(abs(e.err_old)) AS mae_old, avg(abs(e.err_new)) AS mae_new,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY e.err_old) FILTER (WHERE e.hz >= 30) AS med_old,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY e.err_new) FILTER (WHERE e.hz >= 30) AS med_new,
         count(*) FILTER (WHERE e.hz >= 30) AS n30,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY e.dr_new / e.dr_old) AS ratio,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY e.dr_refit / e.dr_old) AS ratio_refit
    INTO st FROM e;
  RAISE NOTICE '0634 V2: run % through its first order (%): the depot''s drain % -> % (% -> % timed, % began before their run), other calls home per hour of work % -> %; % forecast arrivals re-made at each car''s drain (median ratio % to the forecast''s; the fit as it stood %): mean absolute error % -> % minutes, median error past 30 minutes % -> % (% arrivals)',
    left(g.run::text, 8), g.through, g.p_old ->> 'drain_pct_per_min', v_new ->> 'drain_pct_per_min',
    g.p_old ->> 'n_drain', v_new ->> 'n_drain', v_new ->> 'n_primed', g.p_old ->> 'other_per_work_hour',
    v_new ->> 'other_per_work_hour', st.n, round(st.ratio::numeric, 4), round(st.ratio_refit::numeric, 4), round(st.mae_old::numeric, 3),
    round(st.mae_new::numeric, 3), round(st.med_old::numeric, 3), round(st.med_new::numeric, 3), st.n30;
  IF st.n > 0 AND (st.mae_new > st.mae_old * 1.005
                  OR (st.n30 > 0 AND abs(st.med_new) > abs(st.med_old) + 1e-9)) THEN
    RAISE EXCEPTION '0634 V2: the gate holds back: error % -> %, median past 30 minutes % -> %',
      round(st.mae_old::numeric, 3), round(st.mae_new::numeric, 3), round(st.med_old::numeric, 3), round(st.med_new::numeric, 3);
  END IF;
END $v2$;

-- ══ V3: the refit ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v3$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v_id bigint; v_m jsonb; v_t timestamptz := clock_timestamp();
BEGIN
  v_id := public.ottoq_fit_return_model(c_twin, now(), interval '21 days',
                                        '0634: the first fit to time drains only from dispatches the depot saw begin');
  v_m := public.ottoq_learned_estimate(c_twin, 'return_v1');
  IF (v_m ->> 'estimate_id')::bigint IS DISTINCT FROM v_id OR (v_m #>> '{params,forecast_v}') IS DISTINCT FROM '2' THEN
    RAISE EXCEPTION '0634 V3: the depot''s return model is not the refit % at forecast 2', v_id;
  END IF;
  RAISE NOTICE '0634 V3: return_v1 estimate % in % s, usable %: the depot''s drain % (spread %, % timed, % began before their run), other calls home per hour of work %; by class: %; its arrival reads %',
    v_id, round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 1), v_m ->> 'usable',
    v_m #>> '{params,drain_pct_per_min}', v_m #>> '{params,drain_log_sd}', v_m #>> '{params,n_drain}',
    v_m #>> '{params,n_primed}', v_m #>> '{params,other_per_work_hour}',
    COALESCE((SELECT string_agg(k.key || ' ' || (k.value ->> 'drain') || ' (' || (k.value ->> 'n') || ')', '; ' ORDER BY k.key)
                FROM jsonb_each(CASE WHEN jsonb_typeof(v_m #> '{params,drain_by}') = 'object'
                                     THEN v_m #> '{params,drain_by}' ELSE '{}'::jsonb END) k), 'none'),
    COALESCE(v_m #>> '{params,arrival,from}', 'nothing') || ' (usable ' || COALESCE(v_m #>> '{params,arrival,usable}', 'false') || ')';
END $v3$;

-- ══ V4: the self-review reads it ═══════════════════════════════════════════════════════════════════════════════════════════
DO $v4$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v jsonb; v_t timestamptz := clock_timestamp();
BEGIN
  v := public.ottoq_arbiter_self_assessment_v3(c_twin, now() - interval '7 days', false);
  RAISE NOTICE '0634 V4: the self-review in % ms; its arrival areas: %', round(extract(epoch FROM clock_timestamp() - v_t) * 1000),
    COALESCE((SELECT string_agg((x.value ->> 'status') || ' ' || (x.value ->> 'area') || ': ' || left(x.value ->> 'finding', 160), ' | ')
                FROM jsonb_array_elements(v -> 'improvement_areas') x WHERE x.value ->> 'part' = 'arrivals'), 'none');
END $v4$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0634_a_drain_is_timed_only_from_a_dispatch_the_depot_saw_begin', false, false,
  'return_v1 times a drain only from a dispatch the depot saw begin (a car already at work when its run began, its '
  'dispatch back-dated, times none) and counts work from the later of the dispatch and the run''s start; the fit carries '
  'forecast_v 2; the arrival spread reads the newest forecast''s orders once they alone are usable; the fit''s code md5 '
  'covers the spread; the self-review marks orders made before it as history; return_v1 is refitted. FALSE/FALSE as 0627, '
  '0628 and 0633: the return model is read by the check on an agent''s charge order and the agent''s board; no kernel '
  'decision, dial or seat reads it, and no certification arm runs the agent or the charge order.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
