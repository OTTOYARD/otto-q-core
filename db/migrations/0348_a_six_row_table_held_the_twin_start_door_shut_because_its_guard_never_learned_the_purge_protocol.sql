-- migration-version: 20260919170057
-- migration-name:    a_six_row_table_held_the_twin_start_door_shut_because_its_guard_never_learned_the_purge_protocol
--
-- 0348  FOUR ENGINE TABLES ARE APPEND-ONLY. THREE LET THE PURGE THROUGH. THE
--       FOURTH HAS SIX ROWS AND HAS BLOCKED EVERY SIMULATION START.
--
-- 0344 removed a constraint. 0345 fixed the delete order. 0347 removed the
-- quadratic FK scan. Each was necessary, each was insufficient, and none of them
-- was the last one. This is the last one, and it was underneath all three.
--
-- ── HOW IT WAS FINALLY SEEN ─────────────────────────────────────────────────
--
-- Not by reading. By instrumenting. `ottoq_start_demo_run` was driven from
-- pg_cron with an exception handler that LOGGED and SWALLOWED, so the diagnosis
-- would survive the transaction's own rollback. Three attempts before it
-- reported anything useful, and two false conclusions on the way -- both worth
-- recording, because both were about the instrument rather than the engine:
--
--   * `cron.job_run_details.return_message` is updated WHILE the job runs. Read
--     mid-flight it showed the tag of the statement then executing, so the same
--     job appeared to report "SET", then "INSERT 0 1", then "DO". I concluded
--     from that that pg_cron was skipping the final statement. It was not. A
--     progress field read as a result field is not evidence.
--   * A cron job scheduled `* * * * *` with `SET statement_timeout = 0` around
--     an hour-long purge is not a passive probe. Jobid 728 sat 20 minutes inside
--     the unindexed purge holding the very lock 0347's CREATE INDEX needed, so
--     the fix queued behind the defect it fixes.
--
-- What the swallowing handler finally wrote down:
--
--   purge refused: 2 engine table(s) could not be cleared after 1 retry pass(es):
--     [{"t": "ottoq_recall_refusals",  "c": "sim_run_id",
--       "msg": "ottoq_recall_refusals is append-only (attempted DELETE)",
--       "sqlstate": "P0001"},
--      {"t": "ottoq_recall_decisions", "c": "sim_run_id",
--       "msg": "update or delete on table \"ottoq_recall_decisions\" violates
--               foreign key constraint \"ottoq_recall_refusals_recall_id_fkey\"..."}]
--
-- Read it as the two-step it is. The refusals table refused to be deleted. That
-- left its rows in place, which left the FK to `ottoq_recall_decisions` intact,
-- which made the parent undeletable too. One guard produced two survivors, and
-- 0345's bounded retry named both -- that mechanism worked exactly as written.
--
-- ── THE DEFECT: A PROTOCOL THREE OF FOUR TABLES SPEAK ───────────────────────
--
-- `ottoq_purge_prior_runs` line 11-12, its own comment already saying why:
--
--   -- (1) ARM. Without this the append-only guards refuse every DELETE below.
--   PERFORM set_config('ottoq.retention', 'on', true);
--
-- A transaction-local flag. Every append-only guard on the purge path is meant
-- to recognise it. Measured over pg_trigger x pg_proc, engine-class tables with
-- a DELETE-firing guard -- there are exactly four:
--
--   table                    guard function                      honours arming  rows
--   ottoq_events             ottoq_events_block_mutation               YES      82,143
--   ottoq_recall_decisions   ottoq_block_mutation                      YES     283,076
--   ottoq_rule_evaluations   ottoq_block_mutation                      YES      24,059
--   ottoq_recall_refusals    ottoq_recall_refusals_append_only         NO            6
--
-- The three that pass share two functions built around the same clause:
--
--   IF TG_OP = 'DELETE' AND current_setting('ottoq.retention', true) = 'on'
--     THEN RETURN OLD;
--
-- The fourth has a bespoke body of one statement and no condition at all:
--
--   BEGIN
--     RAISE EXCEPTION 'ottoq_recall_refusals is append-only (attempted %)', TG_OP;
--   END
--
-- It is not wrong about what it wants. It is simply the only one of the four
-- that was never told how the purge asks permission. **Six rows, no condition,
-- and the front door of the product shut behind it.** 389,278 rows across the
-- other three delete without complaint.
--
-- ── THE FIX, AND WHY IT IS NOT A RECLASSIFICATION ──────────────────────────
--
-- The tempting fix is to move `ottoq_recall_refusals` to class `evidence` so the
-- purge stops trying. That would be wrong twice over. It is genuinely
-- run-scoped -- it carries `sim_run_id` with an FK to `ottoq_sim_runs`, and C9's
-- refusal ledger is per-run -- and reclassifying would leave prior runs' refusals
-- visible to any unscoped reader, which is the 0145/0146 defect class the purge
-- exists to prevent. The table's classification is right. Its guard is
-- incomplete. So the guard is what changes, to the identical clause its three
-- siblings use. UPDATE stays forbidden unconditionally: the trigger is tgtype 27
-- (BEFORE, ROW, DELETE|UPDATE) and both of this table's FKs are NO ACTION, so
-- nothing the purge does needs to UPDATE it -- unlike `ottoq_events`, whose
-- guard must also forgive UPDATE because its self-FK is ON DELETE SET NULL.
--
-- ── AND A CHECK, SO THIS CLASS CANNOT COME BACK ────────────────────────────
--
-- A guard that disagrees with the registry is invisible until the purge actually
-- reaches that table -- which took 0344, 0345 and 0347 to make happen. That is
-- too long a fuse to leave unlit. So `ottoq_check_run_scope_registry` gains
-- check (d): an engine-class table whose DELETE guard raises and does not
-- mention the arming flag is a BLOCKING defect, reported by name.
--
-- THE CHECK IS TEXTUAL, ON THE COMMENT-STRIPPED BODY, AND SAYING SO IS PART OF
-- THE CHECK. `prosrc` includes comments -- 0346's own A1a fired on an
-- explanatory comment, and 0220 matched `LIMIT 1` fourteen times in text and
-- three times in code -- so both `--` and block comments are stripped before
-- matching. It is a heuristic, and its precision is measured rather than
-- asserted: over the live catalog the predicate (raises AND does not mention
-- arming) flags **exactly 1 of the 4** engine-class DELETE guards, the right one,
-- with no false positive.
--
-- WHY IT IS SCOPED TO engine + DELETE, which is narrower than the hazard and is
-- deliberate. The symmetric case exists: the purge UPDATEs `stamp` columns to
-- NULL, so a stamp table whose guard blocked UPDATE unconditionally would break
-- it the same way. It is NOT checked, because a textual test cannot tell a guard
-- from a worker on that side: `vehicles` (class stamp) carries six UPDATE
-- triggers -- `ottoq_arm_interlock`, deploy log, two state-change loggers,
-- occupancy sync, timestamp touch -- and none honours the arming flag because
-- none needs to. Flagging them would be six false blocks on the purge's own
-- precondition, which is a worse failure than the one being prevented. The
-- stamp/UPDATE side is left unchecked and named here rather than papered over.
--
-- ── A CORRECTION TO 0347, WHICH IS APPLIED AND WHOSE FILE STAYS AS APPLIED ──
--
-- 0347's A3 reads `WHERE r.severity = 'blocking'`. The values
-- `ottoq_check_run_scope_registry` actually returns are **'block'** and 'warn'.
-- So A3 matched no row under any condition: it could not have failed, and it
-- asserted nothing. It is the G25/G28 class exactly -- a check narrower than its
-- name, reported green -- and it appeared inside a file whose whole subject was
-- an instrument that answered a narrower question than it looked like. The
-- assertion 0347 should have had is A5 below, with the correct literal, and it
-- is stronger: it demands zero 'block' rows both before and after.

