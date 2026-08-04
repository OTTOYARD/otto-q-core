# `db/baseline/` — a snapshot of the brain, not the brain

**Baseline date: 2026-08-04.** (Artifacts exported from the live database
2026-08-03; every count re-verified against the live database on 2026-08-04 —
see "Currency check" below.)

## What this folder is

A read-only photograph of the OTTO-Q brain — Supabase project
`gxdrcyphqjzjsuhxuqtg` ("otto-q-core") — as it stood on the baseline date. It
exists so that a human, or a future audit, can see the whole system in one place
without opening the Supabase dashboard.

## What this folder is NOT

**Editing these files changes nothing about the running system.** Nothing reads
them. There is no deploy step that picks them up. If you "fix a bug" here, the
bug is still live in the database and your fix is invisible to everyone and
everything.

They are also **not replayable in order**. This is a flattened end-state dump —
`CREATE OR REPLACE FUNCTION` bodies, table definitions, policies and cron rows as
they exist *now*. It is not the 621-step history that produced them, and running
these files top-to-bottom against an empty database is not expected to work.

## To change the brain

1. Write a new numbered file in `../migrations/` (see `../migrations/README.md`).
2. Apply it to the database **from that file**, following `../../scripts/APPLYING.md`.
3. Record it in `../../MIGRATION_LOG.md`.
4. Re-export this baseline when it has drifted far enough to be misleading.

> **The rule: if it isn't a committed file, it didn't happen.**

## Contents

| File | What it holds | Count |
|---|---|---|
| `functions_public.sql` | user-defined routines in schema `public` | **336** |
| `functions_ottoq.sql` | user-defined routines in schema `ottoq` (the decision brain) | **48** |
| `functions_twin.sql` | user-defined routines in schema `twin` (the world simulator) | **71** |
| `tables.sql` | table / column / constraint / index definitions | — |
| `rls_policies.sql` | row-level-security state and policy definitions | — |
| `cron_jobs.sql` | `pg_cron` schedule (tick, metronome, retention) | — |

Total user-defined routines: **455**.

"User-defined" excludes extension-owned routines (`pg_depend.deptype = 'e'`).
The raw `public` schema contains **1,080** routines in total; the extra ~744 are
PostGIS and other extension functions and are deliberately not part of this
baseline.

Edge functions are **not** in this folder — the 27 deployed Supabase edge
functions live in `../../edge-functions/<slug>/index.ts`.

## Currency check (performed 2026-08-04, read-only)

The export claimed certain counts. Those claims were re-verified against the live
database before the copy was trusted. **They match exactly — no drift.**

| Measure | Export claimed | Live (2026-08-04) | Result |
|---|---:|---:|---|
| `public` user routines | 336 | **336** | match |
| `ottoq` user routines | 48 | **48** | match |
| `twin` user routines | 71 | **71** | match |
| Migration ledger entries (`supabase_migrations.schema_migrations`) | 621 | **621** | match |
| Deployed edge functions | 27 | **27** (all `ACTIVE`) | match |

Verification queries used (read-only):

```sql
-- routine counts, extension-owned routines excluded
SELECT n.nspname AS schema, count(*)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public','ottoq','twin')
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
GROUP BY 1;

-- applied-migration ledger
SELECT count(*) FROM supabase_migrations.schema_migrations;
```

Edge-function count came from the Supabase management API function list.

## The gap this repo closes

The live database has **621 applied migrations** in its ledger. The founder's
working folder held 80 migration files, and **none of the 80 appear in the live
ledger**. Every one of those 621 changes was typed straight at the database, so
there was nothing to review, revert, or diff. This baseline is the starting
point from which that stops being true.
