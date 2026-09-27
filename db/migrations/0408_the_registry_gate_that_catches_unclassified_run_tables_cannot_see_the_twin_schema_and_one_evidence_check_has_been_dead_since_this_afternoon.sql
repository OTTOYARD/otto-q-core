-- migration-version: 20260921203327
-- migration-name:    the_registry_gate_that_catches_unclassified_run_tables_cannot_see_the_twin_schema_and_one_evidence_check_has_been_dead_since_this_afternoon
--
-- 0408  **Three fixes, all found while retracting `db/checks/0316`. None changes engine behaviour,
--       so `forces_recert` is FALSE and the sweep in flight is safe.**
--
--   (1) `ottoq_check_run_scope_registry()` check (a) — "a run-scoped column that nobody has
--       classified" — only looks in `('public','proof_0015')`. It has therefore never been able
--       to see `twin` or `ottoq`, and returns clean today while `twin.arm_cycles` and
--       `twin.arm_registrations` sit unclassified with 54,098 and 28,841 rows accumulated across
--       ~1,400 runs. Widened to the four real schemas.
--
--   (2) `ottoq_evidence_join_loss()` **raises 42883 and returns nothing at all**, because
--       `db/migrations/0403` (mine, today) registered a bigint surrogate key
--       (`ottoq_dial_promotion_ledger.promotion_id`) as `class='evidence'`, and the function
--       joins every evidence column to `ottoq_sim_runs.sim_run_id`, which is uuid. Filtered by
--       COLUMN TYPE rather than by column name — see below, the distinction is load-bearing.
--
--   (3) The six `arm.*` event types the twin has been emitting all along are absent from
--       `ottoq_event_types_catalog` (139 rows). Eight are registered — those six plus the two
--       branches of `twin.ottoq_arm_advance_cycles` that have never fired. Phase C7 step 2
--       requires the vocabulary to be registered properly.
--
-- ══ WHY (1) IS A HOLE AND NOT A PREFERENCE ═════════════════════════════════
--
-- `ottoq_purge_prior_runs` clears `class='engine'` tables by registry lookup. A table absent from
-- the registry is never purged and never complained about — the only mechanism that would have
-- complained is check (a), and check (a) cannot see it. That is how `twin.arm_cycles` came to hold
-- **52,490 rows orphaned from 1,373 deleted runs (97%)**, which `db/checks/0316` then read as
-- one run's worth of activity. The measurement error is retracted in `0318`; this is the
-- mechanism that made it available to be made.
--
-- **Widening cannot refuse a demo run.** Check (a)'s severity is `warn`, and the purge's step (2)
-- raises only on `severity='block'` (it counts blocks and merely collects warns into `v_warn`).
-- Verified against the purge's own source in preflight P5 rather than assumed, because a gate
-- widened into a blocker would take the Twin's start door down.
--
-- **The classification itself is deliberately NOT here.** Registering either arm table as
-- `engine` trips check (b2), which requires an FK to `ottoq_sim_runs` — and neither table has any
-- FK, so one would have to be added, and it cannot be added over 80,461 orphan rows without
-- deleting them. That is an 80k-row deletion and it is Chase's call. `evidence` is the
-- non-destructive alternative but would declare as durable evidence a table whose run link is
-- gone for 97% of its rows. `0318` §5 writes up both; this migration makes the gate SAY the
-- tables are unclassified on every purge so the decision cannot be lost again.
--
-- ══ WHY (2) FILTERS ON TYPE AND NOT ON NAME, WHICH IS THE WHOLE POINT ══════
--
-- `0344` fixed the identical per-column/per-table confusion in check (b2) by narrowing it to the
-- four run-key column names. **Copying that here would break this check more quietly than the
-- 42883 does.** The evidence rows whose column is not one of those four names are:
--
--     public.ottoq_determinism_verdict_ledger.arm_a_run   uuid    <- a genuine run reference
--     public.ottoq_determinism_verdict_ledger.arm_b_run   uuid    <- a genuine run reference
--     public.ottoq_dial_promotion_ledger.promotion_id     bigint  <- not a run reference
--
-- A name list drops the determinism ledger's two arm columns — precisely the columns whose join
-- loss matters most — to remove one bigint. `ottoq_sim_runs.sim_run_id` is `uuid`, so the
-- discriminator that is actually true is the type: a non-uuid column CANNOT reference it, and a
-- uuid column named `arm_a_run` can. This change therefore drops exactly one row from
-- consideration and adds none.
--
-- And the general lesson, recorded in `0318` §6: `0344` fixed one of four functions that read
-- `ottoq_run_scope_registry` and left its sibling with the same confusion. **Fix that class of
-- bug across every reader of a shared registry in one change, or the next one is found by an
-- error message.**
--
-- ══ WHY (3) MATTERS DESPITE CHANGING NOTHING AT RUNTIME ════════════════════
--
-- `ottoq_record_event` does not validate against `ottoq_event_types_catalog`, which is exactly
-- why six emitted types could go unregistered indefinitely — nothing breaks, the vocabulary just
-- quietly stops being the vocabulary. Two of the six (`arm.mate_restage_required`,
-- `arm.mate_failed`) have **never been emitted**: across 54,098 cycles, outcomes `restaged` and
-- `failed` are both 0. They are registered anyway, because a catalog that lists only the branches
-- that have happened to fire is not a catalog. Their `description` says so.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_src    text;
  v_n      int;
  v_bad    text;
  v_raised boolean := false;
