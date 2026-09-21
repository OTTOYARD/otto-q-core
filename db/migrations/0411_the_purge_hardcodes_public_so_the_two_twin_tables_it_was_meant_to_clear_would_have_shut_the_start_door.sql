-- migration-version: 20260921210548
-- migration-name:    the_purge_hardcodes_public_so_the_two_twin_tables_it_was_meant_to_clear_would_have_shut_the_start_door
--
-- 0411  **Chase's call: classify `twin.arm_cycles` and `twin.arm_registrations` as `engine` and let
--       the purge own them. Doing only that would have shut the Twin's start door on the next demo
--       run, because `ottoq_purge_prior_runs` hardcodes the `public` schema and the registry it
--       reads is schema-qualified.**
--
--       `forces_recert` FALSE, and for once that is measured rather than argued — see P5/P6.
--
-- ══ THE DECISION ═══════════════════════════════════════════════════════════
--
-- `db/checks/0318` §5 put two options to Chase and he chose the destructive one, in his words:
-- *"Old run data doesn't matter at the moment. If it just purges old data or stale run data, then
-- go for it. We are still ironing out the functionality of OTTO-Q."* So: `engine`, which is what
-- these tables are — run-scoped working state (`phase`, `phase_deadline`, `retry_count`).
--
-- What goes, measured 2026-09-21 21:00 UTC (4:00 PM CT):
--
--     twin.arm_cycles          52,490 orphan rows deleted,  1,892 kept (live runs)
--     twin.arm_registrations   27,971 orphan rows deleted,  1,025 kept
--                              ------                       -----
--                              80,461                       2,917
--
-- Every orphan names a `sim_run_id` that is not in `ottoq_sim_runs`. **Neither table has a single
-- NULL `sim_run_id`**, so after this every row belongs to a live run and the purge can reach all of
-- them — there is no residue class left behind.
--
-- ══ THE TRAP THAT MADE THIS A REAL MIGRATION ═══════════════════════════════
--
-- `ottoq_purge_prior_runs` step (4) builds its DELETE like this:
--
--     EXECUTE format('DELETE FROM public.%1$I WHERE %2$I = ANY($1)', r.t, r.c)
--
-- **`public.` is a literal, and the function never reads `ottoq_run_scope_registry.table_schema`
-- at all** (verified: `prosrc !~ 'table_schema'`). Every one of the 47 engine tables registered
-- today lives in `public`, so the omission has never cost anything. Register a `twin` table and the
-- purge attempts `DELETE FROM public.arm_cycles`, gets `42P01 undefined_table`, parks it in
-- `v_pending`, fails all three retry passes because the name is wrong rather than mis-ordered, and
-- reaches:
--
--     RAISE EXCEPTION 'purge refused: % engine table(s) could not be cleared after % retry pass(es)'
--
-- which rolls back its caller `ottoq_start_demo_run`. **That is the same shut start door `0345`
-- reopened**, arrived at from a different direction: `0345` fixed the ORDER of the deletes, this
-- fixes the NAME. A registry row that looks perfectly correct would have broken every demo run.
--
-- **Fourth member of a family this session keeps finding.** A registry consumer that reads part of
-- the registry and assumes the rest: `0344` (per-column classification read as per-table), `0408`
-- check (a) (schema list omitting `twin` and `ottoq`), `0408` join-loss (column name assumed to
-- imply a run reference), and now the purge (schema column ignored entirely). **The registry is a
-- four-column contract and its consumers keep honouring three.**
--
-- ══ WHAT CHANGES IN THE PURGE, AND WHAT DELIBERATELY DOES NOT ══════════════
--
--   - `eng` now selects `table_schema` and the loop DELETEs `%1$I.%2$I`.
--   - The FK depth graph joins on **OIDs** (`to_regclass`) rather than on
--     `conrelid::regclass::text`. That text form is search-path dependent — it renders a `public`
--     table unqualified and a `twin` table qualified — so comparing it against a registry
--     `table_name` silently matched only `public` tables. OIDs cannot be ambiguous. `0345`'s
--     guarantee that *"an FK added between two engine tables tomorrow is ordered correctly without
--     editing this function"* becomes true for non-`public` tables too, which it was not.
--   - `v_cleared` / `v_pending` keys stay the **bare table name for `public`** and become
--     `schema.table` only outside it, so nothing reading the existing payload shape changes. (No
--     database function reads `cleared_by_table`; the shape is preserved anyway.)
--   - Everything else is byte-identical: the (1) arming, the (2) block gate, (3) the doomed-run
--     selection, (4b) the bounded retry, (5) the parent delete, and the return payload.
--
-- ══ WHY `forces_recert` IS FALSE, AND THIS TIME IT IS MEASURED ═════════════
--
-- `db/checks/0318` §10 is about exactly this claim being asserted in prose and not checked. Two
-- facts, both verified in preflight rather than argued:
--
--   **P5. `ottoq_determinism_pair` does not call the purge.** It mentions `ottoq_purge_prior_runs`
--   only inside `0386`'s comment about verdict durability. So changing the purge cannot change what
--   a certification pair does, and neither can changing what the purge deletes.
--
--   **P6. Every function that reads the arm tables is `sim_run_id`-scoped.** `arm_begin_cycle`,
--   `arm_advance_cycles`, `arm_emergency_release`, `arm_registration_check`, `arm_accuracy`,
--   `sim_stop_charge_session`, `sim_release_depot`, `twin_snapshot` — every one predicates on the
--   run. **So the 80,461 stale rows are invisible to the engine and deleting them cannot change a
--   decision.** Had even one read been unscoped this would be `forces_recert` TRUE and a live
--   `0145`/`0146`-class defect besides; that it is not is the finding, and it is why this deletion
--   is safe rather than merely authorised.
--
--   **And the count is EIGHT, not the ten a raw `prosrc` match reports.** `ottoq_cert_arm_finish`
--   and `ottoq_check_run_scope_registry` name an arm table only inside a comment. Both readings
--   reach the same verdict here, so nothing about this migration changes — but "ten readers, all
--   scoped" overstates the evidence by two, and the same comment-blindness is what rejected this
--   file's first attempt (see P3). Counting occurrences in `prosrc` counts prose.
--
-- And the lineage row is written IN THIS FILE, which is the whole lesson of `0410`.
--
-- ══ ONE THING WORTH KNOWING BEFORE IT MATTERS ══════════════════════════════
--
-- `twin.arm_registrations` is not a state table. It holds the physical mating measurements —
-- `error_lateral_mm`, `error_vertical_mm`, `error_yaw_deg`, `fiducial_seen`, `uwb_beacon_id`,
-- `within_envelope`, against their tolerances. That is L5_PHYSICAL calibration data, and under
-- `engine` every demo run now deletes the prior run's. Correct under the decision taken, and right
-- while functionality is still being ironed out. **If arm-accuracy ever becomes something to trend
-- across runs, it needs an `evidence`-class sibling written at the same time** — the `0340` pattern
-- — not a reclassification of this table, because the working state and the measurement want
-- opposite lifetimes. Recorded here so the tradeoff is visible at the moment it starts to bite.

