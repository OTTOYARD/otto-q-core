-- migration-version: 20260927061451
-- migration-name:    the_booking_window_is_fitted_from_the_charges_with_the_run_s_stop_counted
--
-- 0516  **G240, step 2: a versioned, append-only calibration of the charge booking window, fitted from 0514's
--       evidence ledger by a split-conformal upper bound that counts the charges a run's stop cut short instead of
--       dropping them. Nothing reads it yet; step 3 puts the booking writer behind a dial that names one version.**
--       `db/checks/0386`.
--
-- ══ §1 WHY NOT THE SIMPLE FIT ══════════════════════════════════════════════════════════════════════════════════
--
--   0385 §4 fitted the window from finished charges: 470 of them, 91.3% covered leave-one-run-out. That population is
--   not the population the booking writer books for. A run's stop ends the charges still running, and on the ten
--   operator runs of two hours or more it ended 280 L2 charges against 267 finished; the finished ones are the short
--   ones (median nominal-to-full 58 minutes among the charges a run gave twice their nominal, 125 over all of them),
--   and among charges judged that way the pace ratio rises with length (L2 p90 1.22 under 30 minutes nominal, 1.68
--   over two hours; 0386 §1). A factor fitted from finished charges alone describes short charges, and says so
--   nowhere.
--
-- ══ §2 THE METHOD (`type1_censored_split_conformal_v1`) ════════════════════════════════════════════════════════
--
--   Every charge's censoring time is known: its run stopped at a clock the charge did not choose. That is Type I
--   right-censoring, and Candès, Lei & Ren, "Conformalized survival analysis", JRSSB 85(1):24-45 (2023),
--   doi:10.1093/jrsssb/qkac004, https://arxiv.org/abs/2103.09763 (read 2026-09-27), give the construction with exact
--   finite-sample coverage under it: keep the units whose censoring time exceeds a threshold c0, and run split
--   conformal on min(T, c0). Mirrored here for an upper bound on the pace ratio R = minutes / nominal minutes:
--     (1) A charge is JUDGED when its run left it at least c0 times its nominal: (run end - start) >= c0 x N_sel. N_sel
--         must not depend on how the charge ended, or the selection leaks the outcome: it is the nominal to the
--         charge's own stop target where 0515 recorded one, and the nominal to 100% otherwise (the stop target is at
--         most 100, so this bound only ever judges fewer charges). The run's end is the latest session end the ledger
--         holds for it, which a stop writes for every charge still running; for a run with none running at its stop
--         it is earlier than the true end, which again only judges fewer.
--     (2) A judged charge scores Y = min(R, c0): a finished one its own ratio to the nominal of what it actually
--         charged, a cut one c0 -- it ran past c0 x N_sel >= c0 x N and was still going.
--     (3) Per cell -- charger type x air band (the air the charge ran in, 0510), and charger type alone -- the factor is
--         the k-th smallest Y with k = ceil((n + 1)(1 - alpha)), when k <= n and that value is below c0. Otherwise the
--         cell has no factor.
--   With nothing cut short this is exactly 0385 §4's split conformal on the judged charges. Faults and orphan sweeps
--   are left out: a fault is dealt per session at a trigger SoC before the charge runs (`ottoq_twin_deal_fault_card`),
--   so which charges fault does not depend on their pace. The guarantee is marginal within a cell and over judged
--   charges, whose nominal runs shorter than the cell's whole population while runs are three hours long; each cell
--   records both medians so the shift is read, not assumed, and the next validation runs are full days.
--
-- ══ §3 WHAT THIS ADDS ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_charge_window_calibration`: one immutable row per fit -- its parameters, the ledger cut-off it read
--   (`evidence_through`), the md5s of the code that produced it, every cell, and a leave-one-run-out read of its own
--   coverage. `public.ottoq_charge_window_evidence(...)`: the judged-charge rows a fit reads, callable on its own so a
--   version can be re-derived from the ledger. `public.ottoq_fit_charge_window_calibration(...)`: writes a version.
--   `public.ottoq_charge_window_factor(version, charger, air)`: the factor the booking writer would use -- the air-band
--   cell when it has at least `min_group_n` judged charges and a factor, else the charger-type cell, else NULL.
--   `public.ottoq_charge_air_band(air, edges)`: the one band function both sides use.
--
-- ══ §4 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   New objects only; nothing certified calls them.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0516 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_charge_window_calibration') IS NOT NULL THEN
    RAISE EXCEPTION '0516 P2: the calibration table already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                  AND table_name = 'ottoq_charge_duration_ledger' AND column_name = 'charge_target_soc') THEN
    RAISE EXCEPTION '0516 P2: 0515 is not applied (the ledger has no charge_target_soc)';
  END IF;
  IF to_regprocedure('public.ottoq_charge_minutes_between(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)') IS NULL THEN
    RAISE EXCEPTION '0516 P2: the charge model is not the one this file reads';
  END IF;
END $premises$;

-- (1) the band both sides use
CREATE FUNCTION public.ottoq_charge_air_band(p_air_c numeric, p_edges_c numeric[])
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $fn$
  SELECT CASE WHEN p_air_c IS NULL THEN NULL
              ELSE chr(97 + (SELECT count(*) FROM unnest(p_edges_c) e WHERE p_air_c >= e)::int) END
$fn$;
COMMENT ON FUNCTION public.ottoq_charge_air_band(numeric, numeric[]) IS
  '0516: the air band a charge is calibrated in: ''a'' below the first edge, ''b'' from it to the next, and so on.';
REVOKE ALL ON FUNCTION public.ottoq_charge_air_band(numeric, numeric[]) FROM PUBLIC, anon, authenticated;

-- (2) the versions
CREATE TABLE public.ottoq_charge_window_calibration (
  calibration_id     bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fitted_at          timestamptz NOT NULL DEFAULT now(),
  depot_id           uuid        NOT NULL,
  method             text        NOT NULL,
  alpha              numeric     NOT NULL CHECK (alpha > 0 AND alpha < 0.5),
  c0                 numeric     NOT NULL CHECK (c0 > 1),
  band_edges_c       numeric[]   NOT NULL,
  min_group_n        integer     NOT NULL CHECK (min_group_n >= 1),
  min_run_minutes    integer     NOT NULL,
  evidence_through   timestamptz NOT NULL,   -- ledger rows recorded at or before this; the ledger is append-only
  code_md5           jsonb       NOT NULL,   -- the evidence reader, the fit and the charge model that produced this
  source_runs        text[]      NOT NULL,
  n_judged           integer     NOT NULL,
  cells              jsonb       NOT NULL,
  loro               jsonb       NOT NULL,
  note               text
);
REVOKE ALL ON public.ottoq_charge_window_calibration FROM anon, authenticated;
COMMENT ON TABLE public.ottoq_charge_window_calibration IS
  '0516 (G240 step 2). One immutable row per fit of the charge booking window: a factor per charger type x air band '
  '(and per charger type) that the charge''s nominal minutes are multiplied by, fitted from ottoq_charge_duration_ledger '
  'by type1_censored_split_conformal_v1 (charges a run''s stop cut short are counted, not dropped). Re-derivable: '
  'ottoq_charge_window_evidence with this row''s parameters and evidence_through returns the rows it read.';

CREATE FUNCTION public.ottoq_charge_window_calibration_append_only()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION 'ottoq_charge_window_calibration is append-only (0516): % refused; fit a new version instead', TG_OP;
END $fn$;
CREATE TRIGGER ottoq_charge_window_calibration_append_only_trg
  BEFORE DELETE OR UPDATE ON public.ottoq_charge_window_calibration
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_window_calibration_append_only();

-- (3) the judged-charge rows a fit reads
CREATE FUNCTION public.ottoq_charge_window_evidence(
  p_depot uuid, p_through timestamptz, p_c0 numeric, p_min_run_minutes integer, p_band_edges_c numeric[])
RETURNS TABLE (session_id uuid, run_key text, charger text, band text, nominal_sel numeric, runway_min numeric,
               stopped_reason text, y numeric, judged boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, twin, ottoq, extensions
AS $fn$
  WITH led AS (
    SELECT l.*, COALESCE(l.sim_run_id::text, 'day:' || to_char(l.started_at AT TIME ZONE 'UTC', 'YYYY-MM-DD')) AS rk
      FROM public.ottoq_charge_duration_ledger l
     WHERE l.depot_id = p_depot AND l.recorded_at <= p_through
       AND (l.run_by IN ('operator_demo', 'production_live') OR l.sim_run_id IS NULL)
       AND l.charger_type IN ('dcfc', 'l2') AND l.ambient_temp_c IS NOT NULL
       AND l.stopped_reason IN ('completed', 'sim_reset')
       AND l.started_at IS NOT NULL AND l.ended_at IS NOT NULL AND l.soc_start IS NOT NULL),
  runs AS (
    SELECT rk, max(ended_at) AS run_end, EXTRACT(epoch FROM max(ended_at) - min(started_at)) / 60 AS span_min
      FROM led GROUP BY rk),
  r AS (
    SELECT led.*, runs.run_end,
           -- the nominal the selection uses: the charge's own stop target where 0515 recorded one, else full (<= 100)
           CASE WHEN led.charge_target_soc IS NOT NULL AND led.charge_target_soc > led.soc_start
                THEN public.ottoq_charge_minutes_between(led.soc_start, led.charge_target_soc, led.charger_kw,
                                                         led.vehicle_kw, led.battery_kwh)
                ELSE public.ottoq_charge_minutes_between(led.soc_start, GREATEST(led.soc_start + 1, 100), led.charger_kw,
                                                         led.vehicle_kw, led.battery_kwh) END AS n_sel,
           EXTRACT(epoch FROM runs.run_end - led.started_at) / 60 AS runway
      FROM led JOIN runs USING (rk)
     WHERE runs.rk LIKE 'day:%' OR runs.span_min >= p_min_run_minutes)
  SELECT r.session_id, r.rk, r.charger_type, public.ottoq_charge_air_band(r.ambient_temp_c, p_band_edges_c),
         round(r.n_sel, 3), round(r.runway, 3), r.stopped_reason,
         CASE WHEN r.stopped_reason = 'completed' THEN LEAST(r.duration_min / r.nominal_min, p_c0) ELSE p_c0 END,
         r.runway >= p_c0 * r.n_sel
    FROM r
   WHERE r.n_sel > 0
     AND (r.stopped_reason <> 'completed' OR (r.nominal_min > 0 AND r.duration_min > 0))
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_charge_window_evidence(uuid, timestamptz, numeric, integer, numeric[]) FROM PUBLIC, anon, authenticated;

-- (4) a fit
CREATE FUNCTION public.ottoq_fit_charge_window_calibration(
  p_depot uuid, p_alpha numeric DEFAULT 0.10, p_c0 numeric DEFAULT 2.0, p_min_group_n integer DEFAULT 30,
  p_min_run_minutes integer DEFAULT 120, p_band_edges_c numeric[] DEFAULT '{5,15,25}',
  p_through timestamptz DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, twin, ottoq, extensions
AS $fn$
DECLARE
  v_through timestamptz;
  v_ev      jsonb;     -- the evidence, read once (it costs a charge-model integration per row)
  v_cells   jsonb;
  v_loro    jsonb;
  v_runs    text[];
  v_n       integer;
  v_code    jsonb;
  v_id      bigint;
BEGIN
  IF p_alpha IS NULL OR p_alpha <= 0 OR p_alpha >= 0.5 OR p_c0 IS NULL OR p_c0 <= 1 OR p_min_group_n IS NULL
     OR p_min_group_n < 1 THEN
    RAISE EXCEPTION 'ottoq_fit_charge_window_calibration: alpha in (0, 0.5), c0 > 1 and min_group_n >= 1 required';
  END IF;
  v_through := COALESCE(p_through, (SELECT max(recorded_at) FROM public.ottoq_charge_duration_ledger WHERE depot_id = p_depot));
  IF v_through IS NULL THEN
    RAISE EXCEPTION 'ottoq_fit_charge_window_calibration: the ledger holds no charge for depot %', p_depot;
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) INTO v_ev
    FROM public.ottoq_charge_window_evidence(p_depot, v_through, p_c0, p_min_run_minutes, p_band_edges_c) e;

  -- cells: charger type x air band, and charger type alone
  WITH ev AS (SELECT * FROM jsonb_to_recordset(v_ev) AS e(session_id uuid, run_key text, charger text, band text,
                nominal_sel numeric, runway_min numeric, stopped_reason text, y numeric, judged boolean)),
  lv AS (SELECT charger, band, y, judged, stopped_reason, nominal_sel, run_key FROM ev
         UNION ALL
         SELECT charger, '*', y, judged, stopped_reason, nominal_sel, run_key FROM ev),
  cell AS (
    SELECT charger, band, count(*) AS n_all,
           count(*) FILTER (WHERE judged) AS n,
           count(*) FILTER (WHERE judged AND stopped_reason <> 'completed') AS n_cut,
           count(DISTINCT run_key) FILTER (WHERE judged) AS runs,
           array_agg(y ORDER BY y) FILTER (WHERE judged) AS ys,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY nominal_sel) FILTER (WHERE judged) AS med_nsel_judged,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY nominal_sel) AS med_nsel_all
      FROM lv GROUP BY charger, band),
  kq AS (SELECT cell.*, ceil((n + 1) * (1 - p_alpha))::int AS k FROM cell)
  SELECT jsonb_object_agg(charger || ':' || band, jsonb_build_object(
           'n_all', n_all, 'n', n, 'n_cut', n_cut, 'runs', runs, 'k', k,
           -- rounded UP to 4 places: a factor rounded down can fall below the k-th score and stop covering it
           'factor', CASE WHEN n > 0 AND k <= n AND ys[k] < p_c0 THEN round(ceil(ys[k] * 10000) / 10000, 4) END,
           'median_ratio', CASE WHEN n > 0 THEN round(ys[GREATEST(1, ceil(n / 2.0)::int)], 4) END,
           'median_nominal_judged', round(med_nsel_judged::numeric, 1),
           'median_nominal_all', round(med_nsel_all::numeric, 1)))
    INTO v_cells FROM kq;

  SELECT array_agg(DISTINCT e.run_key ORDER BY e.run_key), count(*) FILTER (WHERE e.judged)
    INTO v_runs, v_n
    FROM jsonb_to_recordset(v_ev) AS e(run_key text, judged boolean);

  -- leave one run out: each run's judged charges against the cells fitted without it, at the cell the writer would use
  WITH ev AS (SELECT * FROM jsonb_to_recordset(v_ev) AS e(run_key text, charger text, band text, y numeric, judged boolean)),
  held AS (SELECT DISTINCT run_key FROM ev WHERE judged),
  lv AS (SELECT charger, band, y, run_key FROM ev WHERE judged
         UNION ALL
         SELECT charger, '*', y, run_key FROM ev WHERE judged),
  fit AS (
    SELECT h.run_key AS held, lv.charger, lv.band, count(*) AS n, array_agg(lv.y ORDER BY lv.y) AS ys
      FROM held h JOIN lv ON lv.run_key <> h.run_key
     GROUP BY 1, 2, 3),
  q AS (
    SELECT held, charger, band, n,
           CASE WHEN ceil((n + 1) * (1 - p_alpha)) <= n AND ys[ceil((n + 1) * (1 - p_alpha))::int] < p_c0
                THEN round(ceil(ys[ceil((n + 1) * (1 - p_alpha))::int] * 10000) / 10000, 4) END AS f
      FROM fit),
  test AS (
    SELECT e.charger, e.y,
           COALESCE((SELECT q.f FROM q WHERE q.held = e.run_key AND q.charger = e.charger AND q.band = e.band
                                          AND q.n >= p_min_group_n AND q.f IS NOT NULL),
                    (SELECT q.f FROM q WHERE q.held = e.run_key AND q.charger = e.charger AND q.band = '*'
                                          AND q.n >= p_min_group_n AND q.f IS NOT NULL)) AS f_used
      FROM ev e WHERE e.judged)
  SELECT jsonb_build_object(
           'judged', count(*),
           'tested', count(*) FILTER (WHERE f_used IS NOT NULL),
           'covered', count(*) FILTER (WHERE f_used IS NOT NULL AND y <= f_used),
           'coverage', round(avg((y <= f_used)::int) FILTER (WHERE f_used IS NOT NULL), 4),
           'no_factor', count(*) FILTER (WHERE f_used IS NULL),
           'dcfc_coverage', round(avg((y <= f_used)::int) FILTER (WHERE f_used IS NOT NULL AND charger = 'dcfc'), 4),
           'l2_coverage', round(avg((y <= f_used)::int) FILTER (WHERE f_used IS NOT NULL AND charger = 'l2'), 4))
    INTO v_loro FROM test;

  v_code := jsonb_build_object(
    'evidence', md5(pg_get_functiondef('public.ottoq_charge_window_evidence(uuid,timestamptz,numeric,integer,numeric[])'::regprocedure)),
    'fit', md5(pg_get_functiondef('public.ottoq_fit_charge_window_calibration(uuid,numeric,numeric,integer,integer,numeric[],timestamptz,text)'::regprocedure)),
    'band', md5(pg_get_functiondef('public.ottoq_charge_air_band(numeric,numeric[])'::regprocedure)),
    'charge_model', md5(pg_get_functiondef('public.ottoq_charge_minutes_between(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)'::regprocedure)));

  INSERT INTO public.ottoq_charge_window_calibration (
    depot_id, method, alpha, c0, band_edges_c, min_group_n, min_run_minutes, evidence_through, code_md5,
    source_runs, n_judged, cells, loro, note)
  VALUES (p_depot, 'type1_censored_split_conformal_v1', p_alpha, p_c0, p_band_edges_c, p_min_group_n, p_min_run_minutes,
          v_through, v_code, COALESCE(v_runs, '{}'), COALESCE(v_n, 0), COALESCE(v_cells, '{}'::jsonb), v_loro, p_note)
  RETURNING calibration_id INTO v_id;
  RETURN v_id;
END
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_fit_charge_window_calibration(uuid,numeric,numeric,integer,integer,numeric[],timestamptz,text) FROM PUBLIC, anon, authenticated;

-- (5) the factor the booking writer would use
CREATE FUNCTION public.ottoq_charge_window_factor(p_calibration_id bigint, p_charger text, p_air_c numeric)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, twin, ottoq, extensions
AS $fn$
  WITH c AS (SELECT * FROM public.ottoq_charge_window_calibration WHERE calibration_id = p_calibration_id),
  cand AS (
    SELECT 1 AS pref, p_charger || ':' || public.ottoq_charge_air_band(p_air_c, c.band_edges_c) AS cell, c.* FROM c
     WHERE p_air_c IS NOT NULL
    UNION ALL
    SELECT 2, p_charger || ':*', c.* FROM c)
  SELECT jsonb_build_object('factor', (cand.cells -> cand.cell ->> 'factor')::numeric, 'cell', cand.cell,
                            'n', (cand.cells -> cand.cell ->> 'n')::int, 'calibration_id', cand.calibration_id)
    FROM cand
   WHERE (cand.cells -> cand.cell ->> 'n')::int >= cand.min_group_n
     AND (cand.cells -> cand.cell ->> 'factor') IS NOT NULL
   ORDER BY cand.pref
   LIMIT 1
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_charge_window_factor(bigint, text, numeric) FROM PUBLIC, anon, authenticated;

DO $verify$
BEGIN
  -- V1: the objects exist, SECURITY DEFINER where they read the ledger, and the browser keys reach none of them
  IF to_regclass('public.ottoq_charge_window_calibration') IS NULL
     OR has_table_privilege('anon', 'public.ottoq_charge_window_calibration', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ottoq_charge_window_calibration', 'SELECT')
     OR has_function_privilege('anon', 'public.ottoq_fit_charge_window_calibration(uuid,numeric,numeric,integer,integer,numeric[],timestamptz,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_charge_window_evidence(uuid,timestamptz,numeric,integer,numeric[])', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_charge_window_factor(bigint,text,numeric)', 'EXECUTE')
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_charge_window_evidence(uuid,timestamptz,numeric,integer,numeric[])'::regprocedure) THEN
    RAISE EXCEPTION '0516 V1: an object is missing, or a browser key reaches it';
  END IF;
  -- V2: the band function bands as documented
  IF public.ottoq_charge_air_band(4.99, '{5,15,25}') <> 'a' OR public.ottoq_charge_air_band(5, '{5,15,25}') <> 'b'
     OR public.ottoq_charge_air_band(24.9, '{5,15,25}') <> 'c' OR public.ottoq_charge_air_band(25, '{5,15,25}') <> 'd'
     OR public.ottoq_charge_air_band(NULL, '{5,15,25}') IS NOT NULL THEN
    RAISE EXCEPTION '0516 V2: the air band is not as documented';
  END IF;
END $verify$;

-- V3: rolled back. On the twin depot's ledger at a fixed cut-off: (a) two fits of the same evidence are identical in
--     every cell and in their leave-one-run-out read; (b) each cell's factor is the k-th judged score, and no judged
--     score above a finite factor exceeds a (1 - alpha) share; (c) the writer's lookup takes the band cell when it has
--     enough judged charges, the charger cell otherwise, and nothing when neither does; (d) a version refuses UPDATE and
--     DELETE.
DO $v3$
DECLARE
  v_msg text; v_through timestamptz; v_a bigint; v_b bigint; v_c bigint; ca record; cb record; v_refused int := 0;
  v_twin uuid := '11111111-1111-1111-1111-111111111111'; v_f jsonb; v_bad int;
BEGIN
  BEGIN
    SELECT max(recorded_at) INTO v_through FROM public.ottoq_charge_duration_ledger WHERE depot_id = v_twin;
    v_a := public.ottoq_fit_charge_window_calibration(v_twin, 0.10, 2.0, 30, 120, '{5,15,25}', v_through, '0516 V3 a');
    v_b := public.ottoq_fit_charge_window_calibration(v_twin, 0.10, 2.0, 30, 120, '{5,15,25}', v_through, '0516 V3 b');
    SELECT * INTO ca FROM public.ottoq_charge_window_calibration WHERE calibration_id = v_a;
    SELECT * INTO cb FROM public.ottoq_charge_window_calibration WHERE calibration_id = v_b;
    -- (a)
    IF ca.cells IS DISTINCT FROM cb.cells OR ca.loro IS DISTINCT FROM cb.loro OR ca.n_judged <> cb.n_judged
       OR ca.source_runs IS DISTINCT FROM cb.source_runs OR ca.code_md5 IS DISTINCT FROM cb.code_md5
       OR ca.n_judged < 50 OR NOT (ca.cells ? 'dcfc:*') OR NOT (ca.cells ? 'l2:*') THEN
      RAISE EXCEPTION '0516 V3 FAILED (a): two fits of one evidence differ, or the evidence is too thin to test (% judged)', ca.n_judged;
    END IF;
    -- (b) coverage by construction on the fitted cells: every finite factor covers at least its k judged charges
    WITH ev AS (SELECT * FROM public.ottoq_charge_window_evidence(v_twin, v_through, 2.0, 120, '{5,15,25}') WHERE judged),
    cov AS (
      SELECT c.cell, (c.v ->> 'k')::int AS k,
             (SELECT count(*) FROM ev e
               WHERE e.charger = split_part(c.cell, ':', 1)
                 AND (split_part(c.cell, ':', 2) = '*' OR e.band = split_part(c.cell, ':', 2))
                 AND e.y <= (c.v ->> 'factor')::numeric) AS covered
        FROM jsonb_each(ca.cells) c(cell, v)
       WHERE (c.v ->> 'factor') IS NOT NULL)
    SELECT count(*) INTO v_bad FROM cov WHERE covered < k;
    IF v_bad <> 0 THEN RAISE EXCEPTION '0516 V3 FAILED (b): % cell(s) cover fewer judged charges than their k', v_bad; END IF;
    -- (c) the lookup's fallback: a band cell under the minimum falls back to the charger cell; a minimum above every
    --     cell gives nothing
    v_f := public.ottoq_charge_window_factor(v_a, 'dcfc', 20);
    IF v_f IS NULL OR (v_f ->> 'n')::int < 30 OR (v_f ->> 'factor')::numeric <= 0
       OR (v_f ->> 'cell') NOT IN ('dcfc:c', 'dcfc:*')
       OR ((v_f ->> 'cell') = 'dcfc:*' AND ((ca.cells -> 'dcfc:c' ->> 'n')::int >= 30 AND (ca.cells -> 'dcfc:c' ->> 'factor') IS NOT NULL)) THEN
      RAISE EXCEPTION '0516 V3 FAILED (c): the lookup did not take the finest adequate cell: %', v_f;
    END IF;
    v_c := public.ottoq_fit_charge_window_calibration(v_twin, 0.10, 2.0, 100000, 120, '{5,15,25}', v_through, '0516 V3 c');
    IF public.ottoq_charge_window_factor(v_c, 'dcfc', 20) IS NOT NULL OR public.ottoq_charge_window_factor(v_c, 'l2', NULL) IS NOT NULL THEN
      RAISE EXCEPTION '0516 V3 FAILED (c): a version with no adequate cell still gave a factor';
    END IF;
    -- (d) append-only
    BEGIN UPDATE public.ottoq_charge_window_calibration SET note = 'x' WHERE calibration_id = v_a;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%append-only (0516)%' THEN v_refused := v_refused + 1; END IF; END;
    BEGIN DELETE FROM public.ottoq_charge_window_calibration WHERE calibration_id = v_a;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%append-only (0516)%' THEN v_refused := v_refused + 1; END IF; END;
    IF v_refused <> 2 THEN RAISE EXCEPTION '0516 V3 FAILED (d): % of 2 edits refused', v_refused; END IF;

    RAISE EXCEPTION '0516 V3 PASSED: % judged charges; two fits of one evidence identical; every factor covers its k; the lookup takes the finest adequate cell and gives nothing without one; versions are append-only (LORO %)',
      ca.n_judged, ca.loro;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0516 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0516 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: DROP the four functions and the table (it holds only versions; nothing reads them until step 3).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0516_the_booking_window_is_fitted_from_the_charges_with_the_run_s_stop_counted', false,
  'G240 step 2: versioned, append-only calibration of the charge booking window (type1_censored_split_conformal_v1) '
  'fitted from ottoq_charge_duration_ledger. New objects only; nothing certified calls them.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
