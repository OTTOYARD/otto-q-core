-- =====================================================================
-- 0202  Every evaluation names its run, and the two arms of a pair
--       stop sharing one clock
-- =====================================================================
-- forces_recert = TRUE. One decide-path body changes
-- (public.ottoq_evaluate_rule_core: its INSERT gains a column, nothing
-- upstream of the row moves), one metrics reader changes
-- (public.ottoq_tick_invariance_metrics), nothing is new. A0 pins every
-- body in public, ottoq and twin; A2 proves each rewritten body differs
-- from its pinned text in exactly the named fragments and nowhere else.
--
-- THE FINDING (pre-Part-B trace, G5; re-measured 2026-09-06 16:00 UTC)
-- ---------------------------------------------------------------------
-- public.ottoq_rule_evaluations is the L1 ledger: one row per rule
-- evaluation, append-only (trg_ottoq_rule_evaluations_no_delete), 5.09M
-- rows by planner estimate, 4.7 GB, evaluation_seq 10,015,191 at the
-- read. It carries no sim_run_id and no data_source. Its one writer,
-- public.ottoq_evaluate_rule_core, already resolves the active run
-- (v_run := ottoq.ottoq_active_sim_run_id()) and stamps it on every
-- event it emits -- the newest linked fail event carries sim_run_id
-- bcde8d08-4d17-4dbe-ad0c-596933f69610, data_source 'twin' -- and then
-- writes the ledger row without it.
--
-- The trace called wall-clock windowing "unreliable when arms overlap".
-- It is worse than unreliable. evaluated_at is NOW(), transaction time,
-- and a certification pair runs both arms in one transaction: the 300
-- newest rows (evaluation_seq 10014892..10015191, written by round 19's
-- last pair) carry ONE evaluated_at, 2026-09-06 05:11:00.094288+00, for
-- two runs. correlation_id is NULL on all 300; triggered_by_event_id is
-- NULL on all 300. The only per-run scoping any reader can do today is
-- by the clock, and the clock cannot separate the two arms of any pair
-- ever run. public.ottoq_tick_invariance_metrics does exactly that
-- (unsafe_blocks counts SLA.001 failures WHERE evaluated_at >=
-- r.started_at), so for every pair it has counted the other arm's
-- blocks as its own.
--
-- No hashed stream reads this table: ottoq_determinism_pair,
-- ottoq_boot_state_fingerprint and the ottoq_hash_* family do not
-- reference it (prosrc scan of every function in public, ottoq, twin).
-- The verdict is blind to the shield today. Recorded, not fixed, here:
-- naming the run is the prerequisite for hashing per run.
--
-- WHAT CHANGES
-- ---------------------------------------------------------------------
--   1. ottoq_rule_evaluations.sim_run_id uuid NULL, FK to ottoq_sim_runs
--      NOT VALID, ON DELETE NO ACTION -- the shape ottoq_events uses;
--      check (c) of the run-scope registry forbids CASCADE. Metadata-only
--      on 5.09M rows. NULL means production, exactly as on ottoq_events
--      and ottoq_service_detail_records. NO BACKFILL: the rows that exist
--      can only be attributed by the clock, and the clock is the defect.
--   2. A partial index (sim_run_id, evaluation_seq) WHERE sim_run_id IS
--      NOT NULL. Every existing row is NULL, so it starts empty; without
--      it the registry-driven purge (DELETE ... WHERE sim_run_id =
--      ANY(doomed)) would walk 4.7 GB per demo-run start.
--   3. The evaluator's INSERT gains the column, populated from the v_run
--      it already holds. Taken from the live catalog, md5-pinned, three
--      fragment replacements, no retyping (the 0200 technique).
--   4. Registry row, class 'engine' ("run-scoped working data; must not
--      outlive its run") -- the class of ottoq_events and the SDRs. A
--      twin run's evaluations die with the run when
--      ottoq_purge_prior_runs purges it (its only caller is
--      ottoq_start_demo_run, and it is the only function that deletes
--      from ottoq_sim_runs at all); production rows are never matched by
--      that DELETE. The wall-clock retention walk in
--      ottoq_retention_purge_worker is unchanged.
--   5. ottoq_tick_invariance_metrics.unsafe_blocks scopes by sim_run_id.
--      For a run that started before this migration's lineage timestamp
--      it returns NULL: those rows cannot be attributed, and a number
--      there would be the old wrong number.
--   6. Hardening found on the way, same table: anon and authenticated
--      hold TRUNCATE, TRIGGER and REFERENCES on the ledger (0198 inspected
--      seven operational tables and found SELECT only; this one was not
--      among them). The append-only trigger does not fire on TRUNCATE.
--      Revoked. SELECT stays; the tenant RLS policy governs it.
--
-- NOT CHANGED, and why
-- ---------------------------------------------------------------------
--   - data_source: derivable (sim_run_id IS NULL), not added.
--   - evaluated_at = NOW(): still transaction time. Sim time on the
--     ledgers is G11 and lands with the event stream, not here.
--   - The verdict: h_rule (the shield's disposals per arm) is the next
--     instrument now that rows name their run. It is a harness change
--     and is filed for the next migration, not folded into this one.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- The pin. Every function body in the three engine schemas, before.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE pin_0202 ON COMMIT DROP AS
SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
       md5(pg_get_functiondef(p.oid)) AS h,
       p.prosecdef
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p');

-- ---------------------------------------------------------------------
-- 0. Preconditions. The file was written against these exact bodies and
--    this exact shape; anything else and the replacements below would be
--    guesses. And never under a certification round.
-- ---------------------------------------------------------------------
DO $pre$
DECLARE v_h text;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname ~ '^r[0-9]+_')
     OR EXISTS (SELECT 1 FROM pg_stat_activity a
                 WHERE a.query ILIKE '%ottoq_determinism_pair%' AND a.pid <> pg_backend_pid() AND a.state <> 'idle') THEN
    RAISE EXCEPTION '0202 refused: a certification round is scheduled or in flight';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0202 refused: a sim run is running';
  END IF;

  SELECT h INTO v_h FROM pin_0202
   WHERE sig = 'public.ottoq_evaluate_rule_core(p_rule_code text, p_entity_type text, p_entity_id uuid, p_context jsonb, p_action_context text, p_fleet_operator_id uuid, p_depot_id uuid, p_triggered_by_event_id uuid, p_override_id uuid)';
  IF v_h IS DISTINCT FROM '3456fb4cc35cd22fcaf64ae682ca4800' THEN
    RAISE EXCEPTION '0202 refused: ottoq_evaluate_rule_core is not the body this file was written against (md5 %)', v_h;
  END IF;
  SELECT h INTO v_h FROM pin_0202 WHERE sig = 'public.ottoq_tick_invariance_metrics(p_sim_run_id uuid)';
  IF v_h IS DISTINCT FROM '501848c0186d4ae4eac82d3777a08f28' THEN
    RAISE EXCEPTION '0202 refused: ottoq_tick_invariance_metrics is not the body this file was written against (md5 %)', v_h;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.ottoq_rule_evaluations'::regclass AND attname = 'sim_run_id' AND NOT attisdropped) THEN
    RAISE EXCEPTION '0202 refused: ottoq_rule_evaluations.sim_run_id already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_rule_evaluations') THEN
    RAISE EXCEPTION '0202 refused: ottoq_rule_evaluations is already in the run-scope registry';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname NOT IN ('pg_catalog','information_schema')
         AND p.prosrc ~* 'insert\s+into\s+(public\.)?ottoq_rule_evaluations') <> 1 THEN
    RAISE EXCEPTION '0202 refused: the ledger no longer has exactly one writer';
  END IF;
  RAISE NOTICE '0202 pre: bodies pinned, column absent, one writer, nothing in flight';