BEGIN;

-- ADD FOREIGN KEY takes ShareRowExclusiveLock on BOTH tables, and ottoq-recert-runner holds
-- RowExclusive on ottoq_sim_runs for the length of every pair. Fail fast rather than queue in front
-- of the runner and block the tick path behind us. The 0407 lesson.
SET LOCAL lock_timeout = '15s';

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n     int;
  v_bad   text;
  v_src   text;
  v_keep  int;
BEGIN
  -- P1. Both tables are still unclassified, and they are the ONLY warns.
  SELECT count(*), string_agg(table_schema||'.'||table_name, ', ' ORDER BY table_schema, table_name)
    INTO v_n, v_bad
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'warn';
  IF v_n <> 2 OR v_bad IS DISTINCT FROM 'twin.arm_cycles, twin.arm_registrations' THEN
    RAISE EXCEPTION '0411 P1: expected exactly the two twin.arm_* warns, got %: %', v_n, coalesce(v_bad,'(none)');
  END IF;

  -- P2. Neither table carries any FK yet -- this migration adds the first.
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE contype = 'f' AND conrelid IN ('twin.arm_cycles'::regclass, 'twin.arm_registrations'::regclass);
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0411 P2: % FK(s) already exist on the arm tables', v_n;
  END IF;

  -- P3. THE DEFECT IS PRESENT. If the purge already honours table_schema, this file is replacing a
  --     function it has not diagnosed.
  --
  --     ON THE COMMENT-STRIPPED BODY, and the first attempt at this migration is why. The
  --     replacement function's own comment explains the old code by quoting it -- "it read
  --     `DELETE FROM public.%I`" -- so a raw `prosrc` match found the literal in the NEW function
  --     and V4 refused the whole transaction. `prosrc` carries comments, and this repo has now
  --     been fooled by that three times: `0346` A1a, `0220`'s LIMIT 1 count, and here. Check (d)
  --     of ottoq_check_run_scope_registry already strips comments for exactly this reason and says
  --     so in its own source; the lesson did not travel. **Any assertion about what a function's
  --     CODE contains must strip comments first.**
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g')
    INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_purge_prior_runs';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0411 P3: public.ottoq_purge_prior_runs is missing';
  END IF;
  IF v_src !~ 'DELETE FROM public\.%' THEN
    RAISE EXCEPTION '0411 P3: the purge no longer hardcodes the public schema -- re-derive before replacing it';
  END IF;
  IF v_src ~ 'table_schema' THEN
    RAISE EXCEPTION '0411 P3: the purge already reads table_schema -- this diagnosis is stale';
  END IF;

  -- P4. NO NULL RUN IDS. An FK permits NULL and the purge matches on equality, so a NULL row would
  --     be a permanent resident that neither mechanism can reach. There must be none.
  SELECT (SELECT count(*) FROM twin.arm_cycles WHERE sim_run_id IS NULL)
       + (SELECT count(*) FROM twin.arm_registrations WHERE sim_run_id IS NULL) INTO v_n;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0411 P4: % row(s) have a NULL sim_run_id -- they would survive every purge '
                    'and the FK would not catch them; decide what they are first', v_n;
  END IF;

  -- P5. THE BASIS OF forces_recert=false, PART ONE: a certification pair does not purge.
  --     Comment-stripped, per P3 -- and here the distinction IS the finding: the pair mentions
  --     ottoq_purge_prior_runs only inside 0386's comment about verdict durability. On the stripped
  --     body the name does not occur at all, so any occurrence is a real call.
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g')
    INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0411 P5: public.ottoq_determinism_pair is missing';
  END IF;
  IF v_src ~ 'ottoq_purge_prior_runs' THEN
    RAISE EXCEPTION '0411 P5: ottoq_determinism_pair CALLS the purge -- changing what the purge '
                    'deletes would change a pair, so this migration is forces_recert TRUE and must '
                    'be reclassified before it lands';
  END IF;

  -- P6. PART TWO: every reader of the arm tables is run-scoped, so the rows about to be deleted
  --     are invisible to the engine. An unscoped reader here is both a recert trigger and a live
  --     0145/0146-class defect.
  --     Comment-stripped, per P3, in both directions: a function naming an arm table only in a
  --     comment is not a reader, and a sim_run_id predicate that exists only in a comment is not a
  --     predicate.
  SELECT string_agg(n.nspname||'.'||p.proname, ', ') INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL (SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                                              '--[^'||chr(10)||']*', '', 'g') AS src) s
   WHERE n.nspname IN ('public','ottoq','twin')
     AND (s.src ~ 'arm_cycles' OR s.src ~ 'arm_registrations')
     AND s.src !~ 'sim_run_id';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0411 P6: these read the arm tables without a sim_run_id predicate, so prior-run '
                    'rows can reach a decision: % -- this is forces_recert TRUE and a defect in its '
                    'own right', v_bad;
  END IF;

  -- P7. There is something to keep. Deleting every row would mean the orphan test is wrong.
  SELECT (SELECT count(*) FROM twin.arm_cycles c
           WHERE EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = c.sim_run_id))
       + (SELECT count(*) FROM twin.arm_registrations a
           WHERE EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = a.sim_run_id))
    INTO v_keep;
  IF v_keep = 0 THEN
    RAISE EXCEPTION '0411 P7: no arm row belongs to a live run -- refusing to delete the whole table';
  END IF;

  RAISE NOTICE '0411 preflight: passed; % arm rows belong to live runs and will be kept', v_keep;
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) The purge learns the registry's fourth column.
--     Body reproduced from the live catalog; the edits are named in the header
--     and marked 0411 inline. Signature, volatility, SECURITY DEFINER and
--     search_path preserved exactly.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_purge_prior_runs(p_keep_run uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  r record; v_n bigint; v_total bigint := 0; v_runs int;
  v_doomed uuid[]; v_block int; v_engine int; v_cleared jsonb := '{}'::jsonb;
  v_warn jsonb;
  v_pending jsonb := '[]'::jsonb;
  v_next    jsonb;
  v_pass    int;
  v_progress boolean;
  v_key     text;   -- 0411: the cleared/pending key, bare in public and qualified outside it
BEGIN
  -- (1) ARM. Without this the append-only guards refuse every DELETE below.
  PERFORM set_config('ottoq.retention', 'on', true);

  -- (2) REFUSE TO RUN BLIND on a blocking defect.
  SELECT count(*) FILTER (WHERE severity = 'block'),
         COALESCE(jsonb_agg(table_name || '.' || column_name)
                  FILTER (WHERE severity = 'warn'), '[]'::jsonb)
    INTO v_block, v_warn
    FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 THEN
    RAISE EXCEPTION 'purge refused: % blocking run-scope defect(s). Run SELECT * FROM ottoq_check_run_scope_registry();', v_block;
  END IF;

  SELECT count(*) INTO v_engine FROM public.ottoq_run_scope_registry WHERE class='engine';
  IF v_engine = 0 THEN
    RAISE EXCEPTION 'purge refused: run-scope registry holds no engine tables';
  END IF;

  -- (3) Decide what is going ONCE, up front, as a value.
  SELECT array_agg(sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs
   WHERE sim_run_id <> p_keep_run
     AND COALESCE(run_by,'') <> 'production_live'
     AND status <> 'running';

  IF v_doomed IS NULL OR cardinality(v_doomed) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'kept', p_keep_run, 'rows_purged', 0,
      'prior_runs_deleted', 0, 'cleared_by_table', v_cleared,
      'unregistered_run_scoped', v_warn, 'retention_armed', true);
  END IF;

  -- (4) CHILDREN FIRST -- AND SINCE 0345 THAT IS TRUE RATHER THAN HOPED.
  --
  -- This was `ORDER BY table_name`, which is alphabetical and knows nothing about
  -- foreign keys. Measured 2026-09-19: of six FK relationships where both ends
  -- are engine tables, THREE are deleted parent-first by that ordering --
  -- ottoq_recall_refusals -> ottoq_recall_decisions,
  -- ottoq_rule_evaluations -> ottoq_events, and
  -- ottoq_ocpp_messages    -> ocpp_sessions.
  -- The first raised 23503 on cron jobid 726 and rolled back an entire
  -- ottoq_start_demo_run, which is why the Twin start door was shut.
  --
  -- Depth is computed from pg_constraint on every call, so an FK added between
  -- two engine tables tomorrow is ordered correctly without editing this
  -- function. depth 0 = not a child of any engine table; deletion runs DESC, so
  -- a child always precedes what it references.
  --
  -- 0411: SCHEMA-AWARE, TWICE OVER.
  --   (a) `eng` carries table_schema and the DELETE below qualifies with it. It
  --       read `DELETE FROM public.%I` and never looked at the registry's
  --       table_schema column at all. All 47 engine tables were in public, so it
  --       cost nothing until twin.arm_cycles and twin.arm_registrations were
  --       registered -- at which point the purge would have raised 42P01 through
  --       all three retry passes and shut the start door again, this time on the
  --       table NAME rather than 0345's ordering.
  --   (b) the FK graph joins on OIDs, not on conrelid::regclass::text. That text
  --       is search-path dependent -- `ottoq_events` for a public table,
  --       `twin.arm_cycles` for a twin one -- so comparing it to a registry
  --       table_name matched public tables only, and 0345's promise about "an FK
  --       added tomorrow" silently excluded every other schema. An OID cannot be
  --       ambiguous.
  FOR r IN
    WITH RECURSIVE eng AS (
      SELECT table_schema, table_name, column_name,
             to_regclass(format('%I.%I', table_schema, table_name)) AS oid
        FROM public.ottoq_run_scope_registry
       WHERE class = 'engine'
    ),
    tbl AS (SELECT DISTINCT oid FROM eng WHERE oid IS NOT NULL),
    edge AS (
      SELECT DISTINCT c.conrelid AS child, c.confrelid AS parent
        FROM pg_constraint c
       WHERE c.contype = 'f'
         AND c.conrelid <> c.confrelid
         AND c.conrelid  IN (SELECT oid FROM tbl)
         AND c.confrelid IN (SELECT oid FROM tbl)
    ),
    depth AS (
      SELECT t.oid, 0 AS d
        FROM tbl t
       WHERE NOT EXISTS (SELECT 1 FROM edge e WHERE e.child = t.oid)
      UNION ALL
      SELECT e.child, d.d + 1
        FROM edge e
        JOIN depth d ON d.oid = e.parent
       WHERE d.d < 20        -- cycle guard: terminate rather than recurse forever
    ),
    ranked AS (
      SELECT oid, max(d) AS d FROM depth GROUP BY oid
    )
    SELECT eng.table_schema AS s, eng.table_name AS t, eng.column_name AS c,
           COALESCE(ranked.d, 0) AS d
      FROM eng
      LEFT JOIN ranked ON ranked.oid = eng.oid
     ORDER BY COALESCE(ranked.d, 0) DESC, eng.table_schema, eng.table_name, eng.column_name
  LOOP
    v_key := CASE WHEN r.s = 'public' THEN r.t ELSE r.s || '.' || r.t END;
    BEGIN
      EXECUTE format('DELETE FROM %1$I.%2$I WHERE %3$I = ANY($1)', r.s, r.t, r.c)
        USING v_doomed;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      IF v_n > 0 THEN
        v_cleared := v_cleared || jsonb_build_object(v_key, v_n);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- NOT swallowed: parked for the bounded retry below, and RAISED by name if
      -- it never resolves. With correct ordering this should stay empty.
      v_pending := v_pending || jsonb_build_array(
        jsonb_build_object('s', r.s, 't', r.t, 'c', r.c, 'sqlstate', SQLSTATE,
                           'msg', left(SQLERRM, 200)));
    END;
  END LOOP;

  -- (4b) BOUNDED RETRY. A cycle, or an ordering the catalog could not express,
  -- would leave residue here. Silently skipping it is the bug this file fixes, so
  -- retry at most three passes and then raise with every survivor named.
  v_pass := 0;
  WHILE jsonb_array_length(v_pending) > 0 AND v_pass < 3 LOOP
    v_pass := v_pass + 1;
    v_next := '[]'::jsonb;
    v_progress := false;
    FOR r IN SELECT (e->>'s') AS s, (e->>'t') AS t, (e->>'c') AS c
               FROM jsonb_array_elements(v_pending) e
    LOOP
      v_key := CASE WHEN r.s = 'public' THEN r.t ELSE r.s || '.' || r.t END;
      BEGIN
        EXECUTE format('DELETE FROM %1$I.%2$I WHERE %3$I = ANY($1)', r.s, r.t, r.c)
          USING v_doomed;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_total := v_total + v_n;
        v_progress := true;
        IF v_n > 0 THEN
          v_cleared := v_cleared || jsonb_build_object(v_key, v_n);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_next := v_next || jsonb_build_array(
          jsonb_build_object('s', r.s, 't', r.t, 'c', r.c, 'sqlstate', SQLSTATE,
                             'msg', left(SQLERRM, 200)));
      END;
    END LOOP;
    v_pending := v_next;
    IF NOT v_progress THEN EXIT; END IF;
  END LOOP;

  IF jsonb_array_length(v_pending) > 0 THEN
    RAISE EXCEPTION 'purge refused: % engine table(s) could not be cleared after % retry pass(es): %',
      jsonb_array_length(v_pending), v_pass, v_pending::text;
  END IF;

  -- (5) The parent. vehicles.owning_sim_run_id is ON DELETE SET NULL; every other
  --     FK is NO ACTION, so if (4) missed anything this RAISES instead of orphaning.
  DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = ANY(v_doomed);
  GET DIAGNOSTICS v_runs = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true, 'kept', p_keep_run, 'rows_purged', v_total,
    'prior_runs_deleted', v_runs, 'cleared_by_table', v_cleared,
    'evidence_preserved', (SELECT count(*) FROM public.ottoq_run_scope_registry WHERE class='evidence'),
    'retry_passes', v_pass,
    'unregistered_run_scoped', v_warn, 'retention_armed', true);
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) The 80,461 orphan rows. Every one names a run ottoq_sim_runs no longer
--     holds, and P6 established that no engine code path can see them.
-- ─────────────────────────────────────────────────────────────────────────────
DELETE FROM twin.arm_registrations a
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = a.sim_run_id);

