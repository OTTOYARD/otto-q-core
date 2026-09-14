-- migration-version: 20260914122818
-- migration-name:    0303_a_bound_that_cannot_be_clamped_must_refuse
--
-- 0303  A BOUND THAT CANNOT BE CLAMPED MUST REFUSE
--
-- G61, open since 0290 and the last thing blocking the twelfth dial.
--
-- public.ottoq_policy_set clamps with
--
--     v_final := GREATEST(v_min, LEAST(v_max, p_param_value));
--
-- which is INCLUSIVE on both sides. It has no way to say "greater than zero",
-- and one dial has needed exactly that since 0290: metres_per_plan_unit, the
-- factor converting the yard's plan units to metres. public.ottoq_site_geometry
-- reads it; public.ottoq_itin_travel_leg multiplies by it as
--
--     v_metres := v_units * v_scale;
--
-- A conversion factor of 0 collapses every distance in the yard to zero metres.
-- A negative one inverts the mapping. Neither is an extreme value that wants
-- clamping -- both are DEGENERATE, the same way a denominator of zero is
-- degenerate. So 0290 deliberately excluded the dial and it has stayed
-- uncatalogued, and therefore unwritable, ever since.
--
-- ---------------------------------------------------------------------------
-- WHY REFUSE RATHER THAN CLAMP
--
-- There is no smallest numeric greater than zero. A clamp needs a value to
-- clamp TO, and an exclusive bound does not have one -- any epsilon would be
-- invented, and inventing a number is the thing this whole catalogue effort
-- has refused to do fourteen files running.
--
-- So an exclusive bound is a VALIDITY constraint, not a clamping one, and it
-- REFUSES:
--
--     {"ok":false,"error":"outside_exclusive_bound", ...}
--
-- which is the shape ottoq_policy_set already uses for unknown_param,
-- invalid_scope_type and scope_id_required. Nothing new for a caller to learn.
--
-- ---------------------------------------------------------------------------
-- THE CATCH-22 THIS FILE IS RESOLVING, WHICH IS WORTH NAMING
--
-- The bound below is DERIVED FROM THE SOURCE, NOT MEASURED, and it could not
-- have been measured: proving what metres_per_plan_unit = 0 does to the yard
-- requires writing 0 to it, and ottoq_policy_set refuses the key precisely
-- because it is uncatalogued. The dial cannot be exercised until it is
-- catalogued, and cataloguing it safely is what this file is for.
--
-- So the claim is made at the strength the evidence supports: the multiply
-- site is quoted, the degeneracy follows from it arithmetically, and this file
-- does not pretend to have run the experiment. Every OTHER bound in the
-- catalogue was read off a clamp, a comparison, a draw's range or a CHECK
-- constraint; this one is read off what a unit-conversion factor IS.
--
-- ---------------------------------------------------------------------------
-- WHY THIS IS SAFE TO DO TO A FUNCTION SEVEN THINGS CALL
--
-- ottoq_policy_set is called by ottoq_agentic_arm, ottoq_apply_ops_action,
-- ottoq_cil_tick, ottoq_fr1_cert_arm, ottoq_ops_set_rush_valve,
-- ottoq_production_start and ottoq_scenario_apply_fleet_overrides -- including
-- the arming and production-start paths. That is not a function to change
-- casually.
--
-- The change is PURELY ADDITIVE and provably inert for every existing row:
-- both new columns are nullable and NULL on all 148 catalogued keys, and a
-- NULL exclusive bound skips the new branch entirely, leaving the same
-- GREATEST/LEAST that ran before. A1 asserts the 148 NULLs. A2 then does not
-- take that on trust -- it re-runs the clamp for EVERY catalogued key that has
-- an inclusive bound, 148 floors and 102 ceilings, and requires each to fire at
-- its own number exactly as before.
--
-- ottoq_policy_set carries SET search_path TO 'twin','ottoq','public',
-- 'extensions'. CREATE OR REPLACE FUNCTION replaces proconfig wholesale; the
-- clause is reproduced verbatim and A6 asserts it survived. That is the
-- 0293/0295 hazard, now on its third appearance in one day.
--
-- forces_recert = FALSE. The two new columns are NULL everywhere so no existing
-- write changes behaviour (A1+A2); ottoq_policy_get -- the read path the decide
-- and tick loops use -- does not read the catalog at all; and the one new
-- catalogue row is for a key with a live global value of 0.4785 that this file
-- does not move (A4).
--
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING
--   ottoq_policy_param_catalog rows                  148 -> 149
--   ottoq_policy_catalog_gap, read_uncatalogued       12 ->  11
--   metres_per_plan_unit in force (global)          0.4785, unchanged
--   every existing key's clamp                       unchanged (A2, 250 checks)
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0303 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0303 P-: a determinism pair is running right now -- it arms '
                    'through ottoq_policy_set and this file replaces it';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0303 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0303 P-: nothing in flight';
