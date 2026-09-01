-- 0143: a short arm is inconclusive, and a streak starts at the floor
--
-- Two faults in how a pair is judged and counted. The first was found in the r9 matrix. The
-- second was found looking for what would go wrong in the re-certification that 0139 forces,
-- and would have produced a false green on the first pair.
--
-- ============================================================================
-- FAULT 1 -- a truncated arm is recorded as a determinism failure
-- ============================================================================
--
-- ottoq_determinism_pair gives each arm p_arm_budget_s and EXITs the tick loop when the
-- budget is spent, reached p_ticks or not. The r9 c1 pair came back equal=false with all
-- four streams differing, which reads as a serious engine defect. Its ticks:
--
--   c1  00:46  busy_day 171717/24t   arm_a 24   arm_b 22   -> failed
--   c2  00:58  busy_day 171717/24t   arm_a 24   arm_b 24   -> passed, all streams equal
--
-- Same seed, same scenario, same horizon, twelve minutes apart. The streams differed in c1
-- because one arm did two ticks less work, not because the engine disagreed with itself.
--
-- Nothing in the verdict separates "the arms disagreed" from "an arm did not finish". Both
-- write validation_status='failed' and both break the streak in ottoq_cert_matrix(), so the
-- 'f' characters in the history strings cannot be read as nondeterminism. On the columns
-- with 30+ pairs behind them, some of that history is this.
--
-- A pair where either arm falls short of p_ticks is INCONCLUSIVE. It is a narrow escape
-- hatch and must stay narrow: if BOTH arms reach p_ticks and disagree, that is a failure,
-- permanently, with no appeal. Note also that both arms stopping short at the SAME tick
-- count is still inconclusive -- it is evidence about a horizon nobody asked to certify.
--
-- ottoq_sim_runs already permits the value; the CHECK constraint reads
-- ARRAY['pending','passed','failed','inconclusive']. Nothing to alter.
--
-- Historical rows are not rewritten. c1 stays 'failed' as the evidence it is.
--
-- ============================================================================
-- FAULT 2 -- the streak walks straight through the recert floor
-- ============================================================================
--
-- 0140 gates green on last_pair_at >= recert_floor, but the STREAK behind it counts pairs
-- back through the floor without noticing. That is nearly harmless when a fix changes the
-- canon, because pre-floor pairs then fail the canon match and the streak stops on its own.
--
-- 0139 is precisely the case where it is not harmless. It strengthens the verdict without
-- touching any of the five canon hashes -- endst is not one of them. So every pre-0139 pair
-- still matches the current canon exactly. Under the current code, ONE new passing pair
-- would chain onto those old pairs and report a streak of three or four, and the column
-- would go green having been judged by the new verdict exactly once.
--
-- That is the false green the whole staleness gate exists to prevent, and it would have
-- fired on the first pair of the re-certification 0139 forces. A streak now starts at the
-- floor: a pair older than the floor is never 'unbroken', whatever its hashes say.

BEGIN;

-- ---------------------------------------------------------------------------------------
-- 0. This migration classifies itself (the 0142 convention). It changes the pair VERDICT --
--    a third outcome exists that did not before -- so by the stated rule it forces
--    re-certification and claims no exemption. No pair on record was judged with the
--    inconclusive rule. The practical cost is nil: 0139 already took every column stale
--    and nothing has run since. The point is that the rule is applied when it costs
--    nothing, so it is still there when it costs something.
-- ---------------------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('a_short_arm_is_inconclusive_and_a_streak_starts_at_the_floor', true,
   '0143: adds the inconclusive outcome to the pair verdict and starts every streak at the '
   'recert floor. Verdict change -- forces re-certification.')
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = now();