DELETE FROM twin.arm_cycles c
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = c.sim_run_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- (3) The FKs check (b2) requires of an engine-class run-key column.
--     NO ACTION deliberately, never CASCADE: check (c) treats a CASCADE to
--     ottoq_sim_runs as a BLOCK, because history that erases itself silently is
--     worse than a purge that refuses loudly.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE twin.arm_cycles
  ADD CONSTRAINT arm_cycles_sim_run_id_fkey
  FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);

ALTER TABLE twin.arm_registrations
  ADD CONSTRAINT arm_registrations_sim_run_id_fkey
  FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- (4) The classification itself -- the two rows this whole file exists to make
--     safe. One row per table on the run key, matching every one of the 47
--     existing engine registrations.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES
 ('twin', 'arm_cycles', 'sim_run_id', 'engine',
  'Robotic charge-arm state machine: phase, phase_deadline, retry_count, outcome. Run-scoped '
  'working state. Unclassified until 0411, so nothing purged it and it accumulated 52,490 orphan '
  'rows across ~1,373 deleted runs -- which db/checks/0316 then read as one run''s activity. The '
  'audit trail of what the arms did lives in ottoq_events as arm.* (also engine, also purged with '
  'its run); this table is the machine, not the record.'),
 ('twin', 'arm_registrations', 'sim_run_id', 'engine',
  'Arm-to-port registration attempts: believed vs true lateral/vertical/yaw, their errors and '
  'tolerances, fiducial and UWB observations. Physical mating measurement, classified engine by '
  'Chase''s decision of 2026-09-21 while OTTO-Q functionality is still being established. If '
  'arm accuracy ever needs trending ACROSS runs it wants an evidence-class sibling written '
  'alongside (the 0340 pattern), not a reclassification of this table -- working state and '
  'measurement want opposite lifetimes.')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- (5) The row the recert floor actually reads. In the file this time (0410).
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0411_the_purge_hardcodes_public_so_the_two_twin_tables_it_was_meant_to_clear_would_have_shut_the_start_door', false,
  'Makes ottoq_purge_prior_runs schema-aware, deletes 80,461 orphan arm rows, adds two FKs to '
  'ottoq_sim_runs and registers twin.arm_cycles / twin.arm_registrations as engine. Cannot move a '
  'canon column, and both halves of that are MEASURED in preflight rather than argued: P5 shows '
  'ottoq_determinism_pair does not call the purge (it names it only inside 0386''s comment), and '
  'P6 shows all eight code readers of the arm tables predicate on sim_run_id, so the deleted rows '
  'were unreachable by any decision. Both checks run on the COMMENT-STRIPPED body: the raw-prosrc '
  'versions call the pair a caller and count ten readers instead of eight, and matching raw prosrc '
  'is what rejected this migration''s first attempt on its own documentation. The arm tables are '
  'not among the fourteen atoms.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_n     int;
  v_bad   text;
  v_floor timestamptz;
  v_cur   int;
  v_cols  int;
