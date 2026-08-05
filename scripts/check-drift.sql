-- ============================================================================
-- check-drift.sql  —  THE SMOKE ALARM
-- ============================================================================
-- Question this answers, in one sentence:
--   "Has anything been applied to the live OTTO-Q brain that is NOT represented
--    by a committed migration file in this repo?"
--
-- READ-ONLY. This script never writes, never creates, never drops. It is safe
-- to run at any time, including during a live demo.
-- It does NOT touch ottoq_events (9 GB of an 11 GB database).
--
-- ---------------------------------------------------------------------------
-- HOW TO RUN IT
-- ---------------------------------------------------------------------------
--   1. Open the Supabase SQL editor for project gxdrcyphqjzjsuhxuqtg
--      ("otto-q-core"), paste this whole file, and run it.
--   OR run it through the Supabase MCP `execute_sql` tool.
--   2. Read the RESULT column top to bottom. Row 1 is the verdict.
--
-- ---------------------------------------------------------------------------
-- WHY THE MANIFEST IS EMBEDDED IN THIS FILE (the design decision)
-- ---------------------------------------------------------------------------
-- SQL cannot read the filesystem, so it cannot see db/migrations/ by itself.
-- Two options were considered:
--
--   (a) Keep a separate committed manifest (APPLIED.tsv) and paste it in.
--       Rejected: two places to update = they drift from each other, and the
--       drift checker drifting is the worst possible failure.
--
--   (b) THE FILES ARE THE SOURCE OF TRUTH. Every migration file declares its
--       own applied version in its header:
--           -- migration-version: 20260804153000
--           -- migration-name:    p3_short_name
--       `scripts/gen-drift-sql.sh` scrapes those headers straight out of
--       db/migrations/*.sql and rewrites the GENERATED MANIFEST block below,
--       in place. You then commit this file along with the migration.
--
-- (b) was chosen. One source of truth (the migration files), one command to
-- refresh, and the refreshed file is committed — so the manifest itself is
-- reviewable in a diff.
--
--   To refresh:  bash scripts/gen-drift-sql.sh
--
-- Do not hand-edit the GENERATED MANIFEST block. If you do, the generator will
-- overwrite you on the next run, and for one commit the smoke alarm will have
-- been lying.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS CHECK CANNOT SEE — read this, it matters
-- ---------------------------------------------------------------------------
-- Sections A/B/C compare the repo against the LEDGER
-- (supabase_migrations.schema_migrations). The ledger is only written when a
-- change is applied AS a migration (Supabase CLI, the MCP apply_migration tool,
-- or the dashboard's migration path).
--
-- A CREATE OR REPLACE typed straight into the SQL editor changes the brain and
-- writes NO ledger row at all. Sections A/B/C are blind to that by construction.
-- Section D is the backstop for it: it compares the live count of user-defined
-- routines against the counts this repo's baseline recorded. If A and B are
-- clean but D disagrees, somebody edited the brain outside the migration path.
--
-- Section D is a coarse detector — it counts routines, it does not compare their
-- bodies. A same-count body edit still slips past it. The real fix for that is
-- re-exporting db/baseline/ periodically and diffing. Stated plainly so nobody
-- mistakes a green Section D for a guarantee.
--
-- Edge functions are not in Postgres and cannot be checked from SQL at all.
-- See scripts/APPLYING.md for the edge-function procedure.
-- ============================================================================

WITH
-- ---------------------------------------------------------------------------
-- The baseline cut. Everything applied at or before this ledger version is
-- represented by db/baseline/ (the 2026-08-04 snapshot), NOT by a migration
-- file, and is therefore not drift. This is the 621st and newest row that
-- existed when the baseline was taken.
-- Only change this line when db/baseline/ is genuinely re-exported.
-- ---------------------------------------------------------------------------
cut(baseline_through, baseline_rows) AS (
  VALUES ('20260803210034'::text, 621)
),

-- ---------------------------------------------------------------------------
-- The repo's migration files. Generated — see the header.
-- ---------------------------------------------------------------------------
repo_manifest(version, name, file) AS (
  VALUES
-- >>> BEGIN GENERATED MANIFEST — do not edit by hand; run scripts/gen-drift-sql.sh
    ('20260804140958'::text, 'approval_gate_decider'::text, '0002_approval_gate_decider.sql'::text),
    ('20260804183836'::text, 'bay_work_recovery'::text, '0003_bay_work_recovery.sql'::text),
    ('20260804232058'::text, 'close_ledger_loop'::text, '0004_close_ledger_loop.sql'::text),
    ('20260805020029'::text, 'inspection_and_condition_resets'::text, '0005_inspection_and_condition_resets.sql'::text),
    ('20260805142711'::text, 'slim_writes_and_arm_retention'::text, '0006_slim_writes_and_arm_retention.sql'::text),
    ('20260805032907'::text, 'add_site_energy_snapshots_created_at_idx'::text, '0007_add_site_energy_snapshots_created_at_idx.sql'::text),
    ('20260805230731'::text, 'soil_gate_and_retention_walk'::text, '0008_soil_gate_and_retention_walk.sql'::text)
-- <<< END GENERATED MANIFEST
),

mf AS (
  -- PENDING is the placeholder a migration carries between "file written" and
  -- "applied to the database". It is deliberately never matched to a ledger row.
  SELECT version, name, file FROM repo_manifest WHERE version IS NOT NULL
),
led AS (
  SELECT version, name FROM supabase_migrations.schema_migrations
),

-- A. Applied to the database, no file in this repo.  ← THIS IS THE ALARM
drift AS (
  SELECT d.version, d.name
  FROM led d CROSS JOIN cut c
  WHERE d.version > c.baseline_through
    AND NOT EXISTS (SELECT 1 FROM mf m WHERE m.version = d.version)
),

-- B. File in this repo, never applied to the database.
pending AS (
  SELECT m.version, m.name, m.file
  FROM mf m
  WHERE m.version <> 'PENDING'
    AND NOT EXISTS (SELECT 1 FROM led d WHERE d.version = m.version)
),

-- B2. Files still marked PENDING (written but not yet applied). Informational.
unapplied AS (
  SELECT m.name, m.file FROM repo_manifest m WHERE m.version = 'PENDING'
),

-- C. Same version, different name — the file and the ledger disagree.
mismatch AS (
  SELECT m.version, m.name AS file_says, d.name AS db_says, m.file
  FROM mf m JOIN led d ON d.version = m.version
  WHERE d.name IS DISTINCT FROM m.name
),

-- D. Backstop: live routine counts vs the counts db/baseline/ recorded.
--
-- These are EXPECTED counts, not frozen ones. A migration that legitimately adds
-- or removes a routine must move the number here in the same commit, or the smoke
-- alarm cries wolf forever and people learn to ignore it.
--
-- Change log for this line — every edit needs a reason and a committed file:
--   2026-08-04  public 336 -> 337.  db/migrations/0002_approval_gate_decider.sql
--               (ledger version 20260804140958) added exactly one routine,
--               public.ottoq_decide_indepot_approvals. VERIFIED by diffing the live
--               public routine list against db/baseline/functions_public.sql: one
--               name added, zero names removed. The other five functions that
--               migration replaced were CREATE OR REPLACE, so they do not move a count.
--   2026-08-05  public 337 -> 339.  db/migrations/0006_slim_writes_and_arm_retention.sql
--               (ledger version 20260805142711) added exactly two routines:
--                 public.ottoq_events_slim_new_state  -- the BEFORE INSERT trigger fn
--                                                        that stops re-writing new_state
--                 public.ottoq_event_new_state(uuid)  -- the rebuild-on-read reader
--               VERIFIED BY NAME, not by arithmetic. The live public routine list was
--               diffed against db/baseline/functions_public.sql (332 distinct names):
--               live 335, ADDED = {ottoq_decide_indepot_approvals (0002),
--               ottoq_event_new_state, ottoq_events_slim_new_state}, REMOVED = {} .
--               Zero names removed is the load-bearing half of that check -- 0006
--               drops nothing, and this proves it rather than asserting it.
--               The three routines 0006 REPLACED (ottoq_purge_prior_runs,
--               ottoq_retention_purge_worker 4-arg, ottoq_events_block_mutation) were
--               CREATE OR REPLACE and do not move a count. The 3-arg overload of
--               ottoq_retention_purge_worker was deliberately left in place (never
--               drop), so the procedure count is unchanged at 2 overloads.
baseline_counts(sch, n) AS (
  VALUES ('public', 339), ('ottoq', 48), ('twin', 71)
),
live_counts AS (
  SELECT n.nspname::text AS sch, count(*)::int AS n
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'ottoq', 'twin')
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend dd
      WHERE dd.objid = p.oid AND dd.deptype = 'e'   -- exclude extension-owned (PostGIS etc.)
    )
  GROUP BY 1
),
counts AS (
  SELECT b.sch, b.n AS baseline_n, COALESCE(l.n, 0) AS live_n
  FROM baseline_counts b LEFT JOIN live_counts l ON l.sch = b.sch
),

-- Totals used by the verdict line.
tally AS (
  SELECT
    (SELECT count(*) FROM drift)     AS n_drift,
    (SELECT count(*) FROM pending)   AS n_pending,
    (SELECT count(*) FROM mismatch)  AS n_mismatch,
    (SELECT count(*) FROM unapplied) AS n_unapplied,
    (SELECT count(*) FROM counts WHERE live_n <> baseline_n) AS n_countdiff,
    (SELECT count(*) FROM led)       AS n_ledger,
    (SELECT count(*) FROM mf)        AS n_files
)

-- ===========================================================================
-- OUTPUT
-- ===========================================================================
SELECT ord, severity, check_name, detail FROM (

  -- ---- verdict -------------------------------------------------------------
  SELECT 0 AS ord,
         CASE WHEN t.n_drift > 0 OR t.n_mismatch > 0 THEN 'DRIFT'
              WHEN t.n_countdiff > 0                 THEN 'INVESTIGATE'
              ELSE 'CLEAN' END AS severity,
         'VERDICT' AS check_name,
         CASE WHEN t.n_drift > 0 OR t.n_mismatch > 0
              THEN t.n_drift || ' migration(s) applied with no file in this repo, '
                   || t.n_mismatch || ' name mismatch(es). The repo is NOT the source of truth right now.'
              WHEN t.n_countdiff > 0
              THEN 'Ledger and repo agree, but live routine counts differ from the baseline — see Section D.'
              ELSE 'Every applied migration is accounted for. Repo is the source of truth.'
         END AS detail
  FROM tally t

  UNION ALL
  SELECT 1, 'INFO', 'SCOPE',
         'Ledger rows: ' || t.n_ledger || '. Baseline covers everything up to version '
         || (SELECT baseline_through FROM cut) || ' (' || (SELECT baseline_rows FROM cut)
         || ' rows). Migration files in repo: ' || t.n_files
         || '. Files written but not yet applied: ' || t.n_unapplied || '.'
  FROM tally t

  -- ---- A. drift ------------------------------------------------------------
  UNION ALL
  SELECT 10, 'CRITICAL', 'A. IN DATABASE, NOT IN REPO',
         d.version || '  ' || COALESCE(d.name, '(unnamed)')
         || '   -> write db/migrations/NNNN_' || COALESCE(d.name, 'unnamed') || '.sql TODAY'
  FROM drift d

  UNION ALL
  SELECT 11, 'OK', 'A. IN DATABASE, NOT IN REPO',
         'none — nothing has been applied past the baseline without a file'
  FROM tally t WHERE t.n_drift = 0

  -- ---- B. pending ----------------------------------------------------------
  UNION ALL
  SELECT 20, 'WARN', 'B. IN REPO, NOT IN DATABASE',
         p.file || '  (claims version ' || p.version || ', name ' || COALESCE(p.name, '?') || ')'
         || '   -> either apply it, or fix its header if it was never applied'
  FROM pending p

  UNION ALL
  SELECT 21, 'OK', 'B. IN REPO, NOT IN DATABASE',
         'none — every committed migration file is applied'
  FROM tally t WHERE t.n_pending = 0

  UNION ALL
  SELECT 25, 'INFO', 'B2. WRITTEN, NOT YET APPLIED',
         u.file || '  (header says PENDING — expected while the change is in flight)'
  FROM unapplied u

  -- ---- C. mismatch ---------------------------------------------------------
  UNION ALL
  SELECT 30, 'CRITICAL', 'C. NAME MISMATCH',
         m.version || '  file says "' || COALESCE(m.file_says, '?')
         || '", database says "' || COALESCE(m.db_says, '?') || '"  (' || m.file || ')'
  FROM mismatch m

  UNION ALL
  SELECT 31, 'OK', 'C. NAME MISMATCH',
         'none — file names and ledger names agree'
  FROM tally t WHERE t.n_mismatch = 0

  -- ---- D. counts backstop --------------------------------------------------
  UNION ALL
  SELECT 40,
         CASE WHEN c.live_n = c.baseline_n THEN 'OK' ELSE 'INVESTIGATE' END,
         'D. ROUTINE COUNT vs BASELINE',
         'schema ' || rpad(c.sch, 7) || ' baseline ' || c.baseline_n
         || ', live ' || c.live_n
         || CASE WHEN c.live_n = c.baseline_n THEN '  (match)'
                 ELSE '  (differs by ' || (c.live_n - c.baseline_n)
                      || ' — expected if a migration added/removed routines; '
                      || 'if Sections A and B are clean, this means the brain was '
                      || 'edited OUTSIDE the migration path)' END
  FROM counts c

) AS report
ORDER BY ord, detail;
