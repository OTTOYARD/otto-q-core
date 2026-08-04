-- ============================================================================
-- 0001_EXAMPLE_template.sql
--
-- THIS FILE IS A TEMPLATE, NOT A MIGRATION. It is never applied. The drift
-- checker skips any filename containing EXAMPLE.
--
-- To make a real migration: copy this file to db/migrations/NNNN_short_name.sql
-- (next free NNNN, lowercase_with_underscores), delete this banner, and fill in
-- the header. Then follow scripts/APPLYING.md.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- REQUIRED HEADER — both lines. The drift checker reads them.
-- Leave the version as PENDING until the migration is actually applied, then
-- paste in the real version the database assigned it and re-run
-- `bash scripts/gen-drift-sql.sh`.
-- ----------------------------------------------------------------------------
-- migration-version: PENDING
-- migration-name:    example_short_name_matching_this_file

-- ----------------------------------------------------------------------------
-- WHAT / WHY  — write this for the person who reads it in six months at 2am
-- during a demo. Not "fixed bug". Say what was wrong, how it showed up, and
-- what the fix does. The house style is a long, honest comment block; the
-- applied migrations that saved the most time all look like this.
-- ----------------------------------------------------------------------------
-- SYMPTOM:  what was observed (a number, a wrong state, a stuck vehicle).
-- CAUSE:    the actual mechanism, once isolated.
-- FIX:      what this file changes, and what it deliberately does NOT change.
-- BLAST:    which callers touch this object, and why they stay safe.
-- VERIFY:   the exact query or run that proves it worked (goes in MIGRATION_LOG.md).

-- ============================================================================
-- HOUSE RULES — these are not style preferences, each one is a scar
-- ============================================================================
--
-- 1. SNAPSHOT BEFORE YOU REPLACE.
--    Capture pg_get_functiondef() into ottoq_schema_snapshots BEFORE the
--    CREATE OR REPLACE. If the change is wrong at 2am, the old body is a SELECT
--    away instead of gone forever. (See reference_db_surgery_lessons: never
--    replace or drop a function whose definition you have not captured.)
--
-- 2. NEVER DROP.
--    No DROP FUNCTION, DROP TABLE, DROP COLUMN. Use CREATE OR REPLACE. If a
--    signature must change, create the new signature alongside and retire the
--    old one in a later, separate migration once nothing calls it. A DROP is
--    irreversible and takes its dependents with it.
--
-- 3. NEVER TOUCH ottoq_events.
--    It is ~9 GB of an 11 GB database and it is append-only guarded. Do not
--    SELECT it casually, do not DELETE from it, do not add an index to it in a
--    migration. Retention is handled separately.
--
-- 4. A FAILURE MUST NEVER ABORT decide_tick.
--    Anything reachable from the tick must be a TOTAL function: every input
--    maps to a defined output. One unmapped twin service code once hit a CHECK
--    constraint and rolled back the WHOLE decide_tick transaction every tick —
--    zero stall assignments — while cron cheerfully reported "succeeded".
--    If you add a mapping, add an ELSE branch. If you add a constraint, make
--    the writer clamp to a legal value rather than raise.
--    The twin's vocabulary is OPEN; OTTO-Q's enums are CLOSED. Every seam
--    between them must be total.
--
-- 5. ONE CONCERN PER FILE.
--    Small migrations are reviewable and revertible. Big ones are neither.
--
-- 6. COMMIT THE FILE FIRST, THEN APPLY IT.
--    See scripts/APPLYING.md. The rule this repo exists for:
--    if it isn't a committed file, it didn't happen.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 1 — SNAPSHOT THE CURRENT DEFINITION (house rule 1)
--
-- This is the exact idiom already used in the live ledger. Change the label to
-- match this migration, and the WHERE clause to name every object you are about
-- to replace. If you are replacing three functions, snapshot all three.
--
-- To recover later:
--   SELECT definition FROM public.ottoq_schema_snapshots
--    WHERE label = '<your label>' AND object_name = '<fn>';
-- ----------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0001_example_short_name_pre',      -- <label>_pre  (use _post for an after-shot)
       'function',
       n.nspname,
       p.proname,
       pg_get_functiondef(p.oid),
       md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_example_function_you_are_changing');


