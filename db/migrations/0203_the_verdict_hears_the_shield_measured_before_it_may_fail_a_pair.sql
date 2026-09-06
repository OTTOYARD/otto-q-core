-- =====================================================================
-- 0203  The verdict hears the shield: h_rule, measured before it may
--       fail a pair
-- =====================================================================
-- forces_recert = FALSE. Harness only. One function is new
-- (ottoq_hash_rule_evaluations), the pair's arm object gains h_rule, the
-- matrix gains canon_rule. No engine body changes; A0 pins every body in
-- public, ottoq and twin. Requires 0202 (the column it hashes by).
--
-- WHY IT EXISTS
-- ---------------------------------------------------------------------
-- 0202 made every rule evaluation name its run. The verdict still could
-- not see the shield: ottoq_determinism_pair hashes commands, decisions,
-- events, bookings, energy, proposals, deferrals and the priors, and not
-- one of them says which rule allowed, warned or blocked what. Two arms
-- could dispose identically while the Layer-1 shield reasoned
-- differently on the way there, and the pair would pass. From this
-- migration each arm carries h_rule: md5 over the run's evaluations as a
-- content multiset of (rule_code, rule_version, action_context,
-- entity_type, entity_id, passed, severity, enforcement,
-- enforcement_taken, parameters_used). Excluded on purpose: ids and
-- timestamps (volatile), duration_ms (a stopwatch), reason, context and
-- result_payload (they carry per-run uuids -- leg_id, visit_needs_id --
-- and wall-clock-derived values such as local_time and age_seconds).
-- entity_id is kept because in the newest 20,000 rows every entity is a
-- vehicle or a BESS unit -- permanent ids, not per-run ones.
--
-- MEASURED, NOT YET ENFORCED, and why
-- ---------------------------------------------------------------------
-- h_rule goes into the arm object and the matrix column, and NOT into
-- v_equal or on_canon. Two reasons, one for each.
--   Within a pair the two arms run in one transaction, so NOW() is the
--   same for both and no evaluator calls clock_timestamp(); the arms are
--   expected to agree. But there is no retro evidence -- every row before
--   0202 has sim_run_id NULL -- so the first flagship measurements are
--   round 21's. A3 below runs a live pair on the grid fixture (seconds)
--   and requires the arms to agree; the flagship round is the second
--   witness. After it, the promotion into v_equal is one line.
--   Across pairs the canon will move with the wall clock until G15 lands:
--   six active evaluators read NOW() and nothing else (SLA.003, SLA.006,
--   and TW.001/003/004/005 through ottoq_depot_local_time), so a round
--   run at 00:11 CT and a round run at 11:00 CT get different
--   operational-hours and quiet-hours answers for the same simulated day.
--   canon_rule is reported so that movement is visible; it is not judged
--   until the shield reads the sim clock.
-- A measurement that could fail the round on day one would be an
-- assertion about the shield's purity that nobody has tested. This is
-- the test.
-- =====================================================================

BEGIN;

CREATE TEMP TABLE pin_0203 ON COMMIT DROP AS
SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
       md5(pg_get_functiondef(p.oid)) AS h,
       p.prosecdef
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p');

CREATE TEMP TABLE pre_0203 ON COMMIT DROP AS
SELECT has_function_privilege('anon',          'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') AS m_anon,
       has_function_privilege('authenticated', 'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') AS m_auth,
       has_function_privilege('service_role',  'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE') AS m_svc,
       has_function_privilege('anon',          'public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)', 'EXECUTE') AS p_anon,
       has_function_privilege('service_role',  'public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)', 'EXECUTE') AS p_svc;