BEGIN;

-- ── P1  the defect is present, and is the one described ────────────────────
DO $$
DECLARE v_body text; v_honours boolean; v_class text; v_tgtype int;
BEGIN
  IF to_regclass('public.ottoq_recall_refusals') IS NULL THEN
    RAISE EXCEPTION '0348 P1: public.ottoq_recall_refusals is absent; this migration has no subject';
  END IF;

  SELECT g.class INTO v_class FROM public.ottoq_run_scope_registry g
   WHERE g.table_schema='public' AND g.table_name='ottoq_recall_refusals'
     AND g.column_name='sim_run_id';
  IF v_class IS DISTINCT FROM 'engine' THEN
    RAISE EXCEPTION '0348 P1: ottoq_recall_refusals.sim_run_id is class %, expected engine -- if it has been reclassified this file is the wrong fix', COALESCE(v_class,'<unregistered>');
  END IF;

  SELECT t.tgtype::int,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g')
    INTO v_tgtype, v_body
    FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
   WHERE t.tgrelid = 'public.ottoq_recall_refusals'::regclass
     AND NOT t.tgisinternal AND (t.tgtype & 8) > 0
   LIMIT 1;

  IF v_body IS NULL THEN
    RAISE EXCEPTION '0348 P1: no DELETE-firing guard found on ottoq_recall_refusals';
  END IF;
  IF v_tgtype <> 27 THEN
    RAISE EXCEPTION '0348 P1: guard trigger is tgtype %, expected 27 (BEFORE|ROW|DELETE|UPDATE) -- the replacement below assumes that shape', v_tgtype;
  END IF;
  v_honours := v_body ILIKE '%ottoq.retention%';
  IF v_honours THEN
    RAISE EXCEPTION '0348 P1: the guard already honours the arming flag -- premise stale, review before applying';
  END IF;