BEGIN
  -- P1. The function exists and still carries the narrow schema list this migration replaces.
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_check_run_scope_registry';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0408 P1: public.ottoq_check_run_scope_registry() is missing';
  END IF;
  IF position('''public'',''proof_0015''' in replace(v_src, ' ', '')) = 0 THEN
    RAISE EXCEPTION '0408 P1: check (a) no longer reads IN (''public'',''proof_0015'') -- somebody '
                    'changed it; re-derive before replacing the whole body';
  END IF;

  -- P2. Widening surfaces EXACTLY the two tables 0318 documents, and nothing else. If a third
  --     appears, stop: it needs its own classification decision, not a silent warn.
  SELECT count(*), string_agg(c.table_schema||'.'||c.table_name||'.'||c.column_name, ', ' ORDER BY 1)
    INTO v_n, v_bad
    FROM information_schema.columns c
    JOIN pg_class rc ON rc.relname = c.table_name
    JOIN pg_namespace nn ON nn.oid = rc.relnamespace AND nn.nspname = c.table_schema
   WHERE rc.relkind = 'r'
     AND c.table_schema IN ('ottoq','twin')
     AND c.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_schema = c.table_schema
                        AND g.table_name   = c.table_name
                        AND g.column_name  = c.column_name);
  IF v_n <> 2 OR v_bad IS DISTINCT FROM 'twin.arm_cycles.sim_run_id, twin.arm_registrations.sim_run_id' THEN
    RAISE EXCEPTION '0408 P2: widening would surface % row(s): % -- expected exactly the two '
                    'twin.arm_* tables named in db/checks/0318', v_n, coalesce(v_bad,'(none)');
  END IF;

  -- P3. Prove the defect before fixing it: the evidence check must RAISE today. If it returns
  --     cleanly, the 42883 is already gone and (2) is repairing something that is not broken.
  BEGIN
    PERFORM count(*) FROM public.ottoq_evidence_join_loss();
  EXCEPTION WHEN others THEN
    v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION '0408 P3: ottoq_evidence_join_loss() no longer raises -- re-derive db/checks/0318 '
                    'section 6 before replacing it';
  END IF;

  -- P4. The bigint row that causes it is present and is the ONLY non-uuid evidence column, so the
  --     type filter removes one row and not a class of rows.
  SELECT count(*), string_agg(g.table_name||'.'||g.column_name||' '||c.data_type, ', ')
    INTO v_n, v_bad
    FROM public.ottoq_run_scope_registry g
    JOIN information_schema.columns c
      ON c.table_schema=g.table_schema AND c.table_name=g.table_name AND c.column_name=g.column_name
   WHERE g.class = 'evidence' AND c.data_type <> 'uuid';
  IF v_n <> 1 OR v_bad NOT LIKE '%promotion_id bigint%' THEN
    RAISE EXCEPTION '0408 P4: expected exactly one non-uuid evidence column (promotion_id bigint), '
                    'found %: % -- the type filter would drop more than intended', v_n, coalesce(v_bad,'(none)');
  END IF;

  -- P5. The purge raises on 'block' only. If it ever starts raising on warns, widening a warn
  --     check takes the Twin's start door down, so this is asserted and not assumed.
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_purge_prior_runs';
  IF v_src IS NULL OR v_src !~ 'IF\s+v_block\s*>\s*0\s+THEN' THEN
    RAISE EXCEPTION '0408 P5: ottoq_purge_prior_runs no longer gates on v_block -- widening a warn '
                    'level check may now refuse a demo run; stop and re-read its source';
  END IF;

  -- P6. None of the six arm types is catalogued yet, and all six are actually emitted or are
  --     reachable branches of twin.ottoq_arm_advance_cycles.
  SELECT count(*) INTO v_n FROM public.ottoq_event_types_catalog WHERE event_type LIKE 'arm.%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0408 P6: % arm.* type(s) already catalogued -- this insert expects none', v_n;
  END IF;

  RAISE NOTICE '0408 preflight: all six checks passed';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) Check (a) widened to the four schemas that actually hold engine tables.