-- ---------------------------------------------------------------------
-- 0. Preconditions.
-- ---------------------------------------------------------------------
DO $pre$
DECLARE v_h text;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname ~ '^r[0-9]+_')
     OR EXISTS (SELECT 1 FROM pg_stat_activity a
                 WHERE a.query ILIKE '%ottoq_determinism_pair%' AND a.pid <> pg_backend_pid() AND a.state <> 'idle') THEN
    RAISE EXCEPTION '0203 refused: a certification round is scheduled or in flight';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0203 refused: a sim run is running';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name ~ '^0202_') THEN
    RAISE EXCEPTION '0203 refused: 0202 is not applied (no lineage row)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.ottoq_rule_evaluations'::regclass AND attname = 'sim_run_id' AND NOT attisdropped) THEN
    RAISE EXCEPTION '0203 refused: ottoq_rule_evaluations.sim_run_id does not exist';
  END IF;
  SELECT h INTO v_h FROM pin_0203
   WHERE sig = 'public.ottoq_determinism_pair(p_seed bigint, p_ticks integer, p_scenario text, p_depot uuid, p_sim_start timestamp with time zone, p_arm_budget_s integer)';
  IF v_h IS DISTINCT FROM '176a41d68ddb69cf98c44b2ab683f15c' THEN
    RAISE EXCEPTION '0203 refused: ottoq_determinism_pair is not the body this file was written against (md5 %)', v_h;
  END IF;
  SELECT h INTO v_h FROM pin_0203 WHERE sig = 'public.ottoq_cert_matrix(p_since timestamp with time zone)';
  IF v_h IS DISTINCT FROM 'c607932b524b6a519c39c0416c9a7f1e' THEN
    RAISE EXCEPTION '0203 refused: ottoq_cert_matrix is not the body this file was written against (md5 %)', v_h;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_hash_rule_evaluations') THEN
    RAISE EXCEPTION '0203 refused: ottoq_hash_rule_evaluations already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = 'aacd0bb0-2d02-d101-72cc-33f70e950bc8')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_scenarios s WHERE s.scenario_code = 'grid_smoke' AND s.status = 'active'
                       AND s.depot_id = 'aacd0bb0-2d02-d101-72cc-33f70e950bc8') THEN
    RAISE EXCEPTION '0203 refused: the grid fixture (grid-0169-smoke) or its bound scenario grid_smoke is missing; A3 needs a live pair';
  END IF;
  RAISE NOTICE '0203 pre: 0202 present, bodies pinned, grid fixture present, nothing in flight';
END $pre$;

-- ---------------------------------------------------------------------
-- 1. The hash. Content multiset, ordered by content, NULL-proof.
-- ---------------------------------------------------------------------
CREATE FUNCTION public.ottoq_hash_rule_evaluations(p_run uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
  -- 0203. The run's Layer-1 disposals as a content multiset. Order is by
  -- content, not by evaluation_seq: the sequence is a wall-clock artefact
  -- shared across every run in the ledger. Every nullable field is
  -- COALESCEd so a NULL cannot drop a row from the hash. reason, context
  -- and result_payload are excluded: they carry per-run uuids and
  -- wall-clock-derived values (see the 0203 header).
  SELECT md5(COALESCE(string_agg(
           e.rule_code || '|' || COALESCE(e.rule_version::text,'-') || '|' || COALESCE(e.action_context,'-')
           || '|' || COALESCE(e.entity_type,'-') || '|' || COALESCE(e.entity_id::text,'-')
           || '|' || COALESCE(e.passed::text,'-') || '|' || COALESCE(e.severity,'-')
           || '|' || COALESCE(e.enforcement,'-') || '|' || COALESCE(e.enforcement_taken,'-')
           || '|' || COALESCE(e.parameters_used::text,'-'),
           E'\n' ORDER BY e.rule_code, COALESCE(e.rule_version::text,'-'), COALESCE(e.action_context,'-'),
                          COALESCE(e.entity_type,'-'), COALESCE(e.entity_id::text,'-'),
                          COALESCE(e.passed::text,'-'), COALESCE(e.severity,'-'),
                          COALESCE(e.enforcement,'-'), COALESCE(e.enforcement_taken,'-'),
                          COALESCE(e.parameters_used::text,'-')), ''))
    FROM public.ottoq_rule_evaluations e
   WHERE e.sim_run_id = p_run;
$function$;
COMMENT ON FUNCTION public.ottoq_hash_rule_evaluations(uuid) IS
  '0203: md5 over the run''s ottoq_rule_evaluations as a content multiset (rule_code, rule_version, action_context, entity_type, entity_id, passed, severity, enforcement, enforcement_taken, parameters_used). Excludes ids, timestamps, duration_ms, reason, context, result_payload. This is h_rule in the pair verdict: measured from 0203, enforced when a flagship round has shown the arms agree.';

-- ---------------------------------------------------------------------
-- 2. The pair, from the catalog: the arm object gains h_rule. One fragment.
-- ---------------------------------------------------------------------
DO $pair$
DECLARE
  v_def text; v_n int;
  v_old text := $f$'h_cal', v_boot->'calibration'->>'h')$f$;
  v_new text := $f$'h_cal', v_boot->'calibration'->>'h', 'h_rule', public.ottoq_hash_rule_evaluations(v_run))$f$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'::regprocedure);
  IF md5(v_def) <> '176a41d68ddb69cf98c44b2ab683f15c' THEN
    RAISE EXCEPTION '0203 step 2: the pair body moved between the pin and the rewrite';
  END IF;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0203 step 2: the arm-object fragment occurs % times, expected exactly once', v_n;
  END IF;
  v_def := replace(v_def, v_old, v_new);
  EXECUTE v_def;
  RAISE NOTICE '0203 step 2: ottoq_determinism_pair rewritten from the catalog (h_rule in the arm object)';
