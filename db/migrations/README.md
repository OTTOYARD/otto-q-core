# `db/migrations/` — every change to the brain, one file at a time

This folder is the only place a change to the OTTO-Q brain is allowed to be
born. `db/baseline/` is a photograph of the past; this folder is the future.

> **The rule: if it isn't a committed file, it didn't happen.**

---

## Naming

```
NNNN_short_name.sql
```

- `NNNN` — a four-digit sequence, starting at `0002` (`0001` is the template).
  It orders the repo's own history. It is **not** the database's version number.
- `short_name` — lowercase, underscores, describes the change, not the ticket.
  Good: `0007_readmit_reopened_needs.sql`. Bad: `0007_fix.sql`, `0007_p2.sql`.

Files containing `EXAMPLE` are skipped by the tooling. Do not put `EXAMPLE` in a
real migration's name.

## Required header

Every migration file must contain these two lines. `scripts/gen-drift-sql.sh`
reads them; a file without them is invisible to the drift check and the
generator refuses to run.

```sql
-- migration-version: 20260804153000
-- migration-name:    readmit_reopened_needs
```

- **`migration-version`** is the version string the *database* assigned when the
  migration was applied — the `version` column of
  `supabase_migrations.schema_migrations`. Write `PENDING` while the file exists
  but has not been applied yet, then replace it with the real value.
- **`migration-name`** must match the `name` column in that same ledger row. If
  the two disagree, `scripts/check-drift.sql` reports a **CRITICAL name
  mismatch** — that is the check doing its job, not a false alarm.

This header is how a file on disk is tied to a row in the database. Without it
there is no link, and "we have a repo" becomes a story rather than a fact.

## How to write one

Copy `0001_EXAMPLE_template.sql`. It is a real, runnable shape with the house
rules baked in as comments, and it is worth reading once end to end before your
first migration.

## The house rules, in short

Full reasoning is in the template. The short version:

| # | Rule | Why |
|---|---|---|
| 1 | **Snapshot before you replace** — capture `pg_get_functiondef()` into `ottoq_schema_snapshots` first | at 2am the old body is a `SELECT` away instead of gone |
| 2 | **Never DROP** — `CREATE OR REPLACE` only | a DROP is irreversible and takes its dependents with it |
| 3 | **Never touch `ottoq_events`** | ~9 GB of an 11 GB database, append-only guarded |
| 4 | **A failure must never abort `decide_tick`** — total functions, `ELSE` branches, no raise on the tick path | one unmapped service code once rolled back every tick while cron reported "succeeded" |
| 5 | **One concern per file** | small migrations are reviewable and revertible; big ones are neither |
| 6 | **Commit the file first, then apply it** | see `../../scripts/APPLYING.md` |
| 7 | **Add an md5 guard** when replacing an existing function | proves you are replacing the body you think you are, instead of silently clobbering someone's hotfix |

### Honest note on rules 1, 2 and 7

These are the right rules, not yet the universal habit. Measured against the
live ledger's 621 applied migrations on 2026-08-04:

| Practice | Migrations using it | Share |
|---|---:|---:|
| snapshot into `ottoq_schema_snapshots` | 29 | 4.7% |
| md5 guard (`def_md5`) | 35 | 5.6% |
| contained a `DROP FUNCTION/TABLE/COLUMN` | 15 | 2.4% |

So the safety idioms are real and in use — `ottoq_schema_snapshots` holds 6,491
captured definitions — but they were applied to a minority of changes, and 15
migrations dropped objects outright. This repo is where that stops. Do not read
the 4.7% as permission; read it as the reason the folder exists.

## Order of operations

1. Write `NNNN_short_name.sql` with `migration-version: PENDING`.
2. **Commit it.**
3. Apply it to the database *from that file* — `../../scripts/APPLYING.md`.
4. Put the real version in the header.
5. `bash ../../scripts/gen-drift-sql.sh`
6. Add a row to `../../MIGRATION_LOG.md`.
7. Commit again, then run `../../scripts/check-drift.sql`. It must be **CLEAN**.
