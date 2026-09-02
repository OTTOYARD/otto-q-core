-- =====================================================================
-- 0149  The matrix is keyed by depot, and reads the energy canon
-- =====================================================================
-- public.ottoq_cert_matrix keyed columns on (seed, ticks, scenario) only.
-- validation_notes carries no depot at all (checked: 0 of 354 eligible
-- rows mention either depot uuid), so the depot must come from the run
-- row, ottoq_sim_runs.depot_id. Without it, pairs run at a second depot
-- would collapse into the flagship's columns and corrupt canon.
--
-- Also: 0148 adds h_nrg to each arm. If the matrix does not compare it
-- across pairs, a column can pass both pairs and still disagree with
-- itself on the energy stream - exactly the inter-pair gap that kept
-- 424242/12t off green for the command stream. canon_nrg is therefore
-- added to the canon comparison. Rows that predate 0148 have NULL h_nrg
-- on both sides; IS NOT DISTINCT FROM treats NULL=NULL as equal, and the
-- 0148 floor puts those rows below the streak anyway.
--
-- RETURNS TABLE changes, so CREATE OR REPLACE is not permitted:
-- DROP + CREATE. No caller exists (no pg_proc body, view, or cron job
-- references ottoq_cert_matrix - verified), so this is safe.
--
-- Classified forces_recert = FALSE: this changes no hash and no engine
-- behaviour; it is a reader. Registered explicitly because absence from
-- the register means "forces recert" (0140).
--
-- Regression check: the new matrix restricted to the flagship depot
-- must equal the old matrix row-for-row on every pre-existing column.
-- =====================================================================

-- 1. Pin, arity, no callers.
DO $pin$
DECLARE v_pin text; v_n int;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)), count(*) OVER () INTO v_pin, v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
  IF v_n <> 1 THEN RAISE EXCEPTION '0149 expected 1 arity, found %', v_n; END IF;
  IF v_pin IS DISTINCT FROM '39f1adbd7204952506c5a575cc6694a7' THEN
    RAISE EXCEPTION '0149 pin mismatch ottoq_cert_matrix: %', v_pin;
  END IF;
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.proname <> 'ottoq_cert_matrix'
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g') ~ 'ottoq_cert_matrix';
  IF v_n <> 0 THEN RAISE EXCEPTION '0149 found % function(s) calling ottoq_cert_matrix; DROP is not safe', v_n; END IF;
  SELECT count(*) INTO v_n FROM pg_views WHERE definition ~ 'ottoq_cert_matrix';
  IF v_n <> 0 THEN RAISE EXCEPTION '0149 found % view(s) using ottoq_cert_matrix', v_n; END IF;
END $pin$;

-- 2. Capture the old output for the regression check.
CREATE TEMP TABLE pg_temp_0149_before AS
SELECT seed, ticks, scenario, pairs_seen, consecutive_passes, green, last_pair_at,
       canon_fp, canon_cmd, canon_dec, canon_evt, canon_bkg, last_run_a, last_run_b,
       history, stale, recert_floor, inconclusive_pairs
  FROM public.ottoq_cert_matrix();

DO $cap$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_temp_0149_before;
  IF v_n <> 6 THEN RAISE EXCEPTION '0149 expected 6 flagship columns before, found %', v_n; END IF;
END $cap$;

-- 3. Replace.
DROP FUNCTION public.ottoq_cert_matrix(timestamp with time zone);