END $pair$;

-- ---------------------------------------------------------------------
-- 3. The matrix, from the catalog: canon_rule appended, not judged.
--    RETURNS TABLE changes, so DROP then CREATE; the text is taken before
--    the drop. Four fragments.
-- ---------------------------------------------------------------------
DO $mx$
DECLARE
  v_def text; v_n int; i int;
  v_old text[] := ARRAY[
    $f$canon_defr text, canon_cal text)$f$,
    $f$p.j->'arm_a'->>'h_cal'$f$,
    $f$rk.c_prop, rk.c_defr, rk.c_cal$f$,
    $f$l.c_prop, l.c_defr, l.c_cal$f$];
  v_new text[] := ARRAY[
    $f$canon_defr text, canon_cal text, canon_rule text)$f$,
    $f$p.j->'arm_a'->>'h_rule'                   AS c_rule,   -- 0203; NULL before 0203; reported, not judged (G15)
         p.j->'arm_a'->>'h_cal'$f$,
    $f$rk.c_prop, rk.c_defr, rk.c_cal, rk.c_rule$f$,
    $f$l.c_prop, l.c_defr, l.c_cal, l.c_rule$f$];
BEGIN
  v_def := pg_get_functiondef('public.ottoq_cert_matrix(timestamptz)'::regprocedure);
  IF md5(v_def) <> 'c607932b524b6a519c39c0416c9a7f1e' THEN
    RAISE EXCEPTION '0203 step 3: the matrix body moved between the pin and the rewrite';
  END IF;
  FOR i IN 1..4 LOOP
    v_n := (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0203 step 3: matrix fragment % occurs % times, expected exactly once', i, v_n;
    END IF;
    v_def := replace(v_def, v_old[i], v_new[i]);
  END LOOP;
  DROP FUNCTION public.ottoq_cert_matrix(timestamp with time zone);
  EXECUTE v_def;
  RAISE NOTICE '0203 step 3: ottoq_cert_matrix dropped and recreated from the catalog (canon_rule appended)';
END $mx$;

-- ---------------------------------------------------------------------
-- ASSERTIONS
-- ---------------------------------------------------------------------
DO $assert$
DECLARE
  v_changed text[]; v_new text[]; v_def text; v_pair jsonb; v_a uuid; v_b uuid; v_n bigint; v_x text;
BEGIN
  -- ── A0. THE PIN. Pair and matrix changed, the hash is new, nothing else; SECURITY DEFINER flags as pinned.
  SELECT array_agg(a.sig ORDER BY a.sig) INTO v_changed
    FROM pin_0203 a
    JOIN (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
                 md5(pg_get_functiondef(p.oid)) AS h, p.prosecdef
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b USING (sig)
   WHERE a.h <> b.h OR a.prosecdef <> b.prosecdef;
  IF v_changed IS DISTINCT FROM ARRAY[
       'public.ottoq_cert_matrix(p_since timestamp with time zone)',
       'public.ottoq_determinism_pair(p_seed bigint, p_ticks integer, p_scenario text, p_depot uuid, p_sim_start timestamp with time zone, p_arm_budget_s integer)'] THEN
    RAISE EXCEPTION '0203 A0 FAILED: function bodies changed = %', v_changed;
  END IF;
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0203 a USING (sig)
   WHERE a.sig IS NULL;
  IF v_new IS DISTINCT FROM ARRAY['public.ottoq_hash_rule_evaluations(p_run uuid)'] THEN
    RAISE EXCEPTION '0203 A0 FAILED: new functions = %', v_new;
  END IF;
  IF (SELECT prosecdef FROM pg_proc WHERE proname = 'ottoq_hash_rule_evaluations') THEN
    RAISE EXCEPTION '0203 A0 FAILED: the hash is SECURITY DEFINER';
  END IF;
  RAISE NOTICE '0203 A0: pin holds; pair and matrix changed, hash new';

  -- ── A1. Both rewritten bodies revert to their pins under the reverse replacements.
  v_def := pg_get_functiondef('public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'::regprocedure);
  v_def := replace(v_def, $f$'h_cal', v_boot->'calibration'->>'h', 'h_rule', public.ottoq_hash_rule_evaluations(v_run))$f$,
                          $f$'h_cal', v_boot->'calibration'->>'h')$f$);
  IF md5(v_def) <> '176a41d68ddb69cf98c44b2ab683f15c' THEN
    RAISE EXCEPTION '0203 A1 FAILED: the pair differs from its pin outside the one fragment';
  END IF;
  v_def := pg_get_functiondef('public.ottoq_cert_matrix(timestamptz)'::regprocedure);
  v_def := replace(v_def, $f$canon_defr text, canon_cal text, canon_rule text)$f$, $f$canon_defr text, canon_cal text)$f$);
  v_def := replace(v_def, $f$p.j->'arm_a'->>'h_rule'                   AS c_rule,   -- 0203; NULL before 0203; reported, not judged (G15)
         p.j->'arm_a'->>'h_cal'$f$, $f$p.j->'arm_a'->>'h_cal'$f$);
  v_def := replace(v_def, $f$rk.c_prop, rk.c_defr, rk.c_cal, rk.c_rule$f$, $f$rk.c_prop, rk.c_defr, rk.c_cal$f$);
  v_def := replace(v_def, $f$l.c_prop, l.c_defr, l.c_cal, l.c_rule$f$, $f$l.c_prop, l.c_defr, l.c_cal$f$);
  IF md5(v_def) <> 'c607932b524b6a519c39c0416c9a7f1e' THEN
    RAISE EXCEPTION '0203 A1 FAILED: the matrix differs from its pin outside the four fragments';
  END IF;
  RAISE NOTICE '0203 A1: pair and matrix revert to their pins under the reverse replacements';

  -- ── A2. An empty stream hashes to md5(''), like every other h_*.
  IF public.ottoq_hash_rule_evaluations('00000000-0000-4000-8000-000000000000') <> md5('') THEN
    RAISE EXCEPTION '0203 A2 FAILED: empty stream does not hash to md5('''')';
  END IF;

  -- ── A3. LIVE. A six-tick pair on the grid fixture (seconds): both arms carry
  --        h_rule, they agree, the stream is non-empty, the hash recomputes from
  --        the ledger after the fact, and 0202's reader answers a number for a
  --        post-0202 run.
  v_pair := public.ottoq_determinism_pair(424242, 6, 'grid_smoke', 'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid,
                                          '2026-09-01 02:00:00+00'::timestamptz, 120);
  IF NOT COALESCE((v_pair->>'equal')::boolean, false) THEN
    RAISE EXCEPTION '0203 A3 FAILED: the grid pair did not pass (outcome %)', v_pair->>'outcome';
  END IF;
  v_a := (v_pair->'arm_a'->>'run')::uuid;  v_b := (v_pair->'arm_b'->>'run')::uuid;
  IF v_pair->'arm_a'->>'h_rule' IS NULL OR v_pair->'arm_b'->>'h_rule' IS NULL THEN
    RAISE EXCEPTION '0203 A3 FAILED: an arm carries no h_rule (%)', v_pair;
  END IF;
  IF (v_pair->'arm_a'->>'h_rule') <> (v_pair->'arm_b'->>'h_rule') THEN
    RAISE EXCEPTION '0203 A3 FAILED: the arms disagree on h_rule: % vs %', left(v_pair->'arm_a'->>'h_rule',8), left(v_pair->'arm_b'->>'h_rule',8);
  END IF;
  IF (v_pair->'arm_a'->>'h_rule') = md5('') THEN
    RAISE EXCEPTION '0203 A3 FAILED: the grid arms evaluated no rules; the instrument has nothing to see';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations e WHERE e.sim_run_id = v_a;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0203 A3 FAILED: arm % has no run-scoped evaluations after the pair', v_a;
  END IF;
  IF public.ottoq_hash_rule_evaluations(v_a) <> (v_pair->'arm_a'->>'h_rule') THEN
    RAISE EXCEPTION '0203 A3 FAILED: h_rule does not recompute from the ledger for arm %', v_a;
  END IF;
  v_x := public.ottoq_tick_invariance_metrics(v_a) ->> 'unsafe_blocks';
  IF v_x IS NULL THEN
    RAISE EXCEPTION '0203 A3 FAILED: tick_invariance_metrics answers NULL for a post-0202 run';
  END IF;
  RAISE NOTICE '0203 A3: grid pair % / %: h_rule % on both arms over % evaluations; unsafe_blocks=%',
    v_a, v_b, left(v_pair->'arm_a'->>'h_rule',8), v_n, v_x;

  -- ── A4. The matrix reports canon_rule: populated for the grid column just
  --        written, NULL for every flagship column (no flagship pair has it yet).
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_matrix(now() - interval '1 hour') m
                  WHERE m.depot = 'aacd0bb0-2d02-d101-72cc-33f70e950bc8' AND m.canon_rule = (v_pair->'arm_a'->>'h_rule')) THEN
    RAISE EXCEPTION '0203 A4 FAILED: the grid column does not report the pair''s h_rule as canon_rule';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_matrix(now() - interval '30 days') m
              WHERE m.depot = '11111111-1111-1111-1111-111111111111' AND m.canon_rule IS NOT NULL) THEN
    RAISE EXCEPTION '0203 A4 FAILED: a flagship column reports canon_rule before any flagship pair carried h_rule';
  END IF;
  RAISE NOTICE '0203 A4: canon_rule populated on the grid column, NULL on flagship';

  -- ── A5. Privileges on the pair and the matrix are what they were.
  IF (SELECT m_anon FROM pre_0203) IS DISTINCT FROM has_function_privilege('anon',          'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE')
     OR (SELECT m_auth FROM pre_0203) IS DISTINCT FROM has_function_privilege('authenticated', 'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE')
     OR (SELECT m_svc FROM pre_0203) IS DISTINCT FROM has_function_privilege('service_role',  'public.ottoq_cert_matrix(timestamptz)', 'EXECUTE')
     OR (SELECT p_anon FROM pre_0203) IS DISTINCT FROM has_function_privilege('anon',         'public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)', 'EXECUTE')
     OR (SELECT p_svc FROM pre_0203) IS DISTINCT FROM has_function_privilege('service_role',  'public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)', 'EXECUTE') THEN
    RAISE EXCEPTION '0203 A5 FAILED: a privilege on the pair or the matrix moved';
  END IF;
  RAISE NOTICE '0203 A5: privileges unchanged';
  RAISE NOTICE '0203: all assertions passed';
END $assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0203_the_verdict_hears_the_shield_measured_before_it_may_fail_a_pair', FALSE,
  'Harness. Each pair arm now carries h_rule = ottoq_hash_rule_evaluations(run): the run''s Layer-1 disposals as a content '
  'multiset (rule_code, rule_version, action_context, entity_type, entity_id, passed, severity, enforcement, enforcement_taken, '
  'parameters_used). Measured, not enforced: not in v_equal and not in on_canon. The matrix reports canon_rule. A3 ran a live '
  'six-tick grid pair and the arms agreed. Promotion into v_equal follows the first flagship round in which every pair agrees; '
  'promotion into on_canon follows G15 (six evaluators read the wall clock, so the canon moves with the hour until then). '
  'No engine body changed.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;