--     Body reproduced verbatim from the live catalog; the ONLY edit is the
--     table_schema IN (...) list in check (a). Signature, volatility,
--     SECURITY DEFINER and search_path preserved exactly.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_check_run_scope_registry()
RETURNS TABLE (table_schema text, table_name text, column_name text, problem text, severity text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = twin, ottoq, public, extensions
AS $fn$
  -- (a) a run-scoped column that nobody has classified
  --
  --     WIDENED 0408. This read IN ('public','proof_0015') and therefore could never see the
  --     `twin` or `ottoq` schemas. It returned clean while twin.arm_cycles (54,098 rows) and
  --     twin.arm_registrations (28,841) sat unclassified, which meant the purge never touched
  --     them and they accumulated ~1,400 runs of orphans -- 97% of their rows. db/checks/0316
  --     then read that accumulation as one run's activity. The gate whose entire job is to
  --     notice an unclassified run-scoped table could not look where two of them were.
  --
  --     Severity stays 'warn': the purge raises on 'block' only, so this can report an
  --     unclassified table on every run start without ever refusing one.
  SELECT c.table_schema::text, c.table_name::text, c.column_name::text,
         'unregistered run-scoped column'::text, 'warn'::text
    FROM information_schema.columns c
    JOIN pg_class rc ON rc.relname = c.table_name
    JOIN pg_namespace nn ON nn.oid = rc.relnamespace AND nn.nspname = c.table_schema
   WHERE rc.relkind = 'r'
     AND c.table_schema IN ('public','ottoq','twin','proof_0015')
     AND c.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_schema = c.table_schema
                        AND g.table_name   = c.table_name
                        AND g.column_name  = c.column_name)
  UNION ALL
  -- (b1) EXISTENCE. Unchanged, over EVERY engine/stamp row. to_regclass (not a
  --      ::regclass cast) is deliberate: the cast RAISES on a dropped table, and
  --      the purge calls this guard, so one dropped scratch table would have made
  --      every run start fail.
  SELECT g.table_schema, g.table_name, g.column_name,
         'registered engine/stamp table no longer exists',
         'block'
    FROM public.ottoq_run_scope_registry g
   WHERE g.class IN ('engine','stamp')
     AND to_regclass(g.table_schema||'.'||g.table_name) IS NULL
  UNION ALL
  -- (b2) THE FK REQUIREMENT, narrowed by 0344 to rows whose column is an actual
  --      run-scoping key -- the same four names (a) watches.
  --
  --      WHY. The registry is per-COLUMN; this check was per-TABLE. So
  --      ottoq_proposer_fire_log.tick_seq, class 'stamp', demanded an FK to
  --      ottoq_sim_runs -- while the same table's sim_run_id is class 'evidence'
  --      and must OUTLIVE the run. 0267 satisfied the demand by adding the FK,
  --      and that FK then made ottoq_purge_prior_runs step (5) raise 23503,
  --      which made ottoq_start_demo_run raise, which broke the Twin's start
  --      door. The table was required to block the purge it was registered to
  --      survive.
  --
  --      tick_seq is an integer tick counter. It is not a key into
  --      ottoq_sim_runs and no FK on it could exist -- the registry's own note
  --      says "Provenance, not a scoping key; sim_run_id is." Orphaning is
  --      impossible through a column that does not reference the parent, so no
  --      protection is lost. This considers strictly FEWER rows than before, so
  --      it cannot invent a block; 0344 A5 asserts ottoq_external_proposals is
  --      still required to keep its FK by its own engine-class row.
  SELECT g.table_schema, g.table_name, g.column_name,
         'engine/stamp run-key column''s table has no FK to ottoq_sim_runs',
         'block'
    FROM public.ottoq_run_scope_registry g
   WHERE g.class IN ('engine','stamp')
     AND g.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND to_regclass(g.table_schema||'.'||g.table_name) IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_constraint k
        WHERE k.contype = 'f'
          AND k.conrelid = to_regclass(g.table_schema||'.'||g.table_name)
          AND k.confrelid = 'public.ottoq_sim_runs'::regclass)
  UNION ALL
  -- (c) any FK to the run table that has become CASCADE
  SELECT n.nspname::text, c.relname::text, 'sim_run_id'::text,
         'FK to ottoq_sim_runs is ON DELETE CASCADE — history can be silently erased',
         'block'
    FROM pg_constraint k
    JOIN pg_class c ON c.oid = k.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE k.contype = 'f'
     AND k.confrelid = 'public.ottoq_sim_runs'::regclass
     AND k.confdeltype = 'c'
  UNION ALL
  -- (d) ADDED 0348. An engine-class table whose append-only DELETE guard never
  --     learned the purge's arming protocol. The registry says the rows must not
  --     outlive their run; the guard says they can never be deleted. Both cannot
  --     be true, and the loser is every simulation start.
  --
  --     ottoq_recall_refusals was exactly this: class 'engine', guard raising
  --     unconditionally, six rows, and ottoq_start_demo_run could not complete.
  --     Its FK then made ottoq_recall_decisions undeletable too -- one guard,
  --     two survivors.
  --
  --     TEXTUAL, on the COMMENT-STRIPPED body, and that is stated because it
  --     matters: prosrc carries comments, and this repo has twice been fooled by
  --     matching them (0346 A1a, 0220's LIMIT 1 count). Precision measured on the
  --     live catalog rather than assumed: flags 1 of 4, the right one.
  --
  --     engine + DELETE only. The stamp/UPDATE mirror is real but unlistable
  --     this way -- `vehicles` carries six UPDATE triggers that are loggers and
  --     workers, not guards, and none honours the flag because none needs to.
  --     Flagging those would put six false blocks on the purge's own
  --     precondition. Named, not silently included.
  SELECT DISTINCT
         g.table_schema, g.table_name, g.column_name,
         'engine table''s append-only DELETE guard ('||p.proname||
           ') does not honour set_config(''ottoq.retention'') — the purge cannot clear it',
         'block'
    FROM public.ottoq_run_scope_registry g
    JOIN pg_class c   ON c.oid = to_regclass(g.table_schema||'.'||g.table_name)
    JOIN pg_trigger t ON t.tgrelid = c.oid AND NOT t.tgisinternal AND (t.tgtype & 8) > 0
    JOIN pg_proc p    ON p.oid = t.tgfoid
   WHERE g.class = 'engine'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g') ILIKE '%RAISE EXCEPTION%'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g') NOT ILIKE '%ottoq.retention%';