END $pre$;

-- ---------------------------------------------------------------------
-- 1. The column, its key, its index.
-- ---------------------------------------------------------------------
ALTER TABLE public.ottoq_rule_evaluations ADD COLUMN sim_run_id uuid;

ALTER TABLE public.ottoq_rule_evaluations
  ADD CONSTRAINT fk_ottoq_rule_evaluations_sim_run
  FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id) NOT VALID;

CREATE INDEX idx_ottoq_evals_sim_run
  ON public.ottoq_rule_evaluations (sim_run_id, evaluation_seq)
  WHERE sim_run_id IS NOT NULL;

COMMENT ON COLUMN public.ottoq_rule_evaluations.sim_run_id IS
  '0202: the run this evaluation was made in (ottoq.ottoq_active_sim_run_id() at write time). NULL = production. Rows written before 0202 are NULL and were never backfilled: only the clock could attribute them, and the clock cannot separate the arms of a pair.';

-- ---------------------------------------------------------------------
-- 2. The evaluator, from the catalog. Three fragments, each required to
--    occur exactly once in the pinned body; then EXECUTE.
-- ---------------------------------------------------------------------
DO $ev$
DECLARE
  v_def text;
  v_old text[] := ARRAY[
    'override_id, correlation_id',
    'p_override_id, v_correlation',
    'THE AUDIT RECORD. UNCHANGED, and it is the complete one.'];
  v_new text[] := ARRAY[
    'override_id, correlation_id, sim_run_id',
    'p_override_id, v_correlation, v_run',
    'THE AUDIT RECORD. 0202: it now names its run (sim_run_id := v_run; NULL is production).'];
  v_n int; i int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_evaluate_rule_core(text,text,uuid,jsonb,text,uuid,uuid,uuid,uuid)'::regprocedure);
  IF md5(v_def) <> '3456fb4cc35cd22fcaf64ae682ca4800' THEN
    RAISE EXCEPTION '0202 step 2: evaluator body moved between the pin and the rewrite';
  END IF;
  FOR i IN 1..3 LOOP
    v_n := (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0202 step 2: fragment % occurs % times in the evaluator, expected exactly once', i, v_n;
    END IF;
    v_def := replace(v_def, v_old[i], v_new[i]);
  END LOOP;
  EXECUTE v_def;
  RAISE NOTICE '0202 step 2: ottoq_evaluate_rule_core rewritten from the catalog (3 fragments)';
END $ev$;

-- ---------------------------------------------------------------------
-- 3. The one run-scoped reader, from the catalog. Two fragments.
-- ---------------------------------------------------------------------
DO $tim$
DECLARE
  v_def text;
  v_old text[] := ARRAY[
    '(SELECT count(*) FROM ottoq_rule_evaluations e',
    'AND e.evaluated_at >= r.started_at),'];
  v_new text[] := ARRAY[
    'CASE WHEN r.started_at < (SELECT l.classified_at FROM ottoq_cert_lineage l WHERE l.name ~ ''^0202_'' LIMIT 1) THEN NULL ELSE (SELECT count(*) FROM ottoq_rule_evaluations e',
    'AND e.sim_run_id = p_sim_run_id) END,'];
  v_n int; i int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_tick_invariance_metrics(uuid)'::regprocedure);
  IF md5(v_def) <> '501848c0186d4ae4eac82d3777a08f28' THEN
    RAISE EXCEPTION '0202 step 3: tick_invariance_metrics body moved between the pin and the rewrite';
  END IF;
  FOR i IN 1..2 LOOP
    v_n := (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0202 step 3: fragment % occurs % times in tick_invariance_metrics, expected exactly once', i, v_n;
    END IF;
    v_def := replace(v_def, v_old[i], v_new[i]);
  END LOOP;
  EXECUTE v_def;
  RAISE NOTICE '0202 step 3: ottoq_tick_invariance_metrics rewritten from the catalog (2 fragments)';
END $tim$;

-- ---------------------------------------------------------------------
-- 4. The registry. Class engine: dies with its run, like the events.
-- ---------------------------------------------------------------------
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public','ottoq_rule_evaluations','sim_run_id','engine',
        '0202: a twin run''s rule evaluations die with the run; production evaluations (NULL sim_run_id) persist under the wall-clock retention walk. Rows from before 0202 are NULL and unattributable.')
ON CONFLICT (table_schema, table_name, column_name) DO NOTHING;

-- ---------------------------------------------------------------------
-- 5. The ledger is append-only for everyone, including TRUNCATE.
-- ---------------------------------------------------------------------
REVOKE TRUNCATE, TRIGGER, REFERENCES ON public.ottoq_rule_evaluations FROM anon, authenticated;

-- ---------------------------------------------------------------------
-- ASSERTIONS
-- ---------------------------------------------------------------------
DO $assert$
DECLARE
  v_changed text[]; v_new text[]; v_def text; v_run uuid; v_eid1 uuid; v_eid2 uuid;
  v_got uuid; v_passed boolean; v_reason text; v_rows bigint; v_blk int; v_warn int;
  v_ctx jsonb := jsonb_build_object(
    'vehicle_id', '0cb1b8c6-c948-4937-8bf6-187442a7be1a',
    'depot_id', '11111111-1111-1111-1111-111111111111',
    'fleet_operator_id', '22222222-2222-2222-2222-222222222222',
    'action', 'task_start', 'now_ts', '2026-09-01T14:00:00+00:00', 'probe', '0202');
BEGIN
  -- ── A0. THE PIN. Two bodies changed, nothing new, both still SECURITY DEFINER as pinned.
  SELECT array_agg(a.sig ORDER BY a.sig) INTO v_changed
    FROM pin_0202 a
    JOIN (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
                 md5(pg_get_functiondef(p.oid)) AS h, p.prosecdef
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b USING (sig)
   WHERE a.h <> b.h OR a.prosecdef <> b.prosecdef;
  IF v_changed IS DISTINCT FROM ARRAY[
       'public.ottoq_evaluate_rule_core(p_rule_code text, p_entity_type text, p_entity_id uuid, p_context jsonb, p_action_context text, p_fleet_operator_id uuid, p_depot_id uuid, p_triggered_by_event_id uuid, p_override_id uuid)',
       'public.ottoq_tick_invariance_metrics(p_sim_run_id uuid)'] THEN
    RAISE EXCEPTION '0202 A0 FAILED: function bodies changed = %', v_changed;
  END IF;
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0202 a USING (sig)
   WHERE a.sig IS NULL;
  IF v_new IS NOT NULL THEN
    RAISE EXCEPTION '0202 A0 FAILED: new functions = %', v_new;
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) <> (SELECT count(*) FROM pin_0202) THEN
    RAISE EXCEPTION '0202 A0 FAILED: function count moved';
  END IF;
  RAISE NOTICE '0202 A0: pin holds; exactly two bodies changed, none new';

  -- ── A1. The shape: column, key, index, registry, and the registry check is clean.
  IF NOT EXISTS (SELECT 1 FROM pg_attribute a
                  WHERE a.attrelid = 'public.ottoq_rule_evaluations'::regclass AND a.attname = 'sim_run_id'
                    AND a.atttypid = 'uuid'::regtype AND NOT a.attnotnull AND NOT a.atthasdef) THEN
    RAISE EXCEPTION '0202 A1 FAILED: sim_run_id is not a nullable, default-free uuid column';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint k
                  WHERE k.conname = 'fk_ottoq_rule_evaluations_sim_run'
                    AND k.conrelid = 'public.ottoq_rule_evaluations'::regclass
                    AND k.confrelid = 'public.ottoq_sim_runs'::regclass
                    AND k.contype = 'f' AND k.confdeltype = 'a' AND NOT k.convalidated) THEN
    RAISE EXCEPTION '0202 A1 FAILED: FK missing, or not NO ACTION, or was validated against 5M rows';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
                  WHERE c.relname = 'idx_ottoq_evals_sim_run' AND i.indisvalid AND i.indpred IS NOT NULL) THEN
    RAISE EXCEPTION '0202 A1 FAILED: partial index missing or invalid';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_schema = 'public' AND table_name = 'ottoq_rule_evaluations'
                    AND column_name = 'sim_run_id' AND class = 'engine') THEN
    RAISE EXCEPTION '0202 A1 FAILED: registry row absent or not class engine';
  END IF;
  SELECT count(*) FILTER (WHERE severity = 'block'),
         count(*) FILTER (WHERE table_name = 'ottoq_rule_evaluations')
    INTO v_blk, v_warn
    FROM public.ottoq_check_run_scope_registry();
  IF v_blk <> 0 OR v_warn <> 0 THEN
    RAISE EXCEPTION '0202 A1 FAILED: run-scope registry check: % blocking, % rows naming this table', v_blk, v_warn;
  END IF;
  RAISE NOTICE '0202 A1: column, FK (NO ACTION, NOT VALID), partial index, registry row; registry check clean';

  -- ── A2. Each rewritten body reverts to its pin under the reverse replacements,
  --        so the fragments are the only difference.
  v_def := pg_get_functiondef('public.ottoq_evaluate_rule_core(text,text,uuid,jsonb,text,uuid,uuid,uuid,uuid)'::regprocedure);
  v_def := replace(v_def, 'override_id, correlation_id, sim_run_id', 'override_id, correlation_id');
  v_def := replace(v_def, 'p_override_id, v_correlation, v_run', 'p_override_id, v_correlation');
  v_def := replace(v_def, 'THE AUDIT RECORD. 0202: it now names its run (sim_run_id := v_run; NULL is production).',
                          'THE AUDIT RECORD. UNCHANGED, and it is the complete one.');
  IF md5(v_def) <> '3456fb4cc35cd22fcaf64ae682ca4800' THEN
    RAISE EXCEPTION '0202 A2 FAILED: the evaluator differs from its pin outside the three fragments';
  END IF;
  v_def := pg_get_functiondef('public.ottoq_tick_invariance_metrics(uuid)'::regprocedure);
  v_def := replace(v_def,
    'CASE WHEN r.started_at < (SELECT l.classified_at FROM ottoq_cert_lineage l WHERE l.name ~ ''^0202_'' LIMIT 1) THEN NULL ELSE (SELECT count(*) FROM ottoq_rule_evaluations e',
    '(SELECT count(*) FROM ottoq_rule_evaluations e');
  v_def := replace(v_def, 'AND e.sim_run_id = p_sim_run_id) END,', 'AND e.evaluated_at >= r.started_at),');
  IF md5(v_def) <> '501848c0186d4ae4eac82d3777a08f28' THEN
    RAISE EXCEPTION '0202 A2 FAILED: tick_invariance_metrics differs from its pin outside the two fragments';
  END IF;
  RAISE NOTICE '0202 A2: both bodies revert to their pins under the reverse replacements';

  -- ── A3. LIVE WRITE PROBE, rolled back. Under a run the row names it; under
  --        'none' the row is production. TW.003 with no service_code passes as
  --        'no context' deterministically, emits no event, and costs one row.
  IF current_setting('ottoq.dryrun', true) = 'on' THEN
    RAISE EXCEPTION '0202 A3 FAILED: ottoq.dryrun is on in this session; the probe would not write';
  END IF;
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed'
   ORDER BY r.started_at DESC, r.sim_run_id DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION '0202 A3 FAILED: no completed flagship run to probe under'; END IF;

  BEGIN
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    SELECT c.passed, c.reason, c.evaluation_id INTO v_passed, v_reason, v_eid1
      FROM public.ottoq_evaluate_rule_core('TW.003.quiet_hours', 'vehicle', '0cb1b8c6-c948-4937-8bf6-187442a7be1a'::uuid,
             v_ctx, 'task_start', '22222222-2222-2222-2222-222222222222'::uuid, '11111111-1111-1111-1111-111111111111'::uuid) c;
    IF NOT v_passed OR v_reason <> 'no context' THEN
      RAISE EXCEPTION '0202 A3 FAILED: probe evaluation did not pass as no-context (passed=%, reason=%)', v_passed, v_reason;
    END IF;
    SELECT e.sim_run_id INTO v_got FROM public.ottoq_rule_evaluations e WHERE e.evaluation_id = v_eid1;
    IF NOT FOUND THEN RAISE EXCEPTION '0202 A3 FAILED: the probe wrote no ledger row'; END IF;
    IF v_got IS DISTINCT FROM v_run THEN
      RAISE EXCEPTION '0202 A3 FAILED: under run % the row carries sim_run_id %', v_run, v_got;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0202', MESSAGE = '0202 probe rollback';
  EXCEPTION WHEN SQLSTATE 'P0202' THEN
    NULL;
  END;

  BEGIN
    PERFORM set_config('ottoq.sim_run_id', 'none', true);
    SELECT c.passed, c.reason, c.evaluation_id INTO v_passed, v_reason, v_eid2
      FROM public.ottoq_evaluate_rule_core('TW.003.quiet_hours', 'vehicle', '0cb1b8c6-c948-4937-8bf6-187442a7be1a'::uuid,
             v_ctx, 'task_start', '22222222-2222-2222-2222-222222222222'::uuid, '11111111-1111-1111-1111-111111111111'::uuid) c;
    IF NOT v_passed OR v_reason <> 'no context' THEN
      RAISE EXCEPTION '0202 A3 FAILED: production probe did not pass as no-context (passed=%, reason=%)', v_passed, v_reason;
    END IF;
    SELECT e.sim_run_id INTO v_got FROM public.ottoq_rule_evaluations e WHERE e.evaluation_id = v_eid2;
    IF NOT FOUND THEN RAISE EXCEPTION '0202 A3 FAILED: the production probe wrote no ledger row'; END IF;
    IF v_got IS NOT NULL THEN
      RAISE EXCEPTION '0202 A3 FAILED: under no run the row carries sim_run_id %', v_got;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0202', MESSAGE = '0202 probe rollback';
  EXCEPTION WHEN SQLSTATE 'P0202' THEN
    NULL;
  END;
  PERFORM set_config('ottoq.sim_run_id', '', true);

  IF EXISTS (SELECT 1 FROM public.ottoq_rule_evaluations WHERE evaluation_id IN (v_eid1, v_eid2)) THEN
    RAISE EXCEPTION '0202 A3 FAILED: a probe row survived its rollback';
  END IF;
  SELECT count(*) INTO v_rows FROM public.ottoq_rule_evaluations WHERE sim_run_id IS NOT NULL;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION '0202 A3 FAILED: % rows carry a sim_run_id before any run has been made under 0202', v_rows;
  END IF;
  RAISE NOTICE '0202 A3: under run % the row named it; under none the row was production; both rolled back; nothing backfilled', v_run;

  -- ── A4. Grants: the two API roles keep SELECT and lose the rest; the engine roles are untouched.
  IF has_table_privilege('anon', 'public.ottoq_rule_evaluations', 'TRUNCATE')
     OR has_table_privilege('anon', 'public.ottoq_rule_evaluations', 'TRIGGER')
     OR has_table_privilege('anon', 'public.ottoq_rule_evaluations', 'REFERENCES')
     OR has_table_privilege('authenticated', 'public.ottoq_rule_evaluations', 'TRUNCATE')
     OR has_table_privilege('authenticated', 'public.ottoq_rule_evaluations', 'TRIGGER')
     OR has_table_privilege('authenticated', 'public.ottoq_rule_evaluations', 'REFERENCES') THEN
    RAISE EXCEPTION '0202 A4 FAILED: an API role still holds TRUNCATE, TRIGGER or REFERENCES on the ledger';
  END IF;
  IF NOT has_table_privilege('anon', 'public.ottoq_rule_evaluations', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.ottoq_rule_evaluations', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.ottoq_rule_evaluations', 'INSERT')
     OR NOT has_table_privilege('service_role', 'public.ottoq_rule_evaluations', 'DELETE') THEN
    RAISE EXCEPTION '0202 A4 FAILED: a privilege that should have survived did not';
  END IF;
  RAISE NOTICE '0202 A4: anon/authenticated SELECT only; service_role unchanged';

  -- ── A5. The metrics reader answers NULL for a pre-0202 run and a number for
  --        a post-0202 one. Only the first half is testable now: the lineage
  --        row lands below, so at this moment the CASE falls through to the
  --        run-scoped count, which must be 0 for the newest completed run.
  IF (public.ottoq_tick_invariance_metrics(v_run) ->> 'unsafe_blocks') IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION '0202 A5 FAILED: before the lineage row, unsafe_blocks for % should read 0 (run-scoped, no rows), got %',
      v_run, public.ottoq_tick_invariance_metrics(v_run) ->> 'unsafe_blocks';
  END IF;
  RAISE NOTICE '0202 A5: tick_invariance_metrics reads the run-scoped count';
  RAISE NOTICE '0202: all assertions passed';