END $inflight$;

-- P0. MD5 GUARD on the setter, plus its search_path.
DO $p0$
DECLARE v_md5 text; v_cfg text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)), array_to_string(p.proconfig, ' | ')
    INTO v_md5, v_cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';
  IF v_md5 IS DISTINCT FROM '4e4617342bf36b85cdc49610409229af' THEN
    RAISE EXCEPTION '0303 P0: ottoq_policy_set is not the definition this file was '
                    'written against (live md5 %)', COALESCE(v_md5, '(absent)');
  END IF;
  IF v_cfg IS DISTINCT FROM 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0303 P0: proconfig is %, not the search_path this file reproduces',
                    COALESCE(v_cfg, '(none)');
  END IF;
  RAISE NOTICE '0303 P0: setter md5 and search_path both match';
END $p0$;

-- P1. THE COLUMNS DO NOT EXIST YET, and there is exactly one overload of the
-- setter to replace.
DO $p1$
DECLARE v_cols int; v_overloads int;
BEGIN
  SELECT count(*) INTO v_cols FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_policy_param_catalog'
     AND column_name IN ('min_exclusive','max_exclusive');
  IF v_cols <> 0 THEN
    RAISE EXCEPTION '0303 P1: % exclusive-bound column(s) already exist; re-read '
                    'before adding them again', v_cols;
  END IF;
  SELECT count(*) INTO v_overloads FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_policy_set';
  IF v_overloads <> 1 THEN
    RAISE EXCEPTION '0303 P1: ottoq_policy_set has % overloads; CREATE OR REPLACE '
                    'would leave the others carrying the old clamp', v_overloads;
  END IF;
  RAISE NOTICE '0303 P1: columns absent, exactly one setter overload';
END $p1$;

-- P2. metres_per_plan_unit IS UNCATALOGUED AND ITS ONE LIVE VALUE SURVIVES THE
-- NEW BOUND. A bound that orphans a value already in force is a silent
-- behaviour change dressed as documentation.
DO $p2$
DECLARE v_cat int; v_n int; v_val numeric;
BEGIN
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog
   WHERE param_key = 'metres_per_plan_unit';
  IF v_cat <> 0 THEN
    RAISE EXCEPTION '0303 P2: metres_per_plan_unit is already catalogued';
  END IF;
  SELECT count(*), min(param_value) INTO v_n, v_val FROM public.ottoq_policy_params
   WHERE param_key = 'metres_per_plan_unit';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0303 P2: % live rows for metres_per_plan_unit, expected exactly 1 '
                    '(the global 0.4785 this file reasons about)', v_n;
  END IF;
  IF v_val <= 0 THEN
    RAISE EXCEPTION '0303 P2: the live value is %, which the new exclusive bound '
                    'would orphan', v_val;
  END IF;
  RAISE NOTICE '0303 P2: uncatalogued, one live row at %, survives min_exclusive 0', v_val;
END $p2$;

-- P3. THE BASELINE A2 REGRESSION-TESTS AGAINST. If these move, A2's counts are
-- wrong and it would silently test fewer dials than the catalog holds.
DO $p3$
DECLARE v_total int; v_min int; v_max int; v_bad int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE min_value IS NOT NULL),
         count(*) FILTER (WHERE max_value IS NOT NULL),
         count(*) FILTER (WHERE min_value IS NOT NULL AND max_value IS NOT NULL
                            AND min_value > max_value)
    INTO v_total, v_min, v_max, v_bad
    FROM public.ottoq_policy_param_catalog;
  IF v_total <> 148 OR v_min <> 148 OR v_max <> 102 THEN
    RAISE EXCEPTION '0303 P3: catalog is % rows / % with a floor / % with a ceiling, '
                    'not the 148/148/102 this file predicts against', v_total, v_min, v_max;
  END IF;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0303 P3: % catalog row(s) have min > max; the clamp would be '
                    'incoherent for them and A2 would fail for that reason instead', v_bad;
  END IF;
  RAISE NOTICE '0303 P3: 148 rows, 148 floors, 102 ceilings, none self-contradicting';
END $p3$;

