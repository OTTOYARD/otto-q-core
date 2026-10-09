-- migration-version: PENDING
-- migration-name:    the_futures_spread_each_arrival_as_the_returns_show
--
-- 0633  **The futures spread each arrival as the depot's returns show.**
--       The kernel's check on an agent's charge order rolls futures in which every car at work comes home, each at its
--       forecast median spread by a log spread that grows with how far ahead the car is. That spread was the class's
--       drain spread times the horizon, plus the drive's: too narrow for a car due in minutes, too wide for one due in
--       an hour. 0633 learns the spread from the check's own forecasts, graded against what happened: the arrival's
--       error in minutes has a floor (the recall is decided at a tick, a battery reading is noisy, the drive varies), a
--       part that grows with the square root of the horizon, and a part that grows with the horizon. The return fit
--       learns all three every night; the forecast reads them; the futures and the grade read the forecast.
--
-- ══ §1 WHY (measured 2026-10-09 06:15-06:45 UTC, 1:15-1:45 AM CT) ═══════════════════════════════════════════════════════
--
--   (a) G371 (check 0423 §3): on b2efcc07's 3,703 forecast arrivals (100 returns), out of sample, 50.4% inside the 80%
--       band for cars due within 10 minutes, 79.1% at 10-30, 91.9% at 30-60 and 94.0% past an hour. The self-review
--       ranks it second, on 24.4% of what made the check wrong ("A few cars come home far from their forecast").
--   (b) What the errors are. Split by each return's own dispatch, the 95 reserve returns' drive home ran +0.06 to
--       +0.08 minutes over the forecast's (SD 0.2), so the error is the time to the rung: SD 0.47, 0.76, 1.39 and 1.74
--       minutes at horizons near 5, 20, 45 and 70. The battery itself barely wanders (its reading strays 0.12-0.18
--       points from each dispatch's own straight line at lags of 1 to 40 minutes), so the error is a floor, a car's
--       drain beside its class's, and what lies between. In the fit's own 9 log-spaced horizon bins (10 returns or
--       more each), the robust second moment of the error (1.4826 times the median absolute error, squared) reads
--       0.30, 0.13, 0.32, 0.25, 0.43, 0.66, 1.30, 2.96 and 5.35 at horizons of 1.4 to 68 minutes; floor + walk * h +
--       drift * h^2 carries it. The forecast's variance was (0.04 h)^2 + 0.17^2: 0.03 at 1.4 minutes and 7.4 at 68.
--   (c) What the fit buys, in sample on b2efcc07 (rehearsed 2026-10-09 06:40 UTC, 1:40 AM CT: floor 0.249, walk
--       0.0047 and drift 0.00107 fitted to 9 bins of 100 returns, scored on their 3,658 forecasts through the futures'
--       own reader, ottoq_inbound_arrival_z with the order's other calls home): inside the 80% band, under 10 minutes
--       50.4% -> 81.3% (9.3% early, 9.4% late), 10-30 79.1% -> 84.4%, 30-60 91.9% -> 88.5%, 60+ 94.0% -> 93.8%; all
--       82.6% -> 86.9%. Out of sample is the next armed run's.
--   (d) What it does not fix. Past 30 minutes cars come home early: the median error is -2% of the horizon (-1.20
--       minutes at 61). The three other calls home on b2efcc07 (stale comms twice, a major fault) came 7-18 minutes
--       early and the futures already draw other calls at the depot's rate; the reserve returns' drift is a run's drain
--       beside the forecast's. A spread centred where the forecast is cannot be both 80% and balanced around a median
--       that is off: the long horizons stay wide. Named in G371 as the next build.
--   (e) Why the fit weighs each bin relative to its own size. On a planted spread (floor 0.25, walk 0.01, drift
--       0.0009; tests/test_agent_arrival_spread_sql.py), a fit weighing each bin by its returns alone read the variance
--       at 0.6 minutes as 0.117 against 0.256 planted: the long horizons' large variances outweigh the short ones', and
--       the short horizons are where G371's band was thinnest. A variance read from n returns is known to a share of
--       itself, so each bin weighs n over its variance squared (first its own, then twice the fitted curve's).
--   (f) Learned from the check's grades, not from the cars' telemetry: the dispatches and the telemetry are run-scoped
--       engine data (ottoq_run_scope_registry class 'engine'); the snapshots and the grades are evidence, and in
--       production the agent is armed on every run (0629), so the check grades its forecasts every day.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) ottoq_return_model_params gains `arrival` (public.ottoq_return_arrival_fit): from the depot's graded orders in
--       the fit's window (a fit through a past moment reads the grades that stood by then, G367), every forecast
--       arrival made by 0628's drain or later (the order's state carries a class's drain) that came home inside its
--       window, at a horizon (minutes to the rung) above zero: per log-spaced horizon bin with 10 returns or more (a
--       return is a car's one arrival, however many orders forecast it), the robust second moment of the error about
--       zero (the forecast's median); the floor, walk and drift that are each zero or more, by relative least squares
--       (public.ottoq_variance_curve_fit, §1(e)). Usable from 4 bins and 30 returns. Every other key is 0628's.
--   (b) public.ottoq_return_arrival_sd(return model, horizon): the log spread whose variance about the horizon is the
--       fit's, sqrt(ln(1 + V(h) / max(h, 0.25)^2)); NULL when the fit has no usable arrival. The forecast and a reader
--       of it read it here.
--   (c) ottoq_charge_line_inbound: with the run's new dial agent_charge_order_arrival_spread at 1 (its default) and a
--       usable arrival, each car at work is spread by (b); else 0628's spread. A person's dial, catalogued, not the
--       agent's (0 is 0628's forecast exactly).
--   (d) The self-review: orders made with a return model that had no usable arrival, graded once the depot's has one,
--       are history for the arrivals (built), and it says so.
--   (e) return_v1 is refitted here, so the check reads the spread from this apply on.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running, no fit running. P1 the four bodies are the ones measured (the self-review's
--   after 0632), 0632's solve exists, the objects are new. V1 the spread and the curve fit by arithmetic (an exact
--   curve comes back, a flat one is a floor alone); each patch by meaning; the dial catalogued. V2 on the return model
--   as it stood (no arrival), the spread is NULL and the forecast is 0628's. V3 the refit's arrival, and the coverage
--   it gives the graded forecasts by horizon against the old spread; a gate: under 10 minutes the band holds at least
--   70% and nearer 80% than it did. V4 the self-review reads it. Executed by tests/test_agent_arrival_spread_sql.py on
--   the miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0627 and 0628: the inbound forecast is read by the check on an
--   agent's charge order and the agent's board; no kernel decision, dial or seat reads it, and no certification arm runs
--   the agent or the charge order (0615). The dial is new and defaults to 1.
--
-- ROLLBACK: set agent_charge_order_arrival_spread to 0 on the runs that should not see it (0628's forecast, exactly), or
--   EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0633_pre' AND object_kind = 'function'; then DROP
--   FUNCTION public.ottoq_return_arrival_sd(jsonb, numeric), public.ottoq_return_arrival_fit(uuid, timestamptz,
--   timestamptz) and public.ottoq_variance_curve_fit(float8[], float8[], float8[]); DELETE FROM
--   public.ottoq_policy_param_catalog WHERE
--   param_key = 'agent_charge_order_arrival_spread'; the return fit appended here stays (evidence); DELETE FROM
--   public.ottoq_cert_lineage WHERE name = '0633_the_futures_spread_each_arrival_as_the_returns_show'.

BEGIN;

-- ── P0: nothing in flight, no run running, no fit running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0633 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0633 P0: a run is running; its check reads the forecast this replaces. Apply between runs';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE pid <> pg_backend_pid() AND state = 'active' AND query ~ 'ottoq_fit_return_model\(') THEN
    RAISE EXCEPTION '0633 P0: a return fit is running (the nightly refit); apply after it';
  END IF;
END $inflight$;

-- ── P1: the bodies are the ones measured; 0632 is applied; the objects are new ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)',                        '5ff357d481888b31efa0afd0c2096cff'),
    ('public.ottoq_charge_line_inbound(uuid,uuid,timestamp with time zone,numeric,jsonb)',              'd53b5734fd590e47071a53ed0df12dbd'),
    ('public.ottoq_fit_return_model(uuid,timestamp with time zone,interval,text)',                      '05f61d707a23cf26a39126289ae9a4b5'),
    ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)',                  '59fa5a99041929c296f879ffd150a94f'))
    AS t(sig, src_md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0633 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_solve_sym3(double precision,double precision,double precision,double precision,'
                     'double precision,double precision,double precision,double precision,double precision)') IS NULL THEN
    RAISE EXCEPTION '0633 P1: 0632 comes first (its solve fits the spread)';
  END IF;
  IF to_regprocedure('public.ottoq_return_arrival_sd(jsonb,numeric)') IS NOT NULL
     OR to_regprocedure('public.ottoq_return_arrival_fit(uuid,timestamp with time zone,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.ottoq_variance_curve_fit(double precision[],double precision[],double precision[])') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_arrival_spread')
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0633_the_futures_spread_each_arrival_as_the_returns_show') THEN
    RAISE EXCEPTION '0633 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0633_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)'::regprocedure,
                 'public.ottoq_charge_line_inbound(uuid,uuid,timestamp with time zone,numeric,jsonb)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure);

-- what V2 compares against: the return model as it stood
CREATE TEMP TABLE _0633_model ON COMMIT DROP AS
SELECT public.ottoq_learned_estimate('11111111-1111-1111-1111-111111111111', 'return_v1') AS m;

-- ══ (c) the dial ══════════════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES ('agent_charge_order_arrival_spread', 0, 1, 1, false,
  'ottoq_charge_line_inbound, ottoq_charge_line_state (0633 the arrival spread)',
  '0633: whether the kernel''s check on an agent''s charge order spreads each car at work by the arrival spread the return '
  'fit learns from the check''s own graded forecasts (a floor, a part with the square root of the horizon and a part with '
  'the horizon), or by the class''s drain spread and the drive''s. 1 learned; 0 is 0628''s check exactly. A person''s dial, '
  'never the agent''s (rule 10).');

-- ══ (b) the spread ════════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_return_arrival_sd(p_rt jsonb, p_hz numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0633: the log spread of a car's arrival forecast p_hz minutes from its rung, from a return_v1 estimate's `arrival`
  -- (p_rt, with its params): the lognormal about the horizon whose variance in minutes is the fit's
  -- V(h) = floor + walk * h + drift * h^2, sqrt(ln(1 + V(h) / max(h, 0.25)^2)). NULL when the fit has no usable arrival
  -- or the horizon is not known. The forecast and every reader of it read it here.
  SELECT CASE WHEN p_hz IS NULL OR NOT COALESCE((p_rt #>> '{params,arrival,usable}')::boolean, false) THEN NULL
              ELSE round(sqrt(ln(1 + GREATEST(COALESCE((p_rt #>> '{params,arrival,floor}')::numeric, 0)
                                              + COALESCE((p_rt #>> '{params,arrival,walk}')::numeric, 0) * GREATEST(p_hz, 0)
                                              + COALESCE((p_rt #>> '{params,arrival,drift}')::numeric, 0) * power(GREATEST(p_hz, 0), 2),
                                              1e-6)
                                     / power(GREATEST(p_hz, 0.25), 2))), 4) END
$fn$;

GRANT EXECUTE ON FUNCTION public.ottoq_return_arrival_sd(jsonb, numeric) TO anon, authenticated, service_role;

-- ══ (a) the curve, and the spread the fit learns ══════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_variance_curve_fit(p_h double precision[], p_v double precision[], p_n double precision[])
RETURNS double precision[]
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
SET search_path TO 'public', 'pg_temp'
AS $fn$
  -- 0633: floor + walk * h + drift * h^2, each zero or more, fitted to variances p_v read at horizons p_h, each from p_n
  -- returns, by relative least squares: a variance read from n returns is known to a share of itself, so each weighs n
  -- over its variance squared, first its own, then twice the fitted curve's (so a bin that read high by chance is not
  -- discounted for it). Every non-empty set of the three terms is solved (ottoq_solve_sym3, a term left out held at zero,
  -- the horizons scaled to the largest so the solve is well conditioned), and the set whose terms are all zero or more
  -- and that leaves the bins least is kept, the fewer terms on a tie: the least-squares fit with every term zero or
  -- more. {floor, walk, drift}; NULL with no bin, or no set that solves.
DECLARE
  c_v_min constant float8 := 0.01;    -- no variance is read finer than a tenth of a minute
  v_s float8;
  v_w float8[];
  v_b float8[];
  v_new float8[];
BEGIN
  IF COALESCE(cardinality(p_h), 0) = 0 OR cardinality(p_v) IS DISTINCT FROM cardinality(p_h)
     OR cardinality(p_n) IS DISTINCT FROM cardinality(p_h) THEN
    RETURN NULL;
  END IF;
  SELECT max(x.h) INTO v_s FROM unnest(p_h) x(h) WHERE x.h > 0;
  IF v_s IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT array_agg(x.n / power(GREATEST(x.v, c_v_min), 2) ORDER BY x.o) INTO v_w
    FROM unnest(p_v, p_n) WITH ORDINALITY x(v, n, o);
  FOR i IN 1..3 LOOP
    WITH bins AS (
      SELECT x.h / v_s AS u, x.v, x.w FROM unnest(p_h, p_v, v_w) x(h, v, w)
       WHERE x.h > 0 AND x.v IS NOT NULL AND x.w > 0
    ), m AS (
      SELECT sum(bins.w) AS s11, sum(bins.w * bins.u) AS s12, sum(bins.w * bins.u ^ 2) AS s13,
             sum(bins.w * bins.u ^ 3) AS s23, sum(bins.w * bins.u ^ 4) AS s33,
             sum(bins.w * bins.v) AS t1, sum(bins.w * bins.u * bins.v) AS t2, sum(bins.w * bins.u ^ 2 * bins.v) AS t3
        FROM bins
    ), sub AS (
      SELECT s.f, s.k, s.d FROM (VALUES (true, false, false), (false, true, false), (false, false, true),
                                        (true, true, false), (true, false, true), (false, true, true),
                                        (true, true, true)) s(f, k, d)
    ), sol AS (
      SELECT sub.*, public.ottoq_solve_sym3(
               CASE WHEN sub.f THEN m.s11 ELSE 1 END, CASE WHEN sub.f AND sub.k THEN m.s12 ELSE 0 END,
               CASE WHEN sub.f AND sub.d THEN m.s13 ELSE 0 END,
               CASE WHEN sub.k THEN m.s13 ELSE 1 END, CASE WHEN sub.k AND sub.d THEN m.s23 ELSE 0 END,
               CASE WHEN sub.d THEN m.s33 ELSE 1 END,
               CASE WHEN sub.f THEN m.t1 ELSE 0 END, CASE WHEN sub.k THEN m.t2 ELSE 0 END,
               CASE WHEN sub.d THEN m.t3 ELSE 0 END) AS b
        FROM sub CROSS JOIN m WHERE m.s11 > 0
    ), ok AS (
      SELECT sol.*, (SELECT sum(bins.w * (bins.v - sol.b[1] - sol.b[2] * bins.u - sol.b[3] * bins.u ^ 2) ^ 2) FROM bins) AS sse
        FROM sol WHERE sol.b IS NOT NULL AND sol.b[1] >= 0 AND sol.b[2] >= 0 AND sol.b[3] >= 0
    )
    SELECT ARRAY[ok.b[1], ok.b[2], ok.b[3]] INTO v_new FROM ok ORDER BY ok.sse, ok.f::int + ok.k::int + ok.d::int LIMIT 1;
    EXIT WHEN v_new IS NULL;
    v_b := v_new;
    EXIT WHEN i = 3;
    SELECT array_agg(x.n / power(GREATEST(v_b[1] + v_b[2] * (x.h / v_s) + v_b[3] * (x.h / v_s) ^ 2, c_v_min), 2) ORDER BY x.o)
      INTO v_w FROM unnest(p_h, p_n) WITH ORDINALITY x(h, n, o);
  END LOOP;
  RETURN CASE WHEN v_b IS NULL THEN NULL ELSE ARRAY[v_b[1], v_b[2] / v_s, v_b[3] / (v_s * v_s)] END;
END
$fn$;

CREATE FUNCTION public.ottoq_return_arrival_fit(p_depot uuid, p_from timestamptz, p_through timestamptz)
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
DECLARE
  c_bins        constant int := 12;           -- log-spaced horizon bins from c_hz_lo to c_hz_hi minutes
  c_hz_lo       constant float8 := 0.3;
  c_hz_hi       constant float8 := 180;
  c_min_bin     constant int := 10;
  c_min_bins    constant int := 4;
  c_min_returns constant int := 30;
  v_h float8[]; v_v float8[]; v_n float8[]; v_bins jsonb; v_ret int; v_fc int; v_ord int; v_runs int; v_b float8[];
BEGIN
  WITH ar AS (
    SELECT h.order_id, h.sim_run_id AS run, s.sim_clock AS clock, ib.value AS e,
           (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act
      FROM public.ottoq_charge_order_grades h
      JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
     WHERE h.depot_id = p_depot AND s.recorded_at > p_from AND s.recorded_at <= p_through AND h.graded_at <= p_through
       AND jsonb_path_exists(s.state, '$.inbound[*].dr')
       AND ib.value ->> 'src' = 'forecast'
       AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
  ), g AS (
    SELECT ar.order_id, ar.run, (ar.e ->> 'eta')::float8 - COALESCE((ar.e ->> 'trip')::float8, 0) AS hz,
           ar.act - (ar.e ->> 'eta')::float8 AS err,
           (ar.e ->> 'id') || '@' || to_char(date_trunc('minute', ar.clock + make_interval(secs => ar.act * 60)
                                                                     + interval '30 seconds') AT TIME ZONE 'UTC',
                                             'YYYY-MM-DD HH24:MI') AS ret
      FROM ar WHERE ar.act IS NOT NULL AND (ar.e ->> 'eta') IS NOT NULL
  ), gb AS (
    SELECT g.*, width_bucket(ln(g.hz), ln(c_hz_lo), ln(c_hz_hi), c_bins) AS b FROM g WHERE g.hz > 0
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
         (SELECT count(DISTINCT gb.run) FROM gb)
    INTO v_h, v_v, v_n, v_bins, v_ret, v_fc, v_ord, v_runs;
  v_b := public.ottoq_variance_curve_fit(v_h, v_v, v_n);
  RETURN jsonb_build_object(
           'floor', round(v_b[1]::numeric, 4), 'walk', round(v_b[2]::numeric, 5), 'drift', round(v_b[3]::numeric, 7),
           'bins', v_bins, 'returns', v_ret, 'forecasts', v_fc, 'orders', v_ord, 'runs', v_runs,
           'centred', 'the forecast''s median',
           'fit', 'relative least squares: each bin by its returns over its variance squared',
           'from', 'graded forecasts made by 0628''s drain or later',
           'usable', COALESCE(cardinality(v_h), 0) >= c_min_bins AND v_ret >= c_min_returns AND v_b IS NOT NULL);
END
$fn$;

GRANT EXECUTE ON FUNCTION public.ottoq_variance_curve_fit(double precision[], double precision[], double precision[])
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_return_arrival_fit(uuid, timestamptz, timestamptz) TO anon, authenticated, service_role;

-- ══ (a) (d) the anchored patches: each anchor once, the stored definition after ═════════════════════════════════════════
CREATE TEMP TABLE _0633_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

INSERT INTO _0633_patch VALUES
('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', 1,
$old$   what it read. Every other key is 0627's. */$old$,
$new$   what it read. Every other key is 0627's.
   0633: and `arrival` (ottoq_return_arrival_fit): the spread of the check's own arrival forecasts, from the depot's
   graded orders in the window (through a past moment, the grades that stood by then), by horizon, with the floor,
   walk and drift fitted to it. Every other key is 0628's. */$new$),
('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', 2,
$old$  RETURN v_p || jsonb_build_object('dwell', v_dw, 'dwell_by', v_dwb);$old$,
$new$  RETURN v_p || jsonb_build_object('dwell', v_dw, 'dwell_by', v_dwb,
                                      'arrival', public.ottoq_return_arrival_fit(p_depot, v_from, v_through));   -- 0633$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 1,
$old$  c_arr_note constant text := ' These orders were made before the futures called each car home at its own reserve rung, '$old$,
$new$  c_arr_note text := ' These orders were made before the futures called each car home at its own reserve rung, '$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 2,
$old$  c_arr_act constant text := 'Grade the next armed run''s orders: the futures now call each car home at its own reserve '$old$,
$new$  c_arr_act text := 'Grade the next armed run''s orders: the futures now call each car home at its own reserve '$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 3,
$old$                                    AND jsonb_typeof(s.state -> 'recall') = 'object');$old$,
$new$                                    AND jsonb_typeof(s.state -> 'recall') = 'object');
  -- 0633: orders made with a return model that had no usable arrival spread, graded once the depot's has one, are history
  -- for the arrivals until new orders are graded
  IF NOT v_arr_built
     AND COALESCE((public.ottoq_learned_estimate(p_depot_id, 'return_v1') #>> '{params,arrival,usable}')::boolean, false)
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_grades h
                       JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
                       JOIN public.ottoq_learned_estimates e ON e.estimate_id::text = s.state #>> '{models,return}'
                      WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
                        AND COALESCE((e.params #>> '{arrival,usable}')::boolean, false)) THEN
    v_arr_built := true;
    c_arr_note := ' These orders were made before the futures spread each arrival as the check''s own graded forecasts show, '
                  'so this is history until new orders are graded.';
    c_arr_act := 'Grade the next armed run''s orders: the futures now spread each arrival by its horizon as the depot''s '
                 'returns show.';
  END IF;$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0633_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0633_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0633 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    -- V1: the stored definition is the pre-image with exactly these replacements
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0633 V1: % is not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ (c) the forecast ══════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_line_inbound(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz,
                                                           p_window_min numeric DEFAULT 180, p_return_model jsonb DEFAULT NULL)
RETURNS TABLE(vehicle_id uuid, eta_min numeric, soc_at_arrival numeric, source text, eta_log_sd numeric, trip_min numeric)
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0620: a car driving home arrives at its dispatch's scheduled_return_at (distance over speed, 0320); a car at work is
  -- called home when its live battery reaches the learned reserve (0619 return_v1), at the learned drain, then drives the
  -- learned trip. With no usable return model, only the cars already driving home. Read-only.
  -- 0627: with the run's agent_charge_order_recall_rule dial at 1 (its default), a car at work is called home where the
  -- kernel's own recall decision calls it, at its own reserve rung (ottoq_recall_threshold_soc: its reserve plus the run's
  -- margin), not at the reserve the depot's returns show on average; and its spread carries the drive's own, in minutes
  -- (the fit's trip_sd_min), beside the drain's, so a car minutes from its reserve is not forecast to the second. With
  -- the dial at 0, 0620's forecast exactly.
  -- 0628: with the run's agent_charge_order_drain_by_class dial at 1 (its default), each car is drained at its own
  -- class's rate, or its model's within the class (ottoq_return_car_drain on the fit's drain_by), with that level's own
  -- spread, a car driving home as well as a car at work; else at the depot's. With the dial at 0, 0627's forecast exactly.
  -- 0633: with the run's agent_charge_order_arrival_spread dial at 1 (its default) and a fit with a usable arrival, each
  -- car at work is spread as the check's own graded forecasts show at its horizon (ottoq_return_arrival_sd: a floor, a
  -- part with the square root of the horizon and a part with the horizon). With the dial at 0, 0628's forecast exactly.
  WITH m AS (
    SELECT COALESCE(p_return_model, public.ottoq_learned_estimate(p_depot_id, 'return_v1')) AS j
  ), p AS (
    SELECT COALESCE((m.j ->> 'usable')::boolean, false) AS usable,
           (m.j #>> '{params,threshold_soc}')::numeric AS thr,
           (m.j #>> '{params,drain_pct_per_min}')::numeric AS drain,
           COALESCE((m.j #>> '{params,drain_log_sd}')::numeric, 0) AS dsd,
           COALESCE((m.j #>> '{params,trip_min}')::numeric, 0) AS trip,
           COALESCE((m.j #>> '{params,trip_sd_min}')::numeric, 0) AS asd,
           COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_recall_rule', 1), 1) >= 1 AS rule,
           COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_drain_by_class', 1), 1) >= 1 AS bycls,   -- 0628
           COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_arrival_spread', 1), 1) >= 1                -- 0633
             AND COALESCE((m.j #>> '{params,arrival,usable}')::boolean, false) AS spread
      FROM m
  ), d AS (
    SELECT DISTINCT ON (d.vehicle_id) d.vehicle_id, d.status, d.scheduled_return_at, v.current_soc::numeric AS soc,
           -- 0628: the drain it is forecast at: its class's or its model's (the fit's drain_by), else the depot's
           COALESCE(NULLIF((k.cd ->> 'dr')::numeric, 0), p.drain) AS dr, COALESCE((k.cd ->> 'dsd')::numeric, p.dsd) AS dsd
      FROM public.ottoq_vehicle_dispatches d
      JOIN public.vehicles v ON v.id = d.vehicle_id
      CROSS JOIN p CROSS JOIN m
      CROSS JOIN LATERAL (SELECT CASE WHEN p.bycls
                                      THEN public.ottoq_return_car_drain(m.j, public.ottoq_charge_clock_who(v.id, v.vehicle_class_code,
                                                                                                            v.make, v.model))
                                 END AS cd) k
     WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active', 'returning') AND d.actual_return_at IS NULL
       AND v.home_depot_id = p_depot_id AND v.category = 'autonomous' AND v.current_soc IS NOT NULL
     ORDER BY d.vehicle_id, d.dispatched_at DESC
  )
  SELECT x.vehicle_id, round(x.eta, 2), round(GREATEST(x.soc, 0), 1), x.source, round(x.sd, 4), round(x.trip, 2)
    FROM (
      SELECT d.vehicle_id, GREATEST(extract(epoch FROM (d.scheduled_return_at - p_clock)) / 60.0, 0) AS eta,
             d.soc - COALESCE(d.dr, 0) * GREATEST(extract(epoch FROM (d.scheduled_return_at - p_clock)) / 60.0, 0) AS soc,
             'returning'::text AS source, 0::numeric AS sd, 0::numeric AS trip
        FROM d, p WHERE d.status = 'returning'
      UNION ALL
      SELECT d.vehicle_id, GREATEST((d.soc - t.thr) / d.dr, 0) + p.trip AS eta,
             LEAST(d.soc, t.thr) - d.dr * p.trip AS soc,
             'forecast'::text AS source,
             CASE WHEN p.spread THEN public.ottoq_return_arrival_sd(m.j, GREATEST((d.soc - t.thr) / d.dr, 0))   -- 0633
                  WHEN p.rule AND p.asd > 0
                  THEN sqrt(d.dsd ^ 2 + (p.asd / GREATEST((d.soc - t.thr) / d.dr, 0.25)) ^ 2) ELSE d.dsd END AS sd,
             p.trip AS trip
        FROM d
        CROSS JOIN p
        CROSS JOIN m
        CROSS JOIN LATERAL (SELECT CASE WHEN p.rule
                                        THEN COALESCE(public.ottoq_recall_threshold_soc(d.vehicle_id, p_sim_run_id, p_clock), p.thr)
                                        ELSE p.thr END AS thr) t
       WHERE d.status = 'active' AND p.usable AND p.drain > 0 AND p.thr IS NOT NULL
    ) x
   WHERE x.eta <= COALESCE(p_window_min, 180)
$fn$;

-- ══ V1: the spread by arithmetic; each patch by meaning; the dial catalogued ═════════════════════════════════════════════
DO $v1$
DECLARE
  c_m constant jsonb := '{"params": {"arrival": {"floor": 0.25, "walk": 0.01, "drift": 0.001, "usable": true}}}';
  v_def text;
  v_b float8[];
BEGIN
  -- V(10) = 0.25 + 0.1 + 0.1 = 0.45: sqrt(ln(1 + 0.45 / 100)); V(0.1) = 0.25101 over 0.25^2 (the floor on the horizon)
  IF public.ottoq_return_arrival_sd(c_m, 10) <> round(sqrt(ln(1.0045)), 4)
     OR public.ottoq_return_arrival_sd(c_m, 0.1) <> round(sqrt(ln(1 + 0.25101 / 0.0625)), 4)
     OR public.ottoq_return_arrival_sd(jsonb_set(c_m, '{params,arrival,usable}', 'false'), 10) IS NOT NULL
     OR public.ottoq_return_arrival_sd('{"params": {}}', 10) IS NOT NULL
     OR public.ottoq_return_arrival_sd(c_m, NULL) IS NOT NULL THEN
    RAISE EXCEPTION '0633 V1: the spread reads % at 10 minutes and % at 0.1', public.ottoq_return_arrival_sd(c_m, 10),
      public.ottoq_return_arrival_sd(c_m, 0.1);
  END IF;
  -- the curve fit: an exact curve (0.25 + 0.01 h + 0.0009 h^2 at 8 horizons) comes back to a part in a million; a flat
  -- one (0.3 everywhere) is a floor alone; no bins is NULL
  v_b := public.ottoq_variance_curve_fit(ARRAY[0.6, 1.5, 3, 6, 12, 25, 45, 80],
                                         ARRAY(SELECT 0.25 + 0.01 * h + 0.0009 * h * h FROM unnest(ARRAY[0.6, 1.5, 3, 6, 12, 25, 45, 80]::float8[]) h),
                                         array_fill(150::float8, ARRAY[8]));
  IF v_b IS NULL OR abs(v_b[1] - 0.25) > 1e-6 OR abs(v_b[2] - 0.01) > 1e-7 OR abs(v_b[3] - 0.0009) > 1e-9 THEN
    RAISE EXCEPTION '0633 V1: the curve fit reads % on an exact curve', v_b;
  END IF;
  v_b := public.ottoq_variance_curve_fit(ARRAY[0.6, 3, 12, 45]::float8[], array_fill(0.3::float8, ARRAY[4]), array_fill(40::float8, ARRAY[4]));
  IF v_b IS NULL OR abs(v_b[1] - 0.3) > 1e-9 OR v_b[2] <> 0 OR v_b[3] <> 0 THEN
    RAISE EXCEPTION '0633 V1: the curve fit reads % on a flat curve', v_b;
  END IF;
  IF public.ottoq_variance_curve_fit('{}'::float8[], '{}'::float8[], '{}'::float8[]) IS NOT NULL THEN
    RAISE EXCEPTION '0633 V1: the curve fit reads a curve from no bins';
  END IF;
  v_def := pg_get_functiondef('public.ottoq_charge_line_inbound(uuid,uuid,timestamp with time zone,numeric,jsonb)'::regprocedure);
  IF strpos(v_def, 'CASE WHEN p.spread THEN public.ottoq_return_arrival_sd(m.j, GREATEST((d.soc - t.thr) / d.dr, 0))') = 0
     OR strpos(v_def, '''agent_charge_order_arrival_spread'', 1), 1) >= 1') = 0 THEN
    RAISE EXCEPTION '0633 V1: the forecast is not as meant';
  END IF;
  IF strpos(pg_get_functiondef('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)'::regprocedure),
            '''arrival'', public.ottoq_return_arrival_fit(p_depot, v_from, v_through));') = 0 THEN
    RAISE EXCEPTION '0633 V1: the return fit does not return its arrival';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_arrival_spread'
                    AND default_value = 1 AND NOT agent_writable) THEN
    RAISE EXCEPTION '0633 V1: the dial is not catalogued as a person''s, default 1';
  END IF;
  RAISE NOTICE '0633 V1: the spread reads % at 10 minutes and % at 0.1 on a planted fit; the curve fit recovers an exact curve and a flat one; the forecast, the fit and the dial as meant',
    public.ottoq_return_arrival_sd(c_m, 10), public.ottoq_return_arrival_sd(c_m, 0.1);
END $v1$;

-- ══ V2: on the return model as it stood, no arrival, so 0628's forecast ═══════════════════════════════════════════════════
DO $v2$
DECLARE v_m jsonb;
BEGIN
  SELECT m INTO v_m FROM _0633_model;
  IF v_m IS NOT NULL AND (v_m #> '{params,arrival}') IS NOT NULL THEN
    RAISE EXCEPTION '0633 V2: the return model as it stood already has an arrival';
  END IF;
  IF public.ottoq_return_arrival_sd(v_m, 10) IS NOT NULL THEN
    RAISE EXCEPTION '0633 V2: a model with no arrival gives a spread';
  END IF;
  RAISE NOTICE '0633 V2: on return_v1 estimate % (no arrival) the spread is NULL, so its forecast is 0628''s', v_m -> 'estimate_id';
END $v2$;

-- ══ V3: the refit, and the coverage it gives the graded forecasts by horizon; the gate ═════════════════════════════════════
DO $v3$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v_id bigint; v_m jsonb; v_t timestamptz := clock_timestamp();
        r record; v_out text := ''; v_short record;
BEGIN
  v_id := public.ottoq_fit_return_model(c_twin, now(), interval '21 days', '0633: the first fit to spread arrivals from graded forecasts');
  v_m := public.ottoq_learned_estimate(c_twin, 'return_v1');
  IF (v_m ->> 'estimate_id')::bigint IS DISTINCT FROM v_id THEN
    RAISE EXCEPTION '0633 V3: the depot''s return model is not the refit %', v_id;
  END IF;
  RAISE NOTICE '0633 V3: return_v1 estimate % in % s, usable %; its arrival: %', v_id,
    round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 1), v_m ->> 'usable', v_m #> '{params,arrival}';
  IF NOT COALESCE((v_m #>> '{params,arrival,usable}')::boolean, false) THEN
    RAISE NOTICE '0633 V3: the arrival is not usable yet (too few graded returns); the forecast stays 0628''s until it is';
    RETURN;
  END IF;
  FOR r IN
    WITH ar AS (
      SELECT ib.value AS e, s.state -> 'recall' AS rc,
             (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act
        FROM public.ottoq_charge_order_grades h
        JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
        CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
       WHERE h.depot_id = c_twin AND jsonb_path_exists(s.state, '$.inbound[*].dr') AND ib.value ->> 'src' = 'forecast'
         AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
    ), z AS (
      SELECT (ar.e ->> 'eta')::float8 - COALESCE((ar.e ->> 'trip')::float8, 0) AS hz,
             public.ottoq_inbound_arrival_z(ar.e, ar.rc, ar.act) AS z_old,
             public.ottoq_inbound_arrival_z(ar.e || jsonb_build_object('esd', public.ottoq_return_arrival_sd(v_m,
                                              ((ar.e ->> 'eta')::numeric - COALESCE((ar.e ->> 'trip')::numeric, 0)))),
                                            ar.rc, ar.act) AS z_new
        FROM ar WHERE (ar.e ->> 'eta')::float8 > COALESCE((ar.e ->> 'trip')::float8, 0)
    )
    SELECT CASE WHEN z.hz < 10 THEN '1 under 10' WHEN z.hz < 30 THEN '2 10-30' WHEN z.hz < 60 THEN '3 30-60' ELSE '4 60+' END AS hb,
           count(*) AS n, avg((abs(z.z_old) <= 1.2816)::int) AS old_in, avg((abs(z.z_new) <= 1.2816)::int) AS new_in,
           avg((z.z_new < -1.2816)::int) AS early, avg((z.z_new > 1.2816)::int) AS late
      FROM z WHERE z.z_old IS NOT NULL AND z.z_new IS NOT NULL GROUP BY 1 ORDER BY 1
  LOOP
    v_out := v_out || format('%s: %s arrivals, inside the 80%% band %s -> %s (early %s, late %s); ', r.hb, r.n,
                             round(r.old_in * 100, 1), round(r.new_in * 100, 1), round(r.early * 100, 1), round(r.late * 100, 1));
    IF r.hb = '1 under 10' THEN v_short := r; END IF;
  END LOOP;
  RAISE NOTICE '0633 V3: the graded forecasts by horizon, the old spread against the new: %', v_out;
  -- the gate: under 10 minutes the band holds at least 70% and is nearer 80% than it was
  IF v_short IS NOT NULL AND (v_short.new_in < 0.70 OR abs(v_short.new_in - 0.80) >= abs(v_short.old_in - 0.80)) THEN
    RAISE EXCEPTION '0633 V3 gate: under 10 minutes the new spread holds % inside the 80%% band against % for the old',
      round(v_short.new_in, 3), round(v_short.old_in, 3);
  END IF;
END $v3$;

-- ══ V4: the self-review reads it ═══════════════════════════════════════════════════════════════════════════════════════════
DO $v4$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v jsonb; v_t timestamptz := clock_timestamp();
BEGIN
  v := public.ottoq_arbiter_self_assessment_v3(c_twin, now() - interval '7 days', false);
  RAISE NOTICE '0633 V4: the self-review in % ms; its arrival areas: %', round(extract(epoch FROM clock_timestamp() - v_t) * 1000),
    COALESCE((SELECT string_agg((x.value ->> 'status') || ' ' || (x.value ->> 'area') || ': ' || left(x.value ->> 'finding', 160), ' | ')
                FROM jsonb_array_elements(v -> 'improvement_areas') x WHERE x.value ->> 'part' = 'arrivals'), 'none');
END $v4$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0633_the_futures_spread_each_arrival_as_the_returns_show', false, false,
  'return_v1 learns the arrival forecast''s spread from the check''s own graded forecasts (ottoq_return_model_params '
  '`arrival`: a floor, a part with the square root of the horizon and a part with the horizon), the inbound forecast '
  'spreads each car at work by it (ottoq_return_arrival_sd) behind the person''s dial agent_charge_order_arrival_spread '
  '(1; 0 is 0628''s forecast), the self-review marks orders made before it as history, and return_v1 is refitted. '
  'FALSE/FALSE as 0627 and 0628: the forecast is read by the check on an agent''s charge order and the agent''s board; '
  'no kernel decision, dial or seat reads it, and no certification arm runs the agent or the charge order.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