END $assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0202_every_evaluation_names_its_run_and_a_pair_stops_sharing_one_clock', TRUE,
  'G5. ottoq_rule_evaluations (5.09M rows, 4.7 GB) carried no sim_run_id; evaluated_at is transaction time, so the two arms '
  'of every certification pair shared one evaluated_at and no reader could tell them apart. Added sim_run_id (NULL = '
  'production; FK NOT VALID, NO ACTION; partial index; registry class engine), populated in ottoq_evaluate_rule_core from '
  'the v_run it already resolved for its events. ottoq_tick_invariance_metrics.unsafe_blocks now scopes by run and answers '
  'NULL for runs that started before this row. No backfill. anon/authenticated lost TRUNCATE, TRIGGER, REFERENCES on the '
  'ledger. No hashed stream reads the table; h_rule is the next instrument. forces_recert TRUE because a decide-path body '
  'changed; the prediction for the next round is that no canon moves.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- A6, after the lineage row: the pre-0202 run now reads NULL, not a number.
DO $post$
DECLARE v_run uuid; v_val text;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed'
   ORDER BY r.started_at DESC, r.sim_run_id DESC LIMIT 1;
  v_val := public.ottoq_tick_invariance_metrics(v_run) ->> 'unsafe_blocks';
  IF v_val IS NOT NULL THEN
    RAISE EXCEPTION '0202 A6 FAILED: a run from before 0202 reads unsafe_blocks = %, expected NULL', v_val;
  END IF;
  RAISE NOTICE '0202 A6: a pre-0202 run reads unsafe_blocks NULL';
END $post$;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-06 20:37:00 UTC (3:37 PM CT) -- one transaction as
-- postgres through one-shot pg_cron job 404, first attempt, 32 s
-- (COMMIT at 20:37:32). Verified after the fact at 20:38 UTC:
--
--   lineage row                 present, 20:37:00.08, forces_recert TRUE
--   sim_run_id column           present (nullable uuid, no default)
--   idx_ottoq_evals_sim_run     present, valid
--   ottoq_evaluate_rule_core    md5 3456fb4c -> cedaa29f
--   recert floor                15:51:00 -> 20:37:00 (this migration)
--
-- Round 21 is the recertification. It runs after 0203 (h_rule measured)
-- and 0207 (the refusal-walk tie), so it certifies three migrations at
-- once; the attribution rule stands: this migration adds a column to an
-- INSERT and cannot move a decision; any canon move belongs to 0207
-- (tied columns only, one move) or is a new finding.
-- =====================================================================