END $$;

-- ── P2  the protocol this fix copies is established, not invented ──────────
DO $$
DECLARE v_ok int; v_bad int;
BEGIN
  WITH reg AS (SELECT DISTINCT table_name FROM public.ottoq_run_scope_registry
                WHERE class='engine' AND table_schema='public'),
  g AS (
    SELECT r.table_name,
           regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                          '--[^'||chr(10)||']*', '', 'g') AS body
    FROM reg r
    JOIN pg_class c   ON c.oid = to_regclass('public.'||r.table_name)
    JOIN pg_trigger t ON t.tgrelid = c.oid AND NOT t.tgisinternal AND (t.tgtype & 8) > 0
    JOIN pg_proc p    ON p.oid = t.tgfoid
  )
  SELECT count(*) FILTER (WHERE body ILIKE '%ottoq.retention%'),
         count(*) FILTER (WHERE body ILIKE '%RAISE EXCEPTION%' AND body NOT ILIKE '%ottoq.retention%')
    INTO v_ok, v_bad FROM g;

  IF v_ok < 3 THEN
    RAISE EXCEPTION '0348 P2: only % engine DELETE guard(s) honour the arming flag; expected at least 3 -- the pattern being copied is not established', v_ok;
  END IF;
  IF v_bad <> 1 THEN
    RAISE EXCEPTION '0348 P2: % engine DELETE guard(s) raise without honouring the arming flag; expected exactly 1 (ottoq_recall_refusals). Check (d) below would not be precise -- re-measure before applying', v_bad;
  END IF;
END $$;

-- ── P3  the purge really does arm the flag this guard will now read ────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='ottoq_purge_prior_runs'
       AND p.prosrc LIKE '%set_config(''ottoq.retention'', ''on'', true)%'
  ) THEN
    RAISE EXCEPTION '0348 P3: ottoq_purge_prior_runs does not arm ottoq.retention -- honouring that flag would not help';
  END IF;
END $$;