-- P4. THE TWO CONSUMER SITES THE BOUND IS DERIVED FROM ARE STILL THERE.
DO $p4$
DECLARE v_read int; v_mult int;
BEGIN
  SELECT count(*) INTO v_read FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_site_geometry'
     AND position('''metres_per_plan_unit''' in p.prosrc) > 0;
  IF v_read <> 1 THEN
    RAISE EXCEPTION '0303 P4: public.ottoq_site_geometry no longer reads the dial';
  END IF;
  SELECT count(*) INTO v_mult FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_itin_travel_leg'
     AND position('v_metres := v_units * v_scale;' in p.prosrc) > 0;
  IF v_mult <> 1 THEN
    RAISE EXCEPTION '0303 P4: the multiply the degeneracy argument rests on is gone';
  END IF;
  RAISE NOTICE '0303 P4: both consumer sites intact';
END $p4$;

-- S. SNAPSHOT ---------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
  (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0303_pre', 'function', 'public', 'ottoq_policy_set',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';

-- ===========================================================================
-- THE CHANGE
-- ===========================================================================

ALTER TABLE public.ottoq_policy_param_catalog
  ADD COLUMN IF NOT EXISTS min_exclusive numeric,
  ADD COLUMN IF NOT EXISTS max_exclusive numeric;

COMMENT ON COLUMN public.ottoq_policy_param_catalog.min_exclusive IS
'0303 (G61): a STRICT lower bound -- the value must be > this, not >= it. '
'Cannot be clamped (there is no smallest numeric greater than x), so '
'ottoq_policy_set REFUSES a violation with error=outside_exclusive_bound rather '
'than inventing an epsilon. NULL for every dial whose floor is expressible as '
'min_value, which is all but one of them.';

COMMENT ON COLUMN public.ottoq_policy_param_catalog.max_exclusive IS
'0303 (G61): a STRICT upper bound, the mirror of min_exclusive. Nothing uses it '
'yet; it exists so the next dial that needs one does not need another migration '
'to the setter.';

CREATE OR REPLACE FUNCTION public.ottoq_policy_set(p_scope_type text, p_scope_id uuid, p_param_key text, p_param_value numeric, p_by text DEFAULT 'ottocommand'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_min numeric; v_max numeric; v_final numeric; v_minx numeric; v_maxx numeric;
BEGIN
  IF p_scope_type = 'sim_run' THEN p_scope_type := 'run'; END IF;
  IF p_scope_type NOT IN ('global','depot','run') THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_scope_type','scope_type',p_scope_type,
                              'allowed',jsonb_build_array('global','depot','run'));
  END IF;

  -- Global rows key on the sentinel. A caller passing NULL for a global write used to hit
  -- the NOT NULL on a primary-key column; it now lands where ottoq_policy_get reads.
  IF p_scope_type = 'global' THEN
    p_scope_id := '00000000-0000-0000-0000-000000000000'::uuid;
  ELSIF p_scope_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','scope_id_required','scope_type',p_scope_type);
  END IF;

  SELECT min_value, max_value, min_exclusive, max_exclusive
    INTO v_min, v_max, v_minx, v_maxx
    FROM ottoq_policy_param_catalog WHERE param_key = p_param_key;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','unknown_param','param',p_param_key); END IF;
  v_final := GREATEST(v_min, LEAST(v_max, p_param_value));

  -- 0303 (G61): an EXCLUSIVE bound cannot be clamped -- there is no smallest
  -- numeric greater than x, and any epsilon would be invented. It is a validity
  -- constraint, so it REFUSES. Both columns are NULL for every dial whose floor
  -- is expressible inclusively, and a NULL bound skips this branch entirely, so
  -- the clamp above is untouched for all 148 keys catalogued before this file.
  IF (v_minx IS NOT NULL AND v_final <= v_minx)
     OR (v_maxx IS NOT NULL AND v_final >= v_maxx) THEN
    RETURN jsonb_build_object('ok',false,'error','outside_exclusive_bound','param',p_param_key,
                              'requested',p_param_value,'after_inclusive_clamp',v_final,
                              'exclusive_range',jsonb_build_array(v_minx,v_maxx));
  END IF;

  INSERT INTO ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)
    VALUES (p_scope_type, p_scope_id, p_param_key, v_final, p_by)
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value, updated_at = now();
  RETURN jsonb_build_object('ok',true,'param',p_param_key,'requested',p_param_value,'applied',v_final,
                            'clamped', v_final <> p_param_value,'safe_range',jsonb_build_array(v_min,v_max),
                            'exclusive_range',jsonb_build_array(v_minx,v_maxx),
                            'scope_type',p_scope_type);
END;
$function$;

INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, min_exclusive, max_exclusive, affects)
VALUES
  ('metres_per_plan_unit',
   '0303 (G61): metres per yard plan unit -- the factor public.ottoq_site_geometry '
   'publishes and public.ottoq_itin_travel_leg multiplies distances by as '
   'v_metres := v_units * v_scale. STRICTLY GREATER THAN ZERO, which is why this '
   'dial waited from 0290 until the catalog could express an exclusive bound: 0 '
   'collapses every distance in the yard to zero metres and a negative inverts '
   'the mapping, so neither is an extreme value wanting a clamp -- both are '
   'degenerate, like a zero denominator. No ceiling: a large factor makes the '
   'yard slow, not incoherent. DERIVED FROM THE SOURCE, NOT MEASURED, and it '
   'could not have been measured -- proving what 0 does requires writing 0, and '
   'the setter refused the key precisely because it was uncatalogued. Live '
   'GLOBAL row = 0.4785, written 2026-08-13 by claude_geometry_contract, equal '
   'to the caller fallback.',
   0.4785, NULL, NULL, 0, NULL, 'public.ottoq_site_geometry; public.ottoq_itin_travel_leg');

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- A1. The columns exist, are nullable, and are NULL for every key catalogued
-- before this file. That is the whole inertness argument, so it is measured.
DO $a1$
DECLARE v_nullable text; v_nonnull int;
BEGIN
  SELECT string_agg(column_name||':'||is_nullable, ', ' ORDER BY column_name) INTO v_nullable
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_policy_param_catalog'
     AND column_name IN ('min_exclusive','max_exclusive');
  IF v_nullable IS DISTINCT FROM 'max_exclusive:YES, min_exclusive:YES' THEN
    RAISE EXCEPTION 'A1 FAILED: the exclusive columns are %, expected both nullable', v_nullable;
  END IF;
  SELECT count(*) INTO v_nonnull FROM public.ottoq_policy_param_catalog
   WHERE param_key <> 'metres_per_plan_unit'
     AND (min_exclusive IS NOT NULL OR max_exclusive IS NOT NULL);
  IF v_nonnull <> 0 THEN
    RAISE EXCEPTION 'A1 FAILED: % pre-existing key(s) carry an exclusive bound; the '
                    'claim that nothing else changed behaviour is void', v_nonnull;
  END IF;
  RAISE NOTICE 'A1 OK: both columns nullable, NULL on all 148 pre-existing keys';
END $a1$;

-- A2. THE REGRESSION, and it is the point of this file. Every catalogued key
-- that has an inclusive bound must still clamp at exactly its own number. 148
-- floors and 102 ceilings, re-run against a scratch run scope so no live value
-- is touched even before the rollback.
DO $a2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000030300cc'::uuid;
  r record; v_r jsonb; v_floors int := 0; v_ceils int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT param_key, min_value, max_value FROM public.ottoq_policy_param_catalog
       WHERE min_value IS NOT NULL ORDER BY param_key
    LOOP
      v_r := public.ottoq_policy_set('run', v_scratch, r.param_key, r.min_value - 1, '0303_regress');
      IF COALESCE((v_r->>'applied')::numeric, -999999) <> r.min_value
         OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
        RAISE EXCEPTION 'A2 FAILED: %''s floor no longer fires at %: %',
                        r.param_key, r.min_value, v_r;
      END IF;
      v_floors := v_floors + 1;

      IF r.max_value IS NOT NULL THEN
        v_r := public.ottoq_policy_set('run', v_scratch, r.param_key, r.max_value + 1, '0303_regress');
        IF COALESCE((v_r->>'applied')::numeric, -999999) <> r.max_value
           OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
          RAISE EXCEPTION 'A2 FAILED: %''s ceiling no longer fires at %: %',
                          r.param_key, r.max_value, v_r;
        END IF;
        v_ceils := v_ceils + 1;
      END IF;
    END LOOP;

    IF v_floors <> 148 OR v_ceils <> 102 THEN
      RAISE EXCEPTION 'A2 FAILED: re-tested % floors and % ceilings, expected 148 and 102. '
                      'A regression test that covers less than the catalog holds is not a '
                      'regression test.', v_floors, v_ceils;
    END IF;
    RAISE EXCEPTION 'A2_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A2_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A2 OK: 148 floors and 102 ceilings all still fire at their own number';
END $a2$;

-- A3. THE NEW BOUND ACTUALLY REFUSES, at the boundary and below it, and lets a
-- legal value through -- or the refusal is a constant and this passes for the
-- wrong reason.
DO $a3$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000030300cc'::uuid;
  v_zero jsonb; v_neg jsonb; v_ok jsonb;