-- ---------------------------------------------------------------------------------------
-- 1. The pair reports whether each arm finished, and judges accordingly.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE
  v_src text; v_new text; v_anchor text; v_repl text; v_n int;
  c_pin CONSTANT text := 'ac0d25c2c1e0ce5147474ba02882b8ba';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';

  IF v_src IS NULL THEN
    RAISE EXCEPTION '0143: public.ottoq_determinism_pair not found';
  END IF;
  IF md5(v_src) <> c_pin THEN
    RAISE EXCEPTION '0143: ottoq_determinism_pair moved under this migration (pin %, found %)',
      c_pin, md5(v_src);
  END IF;

  -- (a) two more locals
  v_anchor := $a$  v_equal boolean; v_verdict jsonb;$a$;
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0143: declare anchor matched % times, expected 1', v_n; END IF;
  v_repl := $r$  v_equal boolean; v_verdict jsonb;
  v_complete boolean; v_outcome text;$r$;
  v_new := replace(v_src, v_anchor, v_repl);

  -- (b) each arm records whether it reached the requested horizon
  v_anchor := $a$'run', v_run, 'ticks', r.tick_count, 'clock', r.sim_clock_current,$a$;
  v_n := (length(v_new) - length(replace(v_new, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0143: arm-json anchor matched % times, expected 1', v_n; END IF;
  v_repl := $r$'run', v_run, 'ticks', r.tick_count, 'clock', r.sim_clock_current,
      'complete', (r.tick_count >= p_ticks),$r$;
  v_new := replace(v_new, v_anchor, v_repl);

  -- (c) the outcome. Inconclusive ONLY for a short arm; two full arms that differ fail.
  v_anchor := $a$         AND (v_arms[1]->'endst')  = (v_arms[2]->'endst');$a$;
  v_n := (length(v_new) - length(replace(v_new, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0143: verdict anchor matched % times, expected 1', v_n; END IF;
  v_repl := $r$         AND (v_arms[1]->'endst')  = (v_arms[2]->'endst');

  v_complete := COALESCE((v_arms[1]->>'complete')::boolean, false)
            AND COALESCE((v_arms[2]->>'complete')::boolean, false);

  v_outcome := CASE WHEN NOT v_complete THEN 'inconclusive'
                    WHEN v_equal        THEN 'passed'
                    ELSE                     'failed' END;$r$;
  v_new := replace(v_new, v_anchor, v_repl);

  -- (d) carry it in the verdict
  v_anchor := $a$    'equal', v_equal, 'seed', p_seed, 'ticks', p_ticks, 'scenario', p_scenario,$a$;
  v_n := (length(v_new) - length(replace(v_new, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0143: verdict-json anchor matched % times, expected 1', v_n; END IF;
  v_repl := $r$    'equal', v_equal, 'outcome', v_outcome, 'complete', v_complete,
    'seed', p_seed, 'ticks', p_ticks, 'scenario', p_scenario,$r$;
  v_new := replace(v_new, v_anchor, v_repl);

  -- (e) and record it
  v_anchor := $a$     SET validation_status = CASE WHEN v_equal THEN 'passed' ELSE 'failed' END,$a$;
  v_n := (length(v_new) - length(replace(v_new, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0143: status anchor matched % times, expected 1', v_n; END IF;
  v_repl := $r$     SET validation_status = v_outcome,$r$;
  v_new := replace(v_new, v_anchor, v_repl);

  EXECUTE v_new;
END
$do$;

-- ---------------------------------------------------------------------------------------
-- 2. The matrix ignores inconclusive pairs, counts them in the open, and starts every
--    streak at the floor.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE c_pin CONSTANT text := '6ed3eeab42386baf6c9951fd50475a19'; v_pin text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_pin
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
  IF v_pin IS NULL THEN RAISE EXCEPTION '0143: public.ottoq_cert_matrix not found'; END IF;
  IF v_pin <> c_pin THEN
    RAISE EXCEPTION '0143: ottoq_cert_matrix moved under this migration (pin %, found %)', c_pin, v_pin;
  END IF;
END
$do$;

DROP FUNCTION IF EXISTS public.ottoq_cert_matrix(timestamptz);

CREATE FUNCTION public.ottoq_cert_matrix(p_since timestamptz DEFAULT (now() - '30 days'::interval))
RETURNS TABLE(seed bigint, ticks integer, scenario text, pairs_seen integer,
              consecutive_passes integer, green boolean, last_pair_at timestamptz,
              canon_fp text, canon_cmd text, canon_dec text, canon_evt text, canon_bkg text,
              last_run_a uuid, last_run_b uuid, history text,
              stale boolean, recert_floor timestamptz, inconclusive_pairs integer)
LANGUAGE sql STABLE
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
WITH fl AS (
  SELECT public.ottoq_cert_recert_floor() AS rf
), pair AS (
  SELECT DISTINCT ON (r.started_at)
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
   ORDER BY r.started_at, r.sim_run_id
), keyed AS (
  SELECT p.t0, p.ok, p.st,
         (p.j->>'seed')::bigint                    AS c_seed,
         COALESCE((p.j->>'ticks')::int, -1)        AS c_ticks,
         COALESCE(p.j->>'scenario', '?')           AS c_scen,
         p.j->'arm_a'->>'fp'                       AS c_fp,
         p.j->'arm_a'->>'h_cmd'                    AS c_cmd,
         p.j->'arm_a'->>'h_dec'                    AS c_dec,
         p.j->'arm_a'->>'h_evt'                    AS c_evt,
         p.j->'arm_a'->>'h_bkg'                    AS c_bkg,
         (p.j->'arm_a'->>'run')::uuid              AS c_run_a,
         (p.j->'arm_b'->>'run')::uuid              AS c_run_b
    FROM pair p
), inc AS (
  -- Counted and shown, never silently dropped: a column that keeps timing out is a column
  -- whose budget is wrong, and that must be visible rather than absent.
  SELECT c_seed, c_ticks, c_scen, count(*)::int AS n_inc
    FROM keyed WHERE st = 'inconclusive'
   GROUP BY c_seed, c_ticks, c_scen
), col AS (
  SELECT * FROM keyed WHERE st <> 'inconclusive'
), ranked AS (
  SELECT c.*, row_number() OVER (PARTITION BY c.c_seed, c.c_ticks, c.c_scen
                                 ORDER BY c.t0 DESC, c.c_run_a DESC) AS rn
    FROM col c
), canon AS (
  SELECT rk.c_seed, rk.c_ticks, rk.c_scen, rk.c_fp, rk.c_cmd, rk.c_dec, rk.c_evt, rk.c_bkg
    FROM ranked rk WHERE rk.rn = 1
), marked AS (
  SELECT r.c_seed, r.c_ticks, r.c_scen, r.rn,
         (r.ok
          -- A streak starts at the floor. 0139 changed the verdict without moving any canon
          -- hash, so without this a single new pair would chain onto pre-0139 pairs that
          -- still match the canon and report a green earned under the old criterion.
          AND r.t0 >= fl.rf
          AND r.c_fp  IS NOT DISTINCT FROM k.c_fp
          AND r.c_cmd IS NOT DISTINCT FROM k.c_cmd
          AND r.c_dec IS NOT DISTINCT FROM k.c_dec
          AND r.c_evt IS NOT DISTINCT FROM k.c_evt
          AND r.c_bkg IS NOT DISTINCT FROM k.c_bkg) AS on_canon
    FROM ranked r
    JOIN canon k ON k.c_seed = r.c_seed AND k.c_ticks = r.c_ticks AND k.c_scen = r.c_scen
    CROSS JOIN fl
), streak AS (
  SELECT x.c_seed, x.c_ticks, x.c_scen,
         count(*) FILTER (WHERE x.unbroken)::int AS n_pass
    FROM (
      SELECT m.c_seed, m.c_ticks, m.c_scen,
             bool_and(m.on_canon) OVER (PARTITION BY m.c_seed, m.c_ticks, m.c_scen
                                        ORDER BY m.rn
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS unbroken
        FROM marked m
    ) x
   GROUP BY x.c_seed, x.c_ticks, x.c_scen
), hist AS (
  SELECT c.c_seed, c.c_ticks, c.c_scen,
         string_agg(CASE WHEN c.ok THEN 'P' ELSE 'f' END, '' ORDER BY c.t0) AS h_hist,
         count(*)::int AS n_pairs
    FROM col c GROUP BY c.c_seed, c.c_ticks, c.c_scen
)
SELECT h.c_seed, h.c_ticks, h.c_scen, h.n_pairs,
       COALESCE(s.n_pass, 0),
       (COALESCE(s.n_pass, 0) >= 2 AND l.t0 >= fl.rf),
       l.t0, l.c_fp, l.c_cmd, l.c_dec, l.c_evt, l.c_bkg, l.c_run_a, l.c_run_b,
       h.h_hist,
       (l.t0 < fl.rf),
       fl.rf,
       COALESCE(i.n_inc, 0)
  FROM hist h
  JOIN streak s ON s.c_seed = h.c_seed AND s.c_ticks = h.c_ticks AND s.c_scen = h.c_scen
  JOIN ranked l ON l.c_seed = h.c_seed AND l.c_ticks = h.c_ticks
               AND l.c_scen = h.c_scen AND l.rn = 1
  LEFT JOIN inc i ON i.c_seed = h.c_seed AND i.c_ticks = h.c_ticks AND i.c_scen = h.c_scen
  CROSS JOIN fl
 ORDER BY h.c_ticks DESC, h.c_scen, h.c_seed;
$function$;

COMMENT ON FUNCTION public.ottoq_cert_matrix(timestamptz) IS
  'The determinism certification matrix. green requires two consecutive passes on one canon, '
  'both at or after ottoq_cert_recert_floor(). Inconclusive pairs (an arm that did not reach '
  'the requested tick horizon) set no canon and break no streak; they are counted in '
  'inconclusive_pairs so an under-budgeted column stays visible.';

-- ---------------------------------------------------------------------------------------
-- 3. Post-conditions.
-- ---------------------------------------------------------------------------------------
DO $chk$
DECLARE v_pair text; v_green int; v_passes int; v_cols int;
BEGIN
  SELECT regexp_replace(pg_get_functiondef(p.oid), '/\*.*?\*/', '', 'g') INTO v_pair
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

  IF v_pair NOT LIKE '%''complete'', (r.tick_count >= p_ticks)%' THEN
    RAISE EXCEPTION '0143: the arm does not report whether it finished';
  END IF;
  IF v_pair NOT LIKE '%WHEN NOT v_complete THEN ''inconclusive''%' THEN
    RAISE EXCEPTION '0143: a short arm is still not inconclusive';
  END IF;
  IF v_pair NOT LIKE '%SET validation_status = v_outcome,%' THEN
    RAISE EXCEPTION '0143: the recorded status is not the outcome';
  END IF;
  -- The escape hatch must not have swallowed the failure path.
  IF v_pair NOT LIKE '%ELSE                     ''failed'' END%' THEN
    RAISE EXCEPTION '0143: two complete arms that disagree no longer fail';
  END IF;

  -- Every pair on record predates the 0139 floor, so after this change every column must
  -- read zero consecutive passes. If any column still claims a streak, the floor gate in
  -- `marked` is not doing anything and a false green is one pair away.
  SELECT count(*), COALESCE(max(consecutive_passes),0), count(*) FILTER (WHERE green)
    INTO v_cols, v_passes, v_green
    FROM public.ottoq_cert_matrix();

  IF v_cols = 0 THEN
    RAISE EXCEPTION '0143: the matrix returned no columns at all';
  END IF;
  IF v_passes <> 0 THEN
    RAISE EXCEPTION '0143: a column still counts % consecutive passes across the 0139 floor', v_passes;
  END IF;
  IF v_green <> 0 THEN
    RAISE EXCEPTION '0143: % column(s) still green on pre-0139 evidence', v_green;
  END IF;
  RAISE NOTICE '0143: % columns, all at zero passes, none green -- the matrix must be re-earned.', v_cols;
END
$chk$;

COMMIT;