-- ── FIX 1  the guard learns the protocol its three siblings already speak ──
-- DELETE is forgiven only while the purge's transaction-local flag is armed.
-- UPDATE stays forbidden unconditionally: both FKs on this table are NO ACTION,
-- so no purge step needs to rewrite a surviving row (contrast
-- ottoq_events_block_mutation, which must also forgive UPDATE because
-- ottoq_events_parent_event_id_fkey is ON DELETE SET NULL).
CREATE OR REPLACE FUNCTION public.ottoq_recall_refusals_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  -- Retention/purge maintenance only. Same clause as public.ottoq_block_mutation;
  -- ottoq_purge_prior_runs step (1) sets this flag transaction-locally. Added by
  -- migration 0348: without it this six-row table refused every DELETE and so
  -- blocked ottoq_start_demo_run outright.
  IF TG_OP = 'DELETE' AND current_setting('ottoq.retention', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'ottoq_recall_refusals is append-only (attempted %)', TG_OP
    USING ERRCODE = 'P0001';
END
$fn$;

-- ── FIX 2  check (d): the registry and the guards must agree ───────────────
CREATE OR REPLACE FUNCTION public.ottoq_check_run_scope_registry()
 RETURNS TABLE(table_schema text, table_name text, column_name text, problem text, severity text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- (a) a run-scoped column that nobody has classified
  SELECT c.table_schema::text, c.table_name::text, c.column_name::text,
         'unregistered run-scoped column'::text, 'warn'::text
    FROM information_schema.columns c
    JOIN pg_class rc ON rc.relname = c.table_name
    JOIN pg_namespace nn ON nn.oid = rc.relnamespace AND nn.nspname = c.table_schema
   WHERE rc.relkind = 'r'
     AND c.table_schema IN ('public','proof_0015')
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
$function$;

COMMENT ON FUNCTION public.ottoq_check_run_scope_registry() IS
  'Purge safety guard. ottoq_purge_prior_runs step (2) refuses to run while this '
  'reports any severity=''block'' row. Checks: (a) unregistered run-scoped column '
  '(warn); (b1) registered engine/stamp table gone; (b2) engine/stamp run-key '
  'column with no FK to ottoq_sim_runs; (c) FK to ottoq_sim_runs turned CASCADE; '
  '(d) 0348 — engine table whose append-only DELETE guard does not honour the '
  'ottoq.retention arming flag, which is what ottoq_recall_refusals did while '
  'blocking every simulation start.';

-- ── A1  BEHAVIOURAL, not textual: the guard now does the right thing twice ──
-- The point of the file. A text match proves the clause is present; only a real
-- DELETE proves it works. Both arms run against live rows inside subtransactions
-- that are rolled back, so nothing is deleted.
DO $$
DECLARE v_id uuid; v_n int; v_armed_ok boolean := false; v_unarmed_blocked boolean := false;
BEGIN
  SELECT refusal_id INTO v_id FROM public.ottoq_recall_refusals LIMIT 1;
  IF v_id IS NULL THEN
    RAISE EXCEPTION '0348 A1: ottoq_recall_refusals is empty, so the guard cannot be exercised on a real row';
  END IF;

  -- ARM 1: armed -> the DELETE must succeed.
  BEGIN
    PERFORM set_config('ottoq.retention', 'on', true);
    DELETE FROM public.ottoq_recall_refusals WHERE refusal_id = v_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 1 THEN v_armed_ok := true; END IF;
    RAISE EXCEPTION 'OTTOQ_0348_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'OTTOQ_0348_ROLLBACK' THEN
      RAISE EXCEPTION '0348 A1: armed DELETE was refused by the guard: %', SQLERRM;
    END IF;
  END;

  -- ARM 2: not armed -> the DELETE must still be refused. A guard that forgives
  -- everything is not a fix, it is a removal.
  BEGIN
    PERFORM set_config('ottoq.retention', 'off', true);
    DELETE FROM public.ottoq_recall_refusals WHERE refusal_id = v_id;
    RAISE EXCEPTION 'OTTOQ_0348_NOT_BLOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'OTTOQ_0348_NOT_BLOCKED' THEN
      RAISE EXCEPTION '0348 A1: unarmed DELETE SUCCEEDED -- the guard has been removed, not taught';
    END IF;
    v_unarmed_blocked := true;
  END;

  PERFORM set_config('ottoq.retention', 'off', true);

  IF NOT v_armed_ok THEN
    RAISE EXCEPTION '0348 A1: armed DELETE did not remove exactly one row';
  END IF;
  IF NOT v_unarmed_blocked THEN
    RAISE EXCEPTION '0348 A1: unarmed DELETE was not blocked';
  END IF;
  RAISE NOTICE '0348 A1: ok — armed DELETE permitted, unarmed DELETE refused, nothing committed';
END $$;

-- ── A2  UPDATE is still forbidden, armed or not ────────────────────────────
DO $$
DECLARE v_id uuid; v_blocked boolean := false;
BEGIN
  SELECT refusal_id INTO v_id FROM public.ottoq_recall_refusals LIMIT 1;
  BEGIN
    PERFORM set_config('ottoq.retention', 'on', true);
    UPDATE public.ottoq_recall_refusals SET reason_code = reason_code WHERE refusal_id = v_id;
    RAISE EXCEPTION 'OTTOQ_0348_UPDATE_ALLOWED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'OTTOQ_0348_UPDATE_ALLOWED' THEN
      RAISE EXCEPTION '0348 A2: UPDATE was permitted while armed -- the guard now forgives more than the purge needs';
    END IF;
    v_blocked := true;
  END;
  PERFORM set_config('ottoq.retention', 'off', true);
  IF NOT v_blocked THEN
    RAISE EXCEPTION '0348 A2: UPDATE was not blocked';
  END IF;
END $$;

-- ── A3  check (d) reports nothing now, AND looked at the right table ───────
-- Two halves on purpose. "Zero defects" from a check that examines nothing is
-- the G25/G28 failure, and this file's own header convicts 0347 of it.
DO $$
DECLARE v_d int; v_pop int;
BEGIN
  SELECT count(*) INTO v_d
    FROM public.ottoq_check_run_scope_registry()
   WHERE severity='block' AND problem LIKE '%append-only DELETE guard%';
  IF v_d <> 0 THEN
    RAISE EXCEPTION '0348 A3: check (d) still reports % blocking row(s) after the fix', v_d;
  END IF;

  -- The population check (d) scans must actually contain ottoq_recall_refusals,
  -- or its silence means nothing.
  WITH reg AS (SELECT DISTINCT table_name FROM public.ottoq_run_scope_registry
                WHERE class='engine' AND table_schema='public')
  SELECT count(*) INTO v_pop
    FROM reg r
    JOIN pg_class c   ON c.oid = to_regclass('public.'||r.table_name)
    JOIN pg_trigger t ON t.tgrelid = c.oid AND NOT t.tgisinternal AND (t.tgtype & 8) > 0
   WHERE r.table_name = 'ottoq_recall_refusals';
  IF v_pop < 1 THEN
    RAISE EXCEPTION '0348 A3: ottoq_recall_refusals is not in check (d)''s population, so its silence proves nothing';
  END IF;
END $$;

-- ── A4  the check still finds a planted defect ─────────────────────────────
-- A guard is only worth having if it fires. Plant a non-arming DELETE guard on
-- an engine table inside a subtransaction, require check (d) to name it, roll back.
DO $$
DECLARE v_found int;
BEGIN
  BEGIN
    -- Built with EXECUTE and a dollar tag composed from chr(36) rather than
    -- written literally: scripts/compile-check.py extracts each CREATE FUNCTION
    -- to compile it separately, and a nested dollar-quoted body inside a DO block
    -- makes its regex run past the end of this block. The linter's limitation,
    -- worked around rather than papered over.
    EXECUTE format(
      'CREATE OR REPLACE FUNCTION public.ottoq_0348_canary_guard() '
      'RETURNS trigger LANGUAGE plpgsql AS %s BEGIN RAISE EXCEPTION %L; END %s',
      chr(36)||'cg'||chr(36), 'canary: append-only', chr(36)||'cg'||chr(36));

    EXECUTE 'CREATE TRIGGER ottoq_0348_canary BEFORE DELETE ON public.ottoq_recall_refusals '
            'FOR EACH ROW EXECUTE FUNCTION public.ottoq_0348_canary_guard()';

    SELECT count(*) INTO v_found
      FROM public.ottoq_check_run_scope_registry()
     WHERE severity='block' AND problem LIKE '%ottoq_0348_canary_guard%';

    RAISE EXCEPTION 'OTTOQ_0348_ROLLBACK_CANARY';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'OTTOQ_0348_ROLLBACK_CANARY' THEN
      RAISE EXCEPTION '0348 A4: planting the canary failed: %', SQLERRM;
    END IF;
  END;

  IF COALESCE(v_found,0) < 1 THEN
    RAISE EXCEPTION '0348 A4: check (d) did NOT flag a planted non-arming DELETE guard -- the check cannot fire';
  END IF;
  RAISE NOTICE '0348 A4: ok — check (d) named the planted guard, and it was rolled back';
END $$;

-- ── A5  the assertion 0347 meant to make, with the literal that exists ────
DO $$
DECLARE v_block int;
BEGIN
  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0348 A5: the purge precondition reports % blocking defect(s); ottoq_purge_prior_runs step (2) would refuse', v_block;
  END IF;
  -- and prove the literal is one the function can actually return
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='ottoq_check_run_scope_registry'
       AND p.prosrc LIKE '%''block''%'
  ) THEN
    RAISE EXCEPTION '0348 A5: severity literal ''block'' does not occur in the check function -- this assertion is as inert as 0347 A3 was';
  END IF;
END $$;

-- ── A6  the canary function did not survive its own rollback ──────────────
DO $$
BEGIN
  IF to_regprocedure('public.ottoq_0348_canary_guard()') IS NOT NULL THEN
    RAISE EXCEPTION '0348 A6: ottoq_0348_canary_guard still exists; the A4 subtransaction leaked a function into the schema';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'ottoq_0348_canary') THEN
    RAISE EXCEPTION '0348 A6: trigger ottoq_0348_canary still exists; the A4 subtransaction leaked a trigger';
  END IF;