-- ----------------------------------------------------------------------------
-- STEP 2 — MD5 GUARD (house rule 1, enforced)
--
-- Proves you are replacing the body you think you are replacing. If someone
-- typed a hotfix straight into the SQL editor since you wrote this file, the
-- live md5 will not match and this raises INSTEAD of silently clobbering their
-- fix. That silent clobber is the single most expensive mistake available here.
--
-- To fill in the expected hash, run this first and paste the result:
--   SELECT md5(pg_get_functiondef(p.oid))
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public' AND p.proname='ottoq_example_function_you_are_changing';
--
-- If you genuinely intend to replace whatever is there, delete this whole
-- block — but say so in MIGRATION_LOG.md. Deleting it quietly is not allowed.
-- ----------------------------------------------------------------------------
DO $guard$
DECLARE
  v_expected text := 'PASTE_THE_MD5_HERE';
  v_actual   text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_actual
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'ottoq_example_function_you_are_changing';

  IF v_actual IS NULL THEN
    RAISE EXCEPTION
      'GUARD: ottoq_example_function_you_are_changing does not exist. '
      'Expected to replace it. Aborting so nothing is created by accident.';
  ELSIF v_actual <> v_expected THEN
    RAISE EXCEPTION
      'GUARD: live definition md5 % does not match the expected %. '
      'Someone changed this function outside this migration. '
      'Re-read the live body, re-base your change on it, then re-run.',
      v_actual, v_expected;
  END IF;
END
$guard$;


-- ----------------------------------------------------------------------------
-- STEP 3 — THE ACTUAL CHANGE
--
-- CREATE OR REPLACE only. Keep the existing SECURITY/search_path settings unless
-- changing them IS the migration — the brain's functions are overwhelmingly
-- SECURITY DEFINER with an explicit search_path, and dropping that line silently
-- changes who the function runs as and what it can see.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_example_function_you_are_changing(
  p_depot_id uuid,
  p_clock    timestamptz
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_result integer := 0;
BEGIN
  -- House rule 4: total and non-aborting. Guard the inputs, never assume.
  IF p_depot_id IS NULL OR p_clock IS NULL THEN
    RETURN 0;
  END IF;

  -- ... the real logic ...

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- House rule 4 again: if this is reachable from decide_tick, swallow and
  -- report rather than propagate. A silent zero beats a rolled-back tick.
  -- Record it somewhere durable that is NOT ottoq_events (house rule 3).
  RAISE WARNING 'ottoq_example_function_you_are_changing failed safely: %', SQLERRM;
  RETURN 0;
END
$function$;


-- ----------------------------------------------------------------------------
-- STEP 4 — POST-SNAPSHOT (optional but cheap, and the ledger shows it is used)
-- ----------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0001_example_short_name_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_example_function_you_are_changing');


-- ----------------------------------------------------------------------------
-- STEP 5 — VERIFY (read-only; paste the output into MIGRATION_LOG.md)
--
-- A migration is not done when it applies without error. It is done when a
-- query proves the behaviour changed. Write that query here.
-- ----------------------------------------------------------------------------
-- SELECT ... ;


-- ============================================================================
-- AFTERWARDS — do not stop here
--   1. Fill in `-- migration-version:` above with the version the database
--      assigned (SELECT version, name FROM supabase_migrations.schema_migrations
--      ORDER BY version DESC LIMIT 1;).
--   2. bash scripts/gen-drift-sql.sh
--   3. Add a row to MIGRATION_LOG.md.
--   4. Commit, then run scripts/check-drift.sql. It must come back CLEAN.
-- ============================================================================
