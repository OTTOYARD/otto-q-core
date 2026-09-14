-- migration-version: 20260914131308
-- migration-name:    0306_a_null_dial_value_silently_wrote_the_maximum
--
-- 0306  A NULL DIAL VALUE SILENTLY WROTE THE MAXIMUM, AND SAID ok:true
--
-- MEASURED 2026-09-14, against the live function, rolled back:
--
--   ottoq_policy_set('run', <scope>, 'vehicle_target_soc_default', NULL, ...)
--
--     returns  {"ok": true, "applied": 100, "clamped": null, "requested": null,
--               "safe_range": [20, 100], ...}
--     stores   100
--
-- The dial's catalogued range is 20..100. Passing NULL set it to 100 -- the
-- MAXIMUM -- and reported success. For this particular dial that is "charge
-- every vehicle to 100% SoC"; for an energy factor it is the most aggressive
-- setting available; for a cap it is the loosest.
--
-- ---------------------------------------------------------------------------
-- WHY: THE CLAMP IS NULL-BLIND, AND SO IS THE FLAG THAT WOULD HAVE WARNED YOU
--
--   v_final := GREATEST(v_min, LEAST(v_max, p_param_value));
--
-- GREATEST and LEAST IGNORE NULL ARGUMENTS. With p_param_value NULL,
-- LEAST(v_max, NULL) is v_max, and GREATEST(v_min, v_max) is v_max. The clamp
-- does not fail on NULL -- it treats NULL as "no opinion" and returns the far
-- end of the range.
--
-- That same property is what makes the NULL/NULL convention of 0304 work, so
-- this is not a mistake to rip out; it is a documented behaviour being relied
-- on in one place and silently misfiring in another.
--
-- And the one field a careful caller would check is no help:
--
--   'clamped', v_final <> p_param_value
--
-- `100 <> NULL` is NULL, not true. So the response says clamped: null. A caller
-- doing `if (!res.clamped) { /* my value was taken verbatim */ }` reads a
-- falsy value and concludes nothing was clamped -- when in fact its value was
-- discarded entirely.
--
-- ---------------------------------------------------------------------------
-- AND SINCE 0304 THERE IS A SECOND, DIFFERENT FAILURE
--
-- For the seven dials catalogued min NULL / max NULL, a NULL input produces
-- v_final = NULL and the INSERT hits the NOT NULL on param_value:
--
--   ERROR: 23502 null value in column "param_value" ... violates not-null constraint
--
-- which ESCAPES AS AN EXCEPTION rather than returning the {"ok":false,...} JSON
-- every other refusal path returns. Callers that read the JSON -- which is all
-- of them -- get an exception they do not handle. So the same input produces
-- silent corruption on 153 dials and an unhandled raise on 7.
--
-- ---------------------------------------------------------------------------
-- HAS IT FIRED? NO EVIDENCE THAT IT HAS, AND THAT IS NOT A REASON TO WAIT
--
-- Measured: every live row sitting at its catalogued maximum is a 0..1 gate
-- deliberately set to 1 (energy_reserve_shave, proposer_frame_facts,
-- proposer_hold_enabled -- written by ottoq_prime and proposer_bridge). None
-- looks like NULL damage. The defect is LATENT.
--
-- Its exposure grew today, which is why it is being fixed today rather than
-- filed: 0302 routed the autonomous dial-tuner ottoq_cil_tick through this
-- setter instead of its own INSERT, and 0305 added a foreign key that makes
-- this function the only comfortable way to write the table at all. Every
-- writer this build has pushed toward the setter is a writer newly exposed to
-- its NULL handling -- an LLM-shaped caller emitting a JSON null, a jsonb
-- field that is absent rather than zero, a ::numeric cast of an empty string.
--
-- ---------------------------------------------------------------------------
-- THE FIX: REFUSE, DO NOT GUESS
--
-- A NULL value is a malformed call, not a value out of range, so it is checked
-- with the other ARGUMENT validations (scope_type, scope_id) and BEFORE the
-- catalog lookup -- deliberately: it needs no catalog row to diagnose, it is
-- the cheaper check, and a caller that passed NULL has a bug to fix whether or
-- not the key is also wrong.
--
-- Nothing else in the function changes. The clamp keeps its NULL-ignoring
-- behaviour, which 0304's seven unbounded rows depend on; it simply can no
-- longer be reached with a NULL input.
--
-- A side effect worth naming: with p_param_value guaranteed NOT NULL at the
-- return, `'clamped', v_final <> p_param_value` is now always a real boolean.
-- The clamped:null case disappears with the defect that produced it.
--
-- ---------------------------------------------------------------------------
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING
--   NULL on a bounded dial     writes the max, ok:true  ->  writes NOTHING, ok:false
--   NULL on an unbounded dial  raises 23502             ->  writes NOTHING, ok:false
--   every non-NULL call        unchanged  (A4, full regression over all bounds)
--   exclusive bounds (0303)    unchanged  (A5)
--   unknown_param              unchanged  (A6)
--   proconfig                  PRESERVED  (A1 -- 0302's lesson: CREATE OR
--                              REPLACE drops the SET clause unless reproduced)
--   recert floor               UNMOVED
--
-- forces_recert = FALSE. No caller in any tick or certification path passes a
-- NULL value: P4 measures that every in-database caller of ottoq_policy_set
-- passes a literal or a NOT NULL expression, so no reachable behaviour changes.
-- Only a call that is today silently corrupting a dial behaves differently, and
-- it behaves differently by refusing.
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0306 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0306 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0306 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0306 P-: nothing in flight';
END $inflight$;