END $$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────
-- forces_recert FALSE. The guard change affects only DELETE-while-armed, and the
-- only caller that arms is ottoq_purge_prior_runs, which runs between runs and
-- never inside a certified tick. UPDATE behaviour is unchanged (A2) and no
-- INSERT path is touched, so no certified atom's inputs move. Check (d) is a new
-- branch of a STABLE reporting function that no engine routine reads except the
-- purge's own precondition.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0348_a_six_row_table_held_the_twin_start_door_shut_because_its_guard_never_learned_the_purge_protocol', false,
  'public.ottoq_recall_refusals_append_only now forgives DELETE while ottoq.retention is armed, the identical clause its three sibling engine guards (ottoq_events_block_mutation, ottoq_block_mutation x2) already used; UPDATE stays forbidden unconditionally because both of the table''s FKs are NO ACTION. This six-row table was the last thing holding ottoq_start_demo_run shut: its unconditional RAISE left its rows in place, which left ottoq_recall_refusals_recall_id_fkey intact, which made ottoq_recall_decisions (283,076 rows) undeletable too, so the purge reported two survivors from one guard. Also adds check (d) to ottoq_check_run_scope_registry: an engine-class table whose append-only DELETE guard does not honour the arming flag is a blocking defect, textual on the comment-stripped body, precision measured at 1 of 4 on the live catalog, scoped to engine+DELETE because the stamp+UPDATE mirror cannot be told from six logger triggers on vehicles. Proven behaviourally (A1: armed DELETE permitted, unarmed refused, both rolled back) and the check proven to fire on a planted canary (A4). forces_recert FALSE: only DELETE-while-armed changed, only the between-runs purge arms it, and no certified tick path is touched.',
  now())
ON CONFLICT(name) DO NOTHING;

COMMIT;