BEGIN
  -- V1. The gate is clean for the first time: no warns, and critically no BLOCKS -- check (b2)
  --     would block on an engine run-key column with no FK, and a block refuses every demo run.
  SELECT count(*) FILTER (WHERE severity='block'), count(*) FILTER (WHERE severity='warn'),
         string_agg(table_schema||'.'||table_name||' ['||severity||'] '||problem, '; ')
    INTO v_n, v_cur, v_bad
    FROM public.ottoq_check_run_scope_registry();
  IF v_n <> 0 OR v_cur <> 0 THEN
    RAISE EXCEPTION '0411 V1: gate reports % block(s) and % warn(s): %', v_n, v_cur, coalesce(v_bad,'(none)');
  END IF;

  -- V2. The FKs exist and are NOT cascading.
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE contype='f' AND confrelid='public.ottoq_sim_runs'::regclass
     AND conrelid IN ('twin.arm_cycles'::regclass,'twin.arm_registrations'::regclass)
     AND confdeltype = 'a';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0411 V2: expected 2 NO ACTION FKs to ottoq_sim_runs, found %', v_n;
  END IF;

  -- V3. No orphan and no NULL survives, so every remaining row is purgeable by run.
  SELECT (SELECT count(*) FROM twin.arm_cycles c WHERE c.sim_run_id IS NULL
            OR NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id=c.sim_run_id))
       + (SELECT count(*) FROM twin.arm_registrations a WHERE a.sim_run_id IS NULL
            OR NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id=a.sim_run_id))
    INTO v_n;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0411 V3: % unreachable arm row(s) remain', v_n;
  END IF;

  -- V4. The purge learned the column, and no longer carries the literal IN ITS CODE. Stripped, per
  --     P3: the new function's comment quotes the old literal to explain what changed, and matching
  --     raw prosrc rejected the first attempt at this migration on its own documentation.
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g')
    INTO v_bad FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_purge_prior_runs';
  IF v_bad ~ 'DELETE FROM public\.%' THEN
    RAISE EXCEPTION '0411 V4: the purge still hardcodes the public schema';
  END IF;
  IF v_bad !~ 'table_schema' THEN
    RAISE EXCEPTION '0411 V4: the purge does not read table_schema';
  END IF;

  -- V5. AND IT WOULD ACTUALLY TARGET THEM. The purge cannot be run here (it deletes), so its own
  --     target query is replayed and asserted to yield the twin tables with schema 'twin'. This is
  --     what P3's diagnosis promised and the only way to check it without purging.
  SELECT count(*) INTO v_n
    FROM (SELECT table_schema, table_name,
                 to_regclass(format('%I.%I', table_schema, table_name)) AS oid
            FROM public.ottoq_run_scope_registry WHERE class='engine') q
   WHERE q.table_schema = 'twin'
     AND q.table_name IN ('arm_cycles','arm_registrations')
     AND q.oid IS NOT NULL;
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0411 V5: the purge''s target set resolves % of 2 twin arm tables', v_n;
  END IF;
  SELECT count(*) INTO v_n
    FROM (SELECT to_regclass(format('%I.%I', table_schema, table_name)) AS oid
            FROM public.ottoq_run_scope_registry WHERE class='engine') q
   WHERE q.oid IS NULL;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0411 V5: % engine registration(s) resolve to no table -- the purge would '
                    'park and then raise on each', v_n;
  END IF;

  -- V6. The instrument is untouched.
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor < '2026-09-21 19:38:48+00'::timestamptz
     OR v_floor >= '2026-09-21 19:38:49+00'::timestamptz THEN
    RAISE EXCEPTION '0411 V6: recert floor moved to % -- this migration classified itself false', v_floor;
  END IF;
  SELECT count(*), count(*) FILTER (WHERE status='current')
    INTO v_cols, v_cur FROM public.ottoq_determinism_canon;
  IF v_cur <> v_cols THEN
    RAISE WARNING '0411 V6: % of % canon columns current (9 of 9 when written)', v_cur, v_cols;
  END IF;

  RAISE NOTICE '0411 verify: gate clean (0 block, 0 warn), 2 NO ACTION FKs, 0 unreachable rows, '
               'purge schema-aware, floor held, % of % canon columns current', v_cur, v_cols;
END $post$;

COMMIT;
