-- =====================================================================
-- 0205  h_rule may now fail a pair
-- =====================================================================
-- forces_recert = FALSE. Harness only: one fragment in
-- ottoq_determinism_pair puts h_rule into v_equal. A0 pins every body.
-- Requires 0203 and EVIDENCE: this file refuses to apply unless the
-- ledger holds a complete flagship round after 0203 in which every pair
-- carried h_rule on both arms and the arms agreed. That gate is the
-- point: 0203 measured, this enforces, and the order is not negotiable.
-- canon_rule stays out of on_canon; that promotion waits for two rounds
-- after 0204 in which the canon holds (the shield reads the sim clock
-- from 0204, so before it the canon moves with the hour by construction).
-- =====================================================================

BEGIN;

CREATE TEMP TABLE pin_0205 ON COMMIT DROP AS
SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
       md5(pg_get_functiondef(p.oid)) AS h, p.prosecdef
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p');

DO $pre$
DECLARE v_since timestamptz; v_pairs int; v_missing int; v_disagree int; v_cols int; v_src text;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname ~ '^r[0-9]+_')
     OR EXISTS (SELECT 1 FROM pg_stat_activity a
                 WHERE a.query ILIKE '%ottoq_determinism_pair%' AND a.pid <> pg_backend_pid() AND a.state <> 'idle') THEN
    RAISE EXCEPTION '0205 refused: a certification round is scheduled or in flight';
  END IF;
  SELECT classified_at INTO v_since FROM public.ottoq_cert_lineage WHERE name ~ '^0203_';
  IF v_since IS NULL THEN RAISE EXCEPTION '0205 refused: 0203 is not applied'; END IF;

  -- THE EVIDENCE GATE. Flagship pairs since 0203: how many, how many lack
  -- h_rule on either arm, how many disagree, how many distinct columns.
  SELECT count(*),
         count(*) FILTER (WHERE j->'arm_a'->>'h_rule' IS NULL OR j->'arm_b'->>'h_rule' IS NULL),
         count(*) FILTER (WHERE (j->'arm_a'->>'h_rule') IS DISTINCT FROM (j->'arm_b'->>'h_rule')),
         count(DISTINCT (j->>'scenario', j->>'seed', j->>'ticks'))
    INTO v_pairs, v_missing, v_disagree, v_cols
    FROM (SELECT r.validation_notes::jsonb AS j
            FROM public.ottoq_sim_runs r
           WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.run_by = 'cert_harness'
             AND r.started_at > v_since AND r.validation_notes IS NOT NULL
             AND r.sim_run_id = ((r.validation_notes::jsonb)->'arm_a'->>'run')::uuid) p;
  IF v_pairs < 6 OR v_cols < 6 THEN
    RAISE EXCEPTION '0205 refused: only % flagship pairs over % columns since 0203; a complete round (six columns) is the bar', v_pairs, v_cols;
  END IF;
  IF v_missing > 0 THEN
    RAISE EXCEPTION '0205 refused: % flagship pairs since 0203 lack h_rule on an arm', v_missing;
  END IF;
  IF v_disagree > 0 THEN
    RAISE EXCEPTION '0205 refused: % flagship pairs since 0203 DISAGREE on h_rule; that is a finding, not a promotion', v_disagree;
  END IF;

  v_src := pg_get_functiondef('public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'::regprocedure);
  IF v_src !~ $q$'h_rule', public.ottoq_hash_rule_evaluations\(v_run\)$q$ THEN
    RAISE EXCEPTION '0205 refused: the pair does not carry h_rule in the arm object (0203 missing?)';
  END IF;
  IF v_src ~ $q$\(v_arms\[1\]->>'h_rule'\)$q$ THEN
    RAISE EXCEPTION '0205 refused: v_equal already hears h_rule';
  END IF;
  RAISE NOTICE '0205 pre: % flagship pairs over % columns since 0203, none missing h_rule, none disagreeing; promoting', v_pairs, v_cols;
END $pre$;

DO $pair$
DECLARE
  v_def text; v_n int; v_h0 text;
  v_old text := $f$AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks')$f$;
  v_new text := $f$AND (v_arms[1]->>'h_rule') = (v_arms[2]->>'h_rule')   -- 0205: the shield's disposals, enforced after 0203 measured them
         AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks')$f$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'::regprocedure);
  v_h0 := md5(v_def);
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0205: the v_equal ticks fragment occurs % times, expected exactly once', v_n;
  END IF;
  v_def := replace(v_def, v_old, v_new);
  EXECUTE v_def;
  -- reverse proof
  v_def := replace(pg_get_functiondef('public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'::regprocedure), v_new, v_old);
  IF md5(v_def) <> v_h0 THEN
    RAISE EXCEPTION '0205 A1 FAILED: the pair differs from its pin outside the one fragment';
  END IF;
  RAISE NOTICE '0205: v_equal hears h_rule; reverse replacement restores the pin';
END $pair$;

DO $assert$
DECLARE v_changed text[]; v_new text[]; v_src text;
BEGIN
  SELECT array_agg(a.sig ORDER BY a.sig) INTO v_changed
    FROM pin_0205 a
    JOIN (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
                 md5(pg_get_functiondef(p.oid)) AS h, p.prosecdef
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b USING (sig)
   WHERE a.h <> b.h OR a.prosecdef <> b.prosecdef;
  IF v_changed IS DISTINCT FROM ARRAY[
       'public.ottoq_determinism_pair(p_seed bigint, p_ticks integer, p_scenario text, p_depot uuid, p_sim_start timestamp with time zone, p_arm_budget_s integer)'] THEN
    RAISE EXCEPTION '0205 A0 FAILED: function bodies changed = %', v_changed;
  END IF;
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0205 a USING (sig) WHERE a.sig IS NULL;
  IF v_new IS NOT NULL THEN RAISE EXCEPTION '0205 A0 FAILED: new functions = %', v_new; END IF;
  -- the h_rule term sits inside the v_equal assignment, between h_cal and ticks
  v_src := pg_get_functiondef('public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'::regprocedure);
  IF position($q$(v_arms[1]->>'h_rule') = (v_arms[2]->>'h_rule')$q$ in v_src) = 0
     OR position($q$(v_arms[1]->>'h_rule') = (v_arms[2]->>'h_rule')$q$ in v_src) < position($q$(v_arms[1]->>'h_cal')$q$ in v_src)
     OR position($q$(v_arms[1]->>'h_rule') = (v_arms[2]->>'h_rule')$q$ in v_src) > position($q$(v_arms[1]->>'ticks')$q$ in v_src) THEN
    RAISE EXCEPTION '0205 A2 FAILED: the h_rule equality is not where v_equal is assembled';
  END IF;
  RAISE NOTICE '0205: all assertions passed';
END $assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0205_h_rule_may_now_fail_a_pair', FALSE,
  'Harness. v_equal now requires the two arms to agree on h_rule (0203). Applied only after the ledger showed a complete flagship '
  'round since 0203 with h_rule on every arm and no disagreement; the gate is in the file. canon_rule is still not judged in the '
  'matrix (waits for two rounds after 0204).',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;