BEGIN
  BEGIN
    v_zero := public.ottoq_policy_set('run', v_scratch, 'metres_per_plan_unit', 0, '0303_proof');
    IF COALESCE((v_zero->>'ok')::boolean, true)
       OR v_zero->>'error' <> 'outside_exclusive_bound' THEN
      RAISE EXCEPTION 'A3 FAILED: 0 is ON the exclusive bound and must be refused: %', v_zero;
    END IF;

    v_neg := public.ottoq_policy_set('run', v_scratch, 'metres_per_plan_unit', -1, '0303_proof');
    IF COALESCE((v_neg->>'ok')::boolean, true)
       OR v_neg->>'error' <> 'outside_exclusive_bound' THEN
      RAISE EXCEPTION 'A3 FAILED: -1 is below the exclusive bound and must be refused: %', v_neg;
    END IF;

    v_ok := public.ottoq_policy_set('run', v_scratch, 'metres_per_plan_unit', 0.0001, '0303_proof');
    IF NOT COALESCE((v_ok->>'ok')::boolean, false)
       OR COALESCE((v_ok->>'applied')::numeric, -1) <> 0.0001
       OR COALESCE((v_ok->>'clamped')::boolean, true) THEN
      RAISE EXCEPTION 'A3 FAILED: 0.0001 is strictly greater than 0 and must be accepted '
                      'unclamped -- a refusal that refuses everything is not a bound: %', v_ok;
    END IF;

    RAISE EXCEPTION 'A3_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A3_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A3 OK: 0 and -1 refused as outside_exclusive_bound, 0.0001 accepted unclamped';
END $a3$;

-- A4. THE LIVE VALUE DID NOT MOVE. Read back with an impossible caller default
-- so the answer can only have come from the stored row.
DO $a4$
DECLARE v_mpu numeric;
BEGIN
  v_mpu := public.ottoq_policy_get(NULL, 'metres_per_plan_unit', -1);
  IF v_mpu IS DISTINCT FROM 0.4785 THEN
    RAISE EXCEPTION 'A4 FAILED: metres_per_plan_unit in force is %, was 0.4785', v_mpu;
  END IF;
  RAISE NOTICE 'A4 OK: the live global still reads 0.4785 from its stored row';
END $a4$;

-- A5. The counts predicted in the header.
DO $a5$
DECLARE v_cat int; v_gap int;
BEGIN
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog;
  IF v_cat <> 149 THEN
    RAISE EXCEPTION 'A5 FAILED: catalog holds % rows, predicted 149', v_cat;
  END IF;
  SELECT count(*) INTO v_gap FROM public.ottoq_policy_catalog_gap
   WHERE status = 'read_uncatalogued';
  IF v_gap <> 11 THEN
    RAISE EXCEPTION 'A5 FAILED: gap is %, predicted 11', v_gap;
  END IF;
  RAISE NOTICE 'A5 OK: catalog 148 -> 149, gap 12 -> 11';
END $a5$;

-- A6. THE SET CLAUSE SURVIVED. Third time today this has mattered.
DO $a6$
DECLARE v_cfg text;
BEGIN
  SELECT array_to_string(p.proconfig, ' | ') INTO v_cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';
  IF v_cfg IS DISTINCT FROM 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION 'A6 FAILED: proconfig is now %, not the search_path the setter had',
                    COALESCE(v_cfg, '(none)');
  END IF;
  RAISE NOTICE 'A6 OK: search_path preserved verbatim';
END $a6$;

-- A7. NO RESIDUE from A2's 250 scratch writes or A3's probes.
DO $a7$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE scope_id = '00000000-0000-0000-0000-0000030300cc'::uuid
      OR updated_by IN ('0303_regress','0303_proof');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A7 FAILED: % scratch row(s) survived', v_n;
  END IF;
  RAISE NOTICE 'A7 OK: no scratch rows survived';
END $a7$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0303_a_bound_that_cannot_be_clamped_must_refuse', false,
 'G61. Adds nullable min_exclusive/max_exclusive to ottoq_policy_param_catalog and teaches '
 'ottoq_policy_set to REFUSE (error=outside_exclusive_bound) rather than clamp a violation, '
 'because there is no smallest numeric greater than x and any epsilon would be invented. '
 'Catalogues metres_per_plan_unit with min_exclusive 0 -- held since 0290 for exactly this '
 'reason. forces_recert=false: both new columns are NULL on all 148 pre-existing keys so the '
 'GREATEST/LEAST clamp is untouched for every one of them (A1), which A2 then re-tests rather '
 'than assumes across 148 floors and 102 ceilings; ottoq_policy_get, the read path the decide '
 'and tick loops use, does not read the catalog at all; and the one new row is for a key whose '
 'live global 0.4785 this file does not move (A4).',
 now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