$fn$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) The evidence join-loss check, restored to working order by TYPE.
--     Body verbatim; the only edit is `AND c.data_type = 'uuid'` folded into the
--     existing column-existence EXISTS. The p_pattern default is preserved --
--     dropping it would fail 42P13 and break the seven call sites of a defaulted
--     signature (the 0401/0407 lesson).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_evidence_join_loss(p_pattern text DEFAULT 'ottoq\_%'::text)
RETURNS TABLE (table_name text, rows_total bigint, rows_with_run bigint,
               rows_orphaned bigint, join_loss_pct numeric, has_fk_to_sim_runs boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
DECLARE
  r      record;
  v_tot  bigint;
  v_run  bigint;
  v_orph bigint;
BEGIN
  FOR r IN
    SELECT DISTINCT reg.table_schema AS sch, reg.table_name AS tbl, reg.column_name AS col
      FROM public.ottoq_run_scope_registry reg
     WHERE reg.class = 'evidence'
       AND reg.table_name LIKE p_pattern
       --: Registered but dropped tables are not a finding; skip rather than raise.
       AND to_regclass(format('%I.%I', reg.table_schema, reg.table_name)) IS NOT NULL
       --: The join hazard needs the joining column to exist, AND to be joinable.
       --:
       --: ADDED 0408 -- `AND c.data_type = 'uuid'`. The EXECUTE below compares this column to
       --: ottoq_sim_runs.sim_run_id, which is uuid. 0403 registered a bigint SURROGATE KEY
       --: (ottoq_dial_promotion_ledger.promotion_id) as evidence, and the comparison raised
       --: 42883, which killed the whole loop -- so this entire check returned nothing from the
       --: moment 0403 landed until 0408.
       --:
       --: TYPE and not NAME, deliberately. 0344 fixed the same per-column/per-table confusion
       --: in check (b2) by narrowing to the four run-key column names; here that would drop
       --: ottoq_determinism_verdict_ledger.arm_a_run and .arm_b_run -- two uuid columns that
       --: ARE run references and whose join loss is the most worth watching -- in order to
       --: exclude one bigint. A non-uuid column cannot reference a uuid key; a uuid column
       --: called arm_a_run can. The type is the property that is actually true.
       AND EXISTS (SELECT 1 FROM information_schema.columns c
                    WHERE c.table_schema = reg.table_schema
                      AND c.table_name  = reg.table_name
                      AND c.column_name = reg.column_name
                      AND c.data_type   = 'uuid')
     ORDER BY reg.table_name
  LOOP
    EXECUTE format(
      'SELECT count(*), count(%1$I), '
      '       count(*) FILTER (WHERE %1$I IS NOT NULL AND NOT EXISTS ('
      '         SELECT 1 FROM public.ottoq_sim_runs sr WHERE sr.sim_run_id = t.%1$I)) '
      '  FROM %2$I.%3$I t', r.col, r.sch, r.tbl)
      INTO v_tot, v_run, v_orph;

    table_name         := r.tbl;
    rows_total         := v_tot;
    rows_with_run      := v_run;
    rows_orphaned      := v_orph;
    join_loss_pct      := CASE WHEN v_tot > 0
                               THEN round(100.0 * v_orph / v_tot, 2) ELSE NULL END;
    --: An FK here would be a registry violation (check (b) wants one from engine/stamp
    --: only). Surfaced beside the loss because the two are the same mistake at different
    --: layers: one blocks the purge, the other silently omits its survivors.
    has_fk_to_sim_runs := EXISTS (
      SELECT 1 FROM pg_constraint c
       WHERE c.conrelid = to_regclass(format('%I.%I', r.sch, r.tbl))
         AND c.contype = 'f'
         AND c.confrelid = 'public.ottoq_sim_runs'::regclass);
    RETURN NEXT;
  END LOOP;
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (3) The six arm.* event types the twin has been emitting since before this
--     session. `emitter` follows the twin convention ('twin_simulator'); the
--     real writer is twin.ottoq_arm_advance_cycles via public.ottoq_record_event
--     with actor_id='twin_charge_arm', which the descriptions name.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_event_types_catalog
  (event_type, category, description, emitter, default_severity, introduced_in)
VALUES
  ('arm.mate_started', 'integration_event',
   'Robotic charge arm began a mate toward a vehicle in a charging stall. Emitted by '
   'twin.ottoq_arm_advance_cycles (actor_id=twin_charge_arm) as a cycle opens.',
   'twin_simulator', 'info', '0408_arm_event_vocabulary'),
  ('arm.mate_latched', 'integration_event',
   'Robotic charge arm latched. The vehicle is physically tethered; '
   'vehicles.robotic_tether_phase becomes ''charging''.',
   'twin_simulator', 'info', '0408_arm_event_vocabulary'),
  ('arm.demate_started', 'integration_event',
   'Robotic charge arm began a demate. The session is ending and the arm is retracting.',
   'twin_simulator', 'info', '0408_arm_event_vocabulary'),
  ('arm.demate_cleared', 'integration_event',
   'Robotic charge arm cleared the vehicle envelope; the stall is releasable and '
   'vehicles.robotic_tether_phase becomes ''clear''.',
   'twin_simulator', 'info', '0408_arm_event_vocabulary'),
  ('arm.emergency_release', 'safety_event',
   'Arm cycle terminated by emergency release (twin.ottoq_arm_emergency_release). '
   'Outcome emergency_released; 85 cycles have taken this path.',
   'twin_simulator', 'warning', '0408_arm_event_vocabulary'),
  ('arm.move_refused', 'safety_event',
   'A move was refused because the vehicle was still tethered. This is the interlock '
   'working, not a fault.',
   'twin_simulator', 'warning', '0408_arm_event_vocabulary'),
  ('arm.mate_restage_required', 'safety_event',
   'Arm could not reach the port and the vehicle must be restaged. UNEXERCISED: outcome '
   '''restaged'' is 0 across 54,098 cycles as of 2026-09-21. Catalogued because a vocabulary '
   'that lists only the branches that have fired is not a vocabulary.',
   'twin_simulator', 'warning', '0408_arm_event_vocabulary'),
  ('arm.mate_failed', 'safety_event',
   'Arm mate failed outright. UNEXERCISED: outcome ''failed'' is 0 across 54,098 cycles as of '
   '2026-09-21. See arm.mate_restage_required.',
   'twin_simulator', 'error', '0408_arm_event_vocabulary')
ON CONFLICT (event_type) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY. A partial fix here is worse than none: a widened gate
-- that blocks, or a join-loss check that still raises, is discovered by a failed
-- demo run rather than by this block.
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_block int;
  v_warn  int;
  v_names text;
  v_rows  int;
  v_n     int;
BEGIN
  -- V1. The widened gate reports the two twin tables as WARNS and adds no BLOCK.
  SELECT count(*) FILTER (WHERE severity = 'block'),
         count(*) FILTER (WHERE severity = 'warn'),
         string_agg(table_schema||'.'||table_name, ', ' ORDER BY table_schema, table_name)
           FILTER (WHERE severity = 'warn')
    INTO v_block, v_warn, v_names
    FROM public.ottoq_check_run_scope_registry();
  IF v_block <> 0 THEN
    RAISE EXCEPTION '0408 V1: widened gate reports % BLOCK row(s) -- the purge and therefore '
                    'ottoq_start_demo_run would refuse. Rolling back.', v_block;
  END IF;
  IF v_warn <> 2 OR v_names IS DISTINCT FROM 'twin.arm_cycles, twin.arm_registrations' THEN
    RAISE EXCEPTION '0408 V1: expected exactly 2 warns (twin.arm_cycles, twin.arm_registrations), '
                    'got %: %', v_warn, coalesce(v_names,'(none)');
  END IF;

  -- V2. The evidence check RUNS, and covers the two uuid arm_*_run columns the name-based fix
  --     would have dropped while excluding the bigint that was killing it.
  SELECT count(*) INTO v_rows FROM public.ottoq_evidence_join_loss();
  IF v_rows = 0 THEN
    RAISE EXCEPTION '0408 V2: ottoq_evidence_join_loss() returned no rows -- it either still '
                    'fails or the type filter excluded everything';
  END IF;
  SELECT count(*) INTO v_n
    FROM public.ottoq_evidence_join_loss('ottoq\_determinism\_verdict\_ledger');
  IF v_n < 2 THEN
    RAISE EXCEPTION '0408 V2: determinism verdict ledger contributes % row(s), expected 2 '
                    '(arm_a_run and arm_b_run) -- the type filter dropped a genuine run '
                    'reference', v_n;
  END IF;

  -- V3. All eight arm types catalogued, including the two unexercised branches.
  SELECT count(*) INTO v_n FROM public.ottoq_event_types_catalog WHERE event_type LIKE 'arm.%';
  IF v_n <> 8 THEN
    RAISE EXCEPTION '0408 V3: % arm.* catalogue row(s), expected 8', v_n;
  END IF;
  SELECT count(*) INTO v_n
    FROM (SELECT DISTINCT event_type FROM public.ottoq_events WHERE event_type LIKE 'arm.%') e
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_event_types_catalog k WHERE k.event_type = e.event_type);
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0408 V3: % emitted arm.* type(s) still absent from the catalogue', v_n;
  END IF;

  -- V4. 0405's anon surface gate is still empty. Both replaced functions are STABLE and
  --     write nothing, but CREATE OR REPLACE is exactly where a privilege surprise would land.
  SELECT count(*) INTO v_n FROM public.ottoq_assert_anon_rpc_surface();
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0408 V4: ottoq_assert_anon_rpc_surface() reports % problem(s) after the '
                    'replaces -- expected empty forever', v_n;
  END IF;

  RAISE NOTICE '0408 verify: gate widened (0 blocks, 2 documented warns), evidence join-loss '
               'check alive with % row(s), 8 arm.* types catalogued, anon surface clean', v_rows;
END $post$;

COMMIT;