-- P0. MD5 GUARD. Replace the definition I actually read, not whatever is there.
DO $p0$
DECLARE v_md5 text; v_cfg text;
BEGIN
  SELECT md5(p.prosrc), array_to_string(p.proconfig,' | ') INTO v_md5, v_cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';
  IF v_md5 IS DISTINCT FROM 'f22a08f2a855df8a0d937815654896d5' THEN
    RAISE EXCEPTION '0306 P0: ottoq_policy_set is not the body this file was written '
                    'against (live prosrc md5 %). Re-read it before replacing it.', v_md5;
  END IF;
  IF v_cfg IS DISTINCT FROM 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0306 P0: proconfig is [%], not the SET clause this file reproduces. '
                    'CREATE OR REPLACE would drop the difference silently.', v_cfg;
  END IF;
  RAISE NOTICE '0306 P0: body md5 and proconfig both match';
END $p0$;

-- P1. REPRODUCE THE DEFECT BEFORE FIXING IT. A fix for a bug that is not there
-- is a change with no justification, and this file's whole header is a claim
-- about live behaviour. Executed, then rolled back.
DO $p1$
DECLARE v_scope uuid := '00000000-0000-0000-0000-0000030600aa'::uuid;
        v_r jsonb; v_written numeric; v_max numeric;
BEGIN
  BEGIN
    SELECT max_value INTO v_max FROM public.ottoq_policy_param_catalog
     WHERE param_key = 'vehicle_target_soc_default';
    IF v_max IS NULL THEN
      RAISE EXCEPTION '0306 P1: vehicle_target_soc_default has no ceiling any more; '
                      'pick another bounded dial to reproduce with';
    END IF;
    v_r := public.ottoq_policy_set('run', v_scope, 'vehicle_target_soc_default', NULL, '0306_repro');
    SELECT param_value INTO v_written FROM public.ottoq_policy_params
     WHERE scope_id = v_scope AND param_key = 'vehicle_target_soc_default';
    IF v_written IS DISTINCT FROM v_max THEN
      RAISE EXCEPTION '0306 P1: passing NULL wrote % (ceiling is %); the defect this file '
                      'fixes does not reproduce, so do not apply it', v_written, v_max;
    END IF;
    IF COALESCE((v_r->>'ok')::boolean, false) IS NOT TRUE THEN
      RAISE EXCEPTION '0306 P1: NULL already refuses (%); the fix may already be in', v_r;
    END IF;
    RAISE EXCEPTION 'P1_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'P1_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE '0306 P1: reproduced -- NULL writes the ceiling and returns ok:true';
END $p1$;