CREATE FUNCTION public.ottoq_cert_matrix(p_since timestamp with time zone DEFAULT (now() - '30 days'::interval))
 RETURNS TABLE(depot uuid, seed bigint, ticks integer, scenario text, pairs_seen integer, consecutive_passes integer, green boolean, last_pair_at timestamp with time zone, canon_fp text, canon_cmd text, canon_dec text, canon_evt text, canon_bkg text, canon_nrg text, last_run_a uuid, last_run_b uuid, history text, stale boolean, recert_floor timestamp with time zone, inconclusive_pairs integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
WITH fl AS (
  SELECT public.ottoq_cert_recert_floor() AS rf
), pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at)
         r.depot_id                              AS c_depot,
         r.started_at                            AS t0,
         r.validation_status                     AS st,
         (r.validation_status = 'passed')        AS ok,
         (r.validation_notes::jsonb)             AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness'
     AND r.started_at >= p_since
     AND r.validation_status IS NOT NULL
     AND r.validation_notes IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb) -> 'arm_a') = 'object'
   ORDER BY r.depot_id, r.started_at, r.sim_run_id
), keyed AS (
  SELECT p.c_depot, p.t0, p.ok, p.st,
         (p.j->>'seed')::bigint                    AS c_seed,
         COALESCE((p.j->>'ticks')::int, -1)        AS c_ticks,
         COALESCE(p.j->>'scenario', '?')           AS c_scen,
         p.j->'arm_a'->>'fp'                       AS c_fp,
         p.j->'arm_a'->>'h_cmd'                    AS c_cmd,
         p.j->'arm_a'->>'h_dec'                    AS c_dec,
         p.j->'arm_a'->>'h_evt'                    AS c_evt,
         p.j->'arm_a'->>'h_bkg'                    AS c_bkg,
         p.j->'arm_a'->>'h_nrg'                    AS c_nrg,
         (p.j->'arm_a'->>'run')::uuid              AS c_run_a,
         (p.j->'arm_b'->>'run')::uuid              AS c_run_b
    FROM pair p
), inc AS (
  SELECT c_depot, c_seed, c_ticks, c_scen, count(*)::int AS n_inc
    FROM keyed WHERE st = 'inconclusive'
   GROUP BY c_depot, c_seed, c_ticks, c_scen
), col AS (
  SELECT * FROM keyed WHERE st <> 'inconclusive'
), ranked AS (
  SELECT c.*, row_number() OVER (PARTITION BY c.c_depot, c.c_seed, c.c_ticks, c.c_scen
                                 ORDER BY c.t0 DESC, c.c_run_a DESC) AS rn
    FROM col c
), canon AS (
  SELECT rk.c_depot, rk.c_seed, rk.c_ticks, rk.c_scen,
         rk.c_fp, rk.c_cmd, rk.c_dec, rk.c_evt, rk.c_bkg, rk.c_nrg
    FROM ranked rk WHERE rk.rn = 1
), marked AS (
  SELECT r.c_depot, r.c_seed, r.c_ticks, r.c_scen, r.rn,
         (r.ok
          AND r.t0 >= fl.rf
          AND r.c_fp  IS NOT DISTINCT FROM k.c_fp
          AND r.c_cmd IS NOT DISTINCT FROM k.c_cmd
          AND r.c_dec IS NOT DISTINCT FROM k.c_dec
          AND r.c_evt IS NOT DISTINCT FROM k.c_evt
          AND r.c_bkg IS NOT DISTINCT FROM k.c_bkg
          AND r.c_nrg IS NOT DISTINCT FROM k.c_nrg) AS on_canon
    FROM ranked r
    JOIN canon k ON k.c_depot = r.c_depot AND k.c_seed = r.c_seed
                AND k.c_ticks = r.c_ticks AND k.c_scen = r.c_scen
    CROSS JOIN fl
), streak AS (
  SELECT x.c_depot, x.c_seed, x.c_ticks, x.c_scen,
         count(*) FILTER (WHERE x.unbroken)::int AS n_pass
    FROM (
      SELECT m.c_depot, m.c_seed, m.c_ticks, m.c_scen,
             bool_and(m.on_canon) OVER (PARTITION BY m.c_depot, m.c_seed, m.c_ticks, m.c_scen
                                        ORDER BY m.rn
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS unbroken
        FROM marked m
    ) x
   GROUP BY x.c_depot, x.c_seed, x.c_ticks, x.c_scen
), hist AS (
  SELECT c.c_depot, c.c_seed, c.c_ticks, c.c_scen,
         string_agg(CASE WHEN c.ok THEN 'P' ELSE 'f' END, '' ORDER BY c.t0) AS h_hist,
         count(*)::int AS n_pairs
    FROM col c GROUP BY c.c_depot, c.c_seed, c.c_ticks, c.c_scen
)
SELECT h.c_depot, h.c_seed, h.c_ticks, h.c_scen, h.n_pairs,
       COALESCE(s.n_pass, 0),
       (COALESCE(s.n_pass, 0) >= 2 AND l.t0 >= fl.rf),
       l.t0, l.c_fp, l.c_cmd, l.c_dec, l.c_evt, l.c_bkg, l.c_nrg, l.c_run_a, l.c_run_b,
       h.h_hist,
       (l.t0 < fl.rf),
       fl.rf,
       COALESCE(i.n_inc, 0)
  FROM hist h
  JOIN streak s ON s.c_depot = h.c_depot AND s.c_seed = h.c_seed AND s.c_ticks = h.c_ticks AND s.c_scen = h.c_scen
  JOIN ranked l ON l.c_depot = h.c_depot AND l.c_seed = h.c_seed AND l.c_ticks = h.c_ticks
               AND l.c_scen = h.c_scen AND l.rn = 1
  LEFT JOIN inc i ON i.c_depot = h.c_depot AND i.c_seed = h.c_seed AND i.c_ticks = h.c_ticks AND i.c_scen = h.c_scen
  CROSS JOIN fl
 ORDER BY h.c_depot, h.c_ticks DESC, h.c_scen, h.c_seed;
$function$;

-- 4. Regression: flagship rows identical to before on every old column.
DO $reg$
DECLARE v_new int; v_diff int; v_sig text;
BEGIN
  SELECT pg_get_function_result(p.oid) INTO v_sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
  IF v_sig NOT LIKE 'TABLE(depot uuid, seed bigint,%canon_nrg text,%' THEN
    RAISE EXCEPTION '0149 unexpected result signature: %', v_sig;
  END IF;

  SELECT count(*) INTO v_new FROM public.ottoq_cert_matrix() m
   WHERE m.depot = '11111111-1111-1111-1111-111111111111';
  IF v_new <> 6 THEN RAISE EXCEPTION '0149 expected 6 flagship columns after, found %', v_new; END IF;

  SELECT count(*) INTO v_diff
    FROM pg_temp_0149_before b
    FULL JOIN (SELECT * FROM public.ottoq_cert_matrix() m
                WHERE m.depot = '11111111-1111-1111-1111-111111111111') a
      ON a.seed=b.seed AND a.ticks=b.ticks AND a.scenario=b.scenario
   WHERE a.seed IS NULL OR b.seed IS NULL
      OR a.pairs_seen         IS DISTINCT FROM b.pairs_seen
      OR a.consecutive_passes IS DISTINCT FROM b.consecutive_passes
      OR a.green              IS DISTINCT FROM b.green
      OR a.last_pair_at       IS DISTINCT FROM b.last_pair_at
      OR a.canon_fp           IS DISTINCT FROM b.canon_fp
      OR a.canon_cmd          IS DISTINCT FROM b.canon_cmd
      OR a.canon_dec          IS DISTINCT FROM b.canon_dec
      OR a.canon_evt          IS DISTINCT FROM b.canon_evt
      OR a.canon_bkg          IS DISTINCT FROM b.canon_bkg
      OR a.last_run_a         IS DISTINCT FROM b.last_run_a
      OR a.last_run_b         IS DISTINCT FROM b.last_run_b
      OR a.history            IS DISTINCT FROM b.history
      OR a.stale              IS DISTINCT FROM b.stale
      OR a.recert_floor       IS DISTINCT FROM b.recert_floor
      OR a.inconclusive_pairs IS DISTINCT FROM b.inconclusive_pairs;
  IF v_diff <> 0 THEN
    RAISE EXCEPTION '0149 regression: % flagship row(s) differ from the pre-change matrix', v_diff;
  END IF;

  -- the matrix must run for the non-default argument too
  PERFORM count(*) FROM public.ottoq_cert_matrix(now() - interval '1 day');
END $reg$;

DROP TABLE pg_temp_0149_before;

-- 5. Classify: a reader, not an engine change. Explicitly exempt.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0149_the_matrix_is_keyed_by_depot_and_reads_the_energy_canon', false,
        'ottoq_cert_matrix keyed by (depot, seed, ticks, scenario); canon_nrg added to the inter-pair comparison. No hash or engine change; regression-checked identical for the flagship.',
        now())
ON CONFLICT (name) DO UPDATE
   SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note, classified_at = EXCLUDED.classified_at;