-- P2. NO IN-DATABASE CALLER PASSES A NULL VALUE. This is the forces_recert=false
-- argument. Every call site is read and must pass either a literal number or an
-- expression; a bare NULL third argument anywhere means a tick path relies on
-- today's behaviour and this file would change it.
DO $p2$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(DISTINCT n.nspname||'.'||p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.proname <> 'ottoq_policy_set'
     AND p.prosrc ~* 'ottoq_policy_set\s*\([^)]*,\s*NULL\s*[,)]';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0306 P2: function(s) pass a bare NULL to ottoq_policy_set (%). '
                    'Read each one: if the NULL is the VALUE argument this file changes '
                    'its behaviour and forces_recert must be re-argued.', v_bad;
  END IF;
  RAISE NOTICE '0306 P2: no in-database caller passes a bare NULL argument';
END $p2$;

-- P3. THE UNBOUNDED ROWS EXIST, so A3 tests something real rather than
-- vacuously passing on an empty set.
DO $p3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE min_value IS NULL AND max_value IS NULL;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0306 P3: no NULL/NULL catalog rows; A3 would prove nothing';
  END IF;
  RAISE NOTICE '0306 P3: % unbounded dial(s) to test the second failure mode against', v_n;
END $p3$;

-- ===========================================================================
-- THE FUNCTION. Body reproduced verbatim from the live definition (P0 pins its
-- md5) with ONE addition, marked below, and the SET clause reproduced because
-- CREATE OR REPLACE replaces proconfig wholesale.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ottoq_policy_set(
  p_scope_type text, p_scope_id uuid, p_param_key text, p_param_value numeric,
  p_by text DEFAULT 'ottocommand'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
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

  -- 0306: A NULL VALUE IS A MALFORMED CALL, NOT A VALUE OUT OF RANGE.
  -- It is refused HERE, with the other argument validations and BEFORE the
  -- catalog lookup: it needs no catalog row to diagnose, it is the cheaper
  -- check, and a caller that passed NULL has a bug to fix whether or not the
  -- key is also wrong.
  --
  -- Measured before this guard existed: GREATEST/LEAST IGNORE NULLS, so
  -- GREATEST(v_min, LEAST(v_max, NULL)) is v_max -- a NULL input silently wrote
  -- the dial's MAXIMUM and returned ok:true. Worse, the field that should have
  -- warned was itself NULL-poisoned: `v_final <> p_param_value` is NULL, not
  -- true, so the response said clamped:null and a caller testing !clamped read
  -- it as "taken verbatim". On the seven dials 0304 catalogued NULL/NULL it
  -- failed the other way, raising a raw 23502 out of the INSERT instead of
  -- returning the refusal JSON every other path returns.
  --
  -- The clamp below KEEPS its NULL-ignoring behaviour on the BOUNDS -- that is
  -- what makes an unbounded catalog row mean "admit, clamp nothing" -- it just
  -- can no longer be reached with a NULL input.
  IF p_param_value IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','null_value','param',p_param_key,
                              'detail','param_value must not be NULL; it is not treated as '
                                       '"no change" and was previously clamped to the '
                                       'parameter maximum');
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
$fn$;

-- ===========================================================================
-- A1. THE SET CLAUSE SURVIVED. 0302's lesson, asserted rather than trusted.
DO $a1$
DECLARE v_cfg text;
BEGIN
  SELECT array_to_string(p.proconfig,' | ') INTO v_cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';
  IF v_cfg IS DISTINCT FROM 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION 'A1 FAILED: proconfig is now [%]; CREATE OR REPLACE dropped the '
                    'SET clause', v_cfg;
  END IF;
  RAISE NOTICE 'A1 OK: proconfig preserved';
END $a1$;

-- A2. A NULL ON A BOUNDED DIAL REFUSES AND WRITES NOTHING. The defect P1
-- reproduced, tested at the same dial.
DO $a2$
DECLARE v_scope uuid := '00000000-0000-0000-0000-0000030600cc'::uuid; v_r jsonb; v_n int;
BEGIN
  BEGIN
    v_r := public.ottoq_policy_set('run', v_scope, 'vehicle_target_soc_default', NULL, '0306_proof');
    IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'null_value' THEN
      RAISE EXCEPTION 'A2 FAILED: NULL was not refused with null_value: %', v_r;
    END IF;
    SELECT count(*) INTO v_n FROM public.ottoq_policy_params
     WHERE scope_id = v_scope AND param_key = 'vehicle_target_soc_default';
    IF v_n <> 0 THEN
      RAISE EXCEPTION 'A2 FAILED: a refused NULL still wrote % row(s)', v_n;
    END IF;
    RAISE EXCEPTION 'A2_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A2_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A2 OK: NULL on a bounded dial refuses and writes nothing';
END $a2$;

-- A3. A NULL ON AN UNBOUNDED DIAL REFUSES IN JSON -- not as a raw 23502. The
-- second failure mode, which only existed after 0304 and which a fix aimed
-- only at the clamp would have missed.
DO $a3$
DECLARE v_scope uuid := '00000000-0000-0000-0000-0000030600cc'::uuid;
        v_r jsonb; r record; v_n int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT param_key FROM public.ottoq_policy_param_catalog
       WHERE min_value IS NULL AND max_value IS NULL ORDER BY param_key
    LOOP
      v_r := public.ottoq_policy_set('run', v_scope, r.param_key, NULL, '0306_proof');
      IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'null_value' THEN
        RAISE EXCEPTION 'A3 FAILED: % did not refuse NULL with null_value: %', r.param_key, v_r;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    IF v_n < 7 THEN
      RAISE EXCEPTION 'A3 FAILED: only % unbounded dial(s) tested, expected at least 7', v_n;
    END IF;
    RAISE EXCEPTION 'A3_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A3_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A3 OK: every unbounded dial refuses NULL in JSON, no raw 23502';
END $a3$;

-- A4. EVERY NON-NULL BEHAVIOUR IS UNCHANGED. Full regression over every bound
-- in the catalog -- the same shape 0303 and 0304 ran, so a drop in the check
-- count is itself a failure.
DO $a4$
DECLARE
  v_scope uuid := '00000000-0000-0000-0000-0000030600cc'::uuid;
  v_r jsonb; r record; v_checks int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT param_key, min_value, max_value, min_exclusive, max_exclusive
        FROM public.ottoq_policy_param_catalog ORDER BY param_key
    LOOP
      IF r.min_value IS NOT NULL AND r.min_exclusive IS NULL THEN
        v_r := public.ottoq_policy_set('run', v_scope, r.param_key, r.min_value - 1, '0306_proof');
        IF COALESCE((v_r->>'applied')::numeric, -999999) <> r.min_value
           OR COALESCE((v_r->>'clamped')::boolean, false) IS NOT TRUE THEN
          RAISE EXCEPTION 'A4 FAILED: %''s floor no longer clamps to % with clamped=true: %',
                          r.param_key, r.min_value, v_r;
        END IF;
        v_checks := v_checks + 1;
      END IF;
      IF r.max_value IS NOT NULL AND r.max_exclusive IS NULL THEN
        v_r := public.ottoq_policy_set('run', v_scope, r.param_key, r.max_value + 1, '0306_proof');
        IF COALESCE((v_r->>'applied')::numeric, -999999) <> r.max_value
           OR COALESCE((v_r->>'clamped')::boolean, false) IS NOT TRUE THEN
          RAISE EXCEPTION 'A4 FAILED: %''s ceiling no longer clamps to % with clamped=true: %',
                          r.param_key, r.max_value, v_r;
        END IF;
        v_checks := v_checks + 1;
      END IF;
    END LOOP;
    IF v_checks < 255 THEN
      RAISE EXCEPTION 'A4 FAILED: only % bound checks ran; 0304 ran 255, so fewer means '
                      'bounds vanished', v_checks;
    END IF;
    RAISE EXCEPTION 'A4_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A4_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A4 OK: every catalogued bound still clamps, and clamped is a real boolean';
END $a4$;

-- A5. THE OTHER TWO REFUSAL PATHS ARE UNTOUCHED: 0303's exclusive bound, and
-- the allow-list. A NULL guard inserted in the wrong place could shadow either.
DO $a5$
DECLARE v_scope uuid := '00000000-0000-0000-0000-0000030600cc'::uuid; v_r jsonb;
BEGIN
  BEGIN
    v_r := public.ottoq_policy_set('run', v_scope, 'metres_per_plan_unit', 0, '0306_proof');
    IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'outside_exclusive_bound' THEN
      RAISE EXCEPTION 'A5 FAILED: 0303''s exclusive floor no longer refuses 0: %', v_r;
    END IF;
    v_r := public.ottoq_policy_set('run', v_scope, 'no_such_dial_0306', 1, '0306_proof');
    IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'unknown_param' THEN
      RAISE EXCEPTION 'A5 FAILED: the allow-list no longer refuses an unknown key: %', v_r;
    END IF;
    v_r := public.ottoq_policy_set('bogus_scope', v_scope, 'metres_per_plan_unit', 1, '0306_proof');
    IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'invalid_scope_type' THEN
      RAISE EXCEPTION 'A5 FAILED: scope validation changed: %', v_r;
    END IF;
    RAISE EXCEPTION 'A5_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A5_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A5 OK: exclusive bound, allow-list and scope validation all unchanged';
END $a5$;

-- A6. A NORMAL WRITE STILL WORKS END TO END, and clamped is false rather than
-- null for a value inside the range.
DO $a6$
DECLARE v_scope uuid := '00000000-0000-0000-0000-0000030600cc'::uuid; v_r jsonb; v_v numeric;
BEGIN
  BEGIN
    v_r := public.ottoq_policy_set('run', v_scope, 'vehicle_target_soc_default', 77, '0306_proof');
    SELECT param_value INTO v_v FROM public.ottoq_policy_params
     WHERE scope_id = v_scope AND param_key = 'vehicle_target_soc_default';
    IF NOT COALESCE((v_r->>'ok')::boolean, false) OR v_v <> 77
       OR COALESCE((v_r->>'clamped')::boolean, true) IS NOT FALSE THEN
      RAISE EXCEPTION 'A6 FAILED: an in-range write is wrong (returned %, stored %)', v_r, v_v;
    END IF;
    RAISE EXCEPTION 'A6_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A6_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A6 OK: an in-range write stores the value and reports clamped=false';
END $a6$;

-- A7. NO RESIDUE.
DO $a7$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE scope_id IN ('00000000-0000-0000-0000-0000030600aa'::uuid,
                      '00000000-0000-0000-0000-0000030600cc'::uuid)
      OR updated_by IN ('0306_repro','0306_proof');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A7 FAILED: % probe row(s) survived', v_n;
  END IF;
  RAISE NOTICE 'A7 OK: no probe rows survived';
END $a7$;

-- ===========================================================================
-- LINEAGE, written here in the migration.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0306_a_null_dial_value_silently_wrote_the_maximum', false,
        'Adds a NULL guard to public.ottoq_policy_set and changes nothing else; the '
        'body is otherwise byte-identical (P0 pinned the prior md5) and the SET clause '
        'is reproduced (A1). Only a call passing a NULL value behaves differently, and '
        'P2 measured that no in-database caller passes a bare NULL argument, so no tick '
        'or certification path can reach the changed branch. Before: a NULL silently '
        'wrote the dial MAXIMUM with ok:true and clamped:null on the 153 bounded rows, '
        'and raised a raw 23502 on the 7 unbounded ones. After: {"ok":false,'
        '"error":"null_value"} and no write.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- A8. THE FLOOR DID NOT MOVE.
DO $a8$
DECLARE v_floor timestamptz;
BEGIN
  SELECT public.ottoq_cert_recert_floor() INTO v_floor;
  IF v_floor <> '2026-09-12 16:50:23.319089+00'::timestamptz THEN
    RAISE EXCEPTION 'A8 FAILED: recert floor moved to % -- this file classified itself '
                    'forces_recert=false and must not unstreak any column', v_floor;
  END IF;
  RAISE NOTICE 'A8 OK: recert floor unmoved at %', v_floor;
END $a8$;
