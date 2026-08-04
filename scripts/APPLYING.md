# APPLYING.md — how to change the OTTO-Q brain

This is the procedure. It is short on purpose. Follow it every time, including
the times it feels like overkill.

> **The rule: if it isn't a committed file, it didn't happen.**

---

## The one-paragraph version

The brain is 455 Postgres functions and 27 edge functions living inside a single
Supabase project. It has no build step and no deploy pipeline — a change becomes
real the moment someone runs SQL against it. That is why the file has to come
first: the file is the only thing that can be read, reviewed, reverted, or
blamed. Write the file, commit the file, then run the file. Never the other way
round.

---

## Part 1 — the numbered procedure

### 1. Write the file

Copy `db/migrations/0001_EXAMPLE_template.sql` to
`db/migrations/NNNN_short_name.sql` (next free number). Fill in the header:

```sql
-- migration-version: PENDING
-- migration-name:    short_name
```

`PENDING` is correct at this stage — the database has not seen it yet.

### 2. Make it a *good* migration

Not optional, and not style preference. Each rule below is a scar. The reasoning
is in the template's comments; the checklist is:

- **Snapshot before you replace.** `INSERT INTO ottoq_schema_snapshots ... SELECT
  pg_get_functiondef(p.oid), md5(...)` for every function the file touches,
  before it touches them.
- **md5 guard.** Assert the live definition is the one you based your change on.
  If someone hotfixed it in the SQL editor since you started, this raises instead
  of silently deleting their fix.
- **Never DROP.** `CREATE OR REPLACE` only. Retiring an old signature is a
  separate, later migration.
- **Never touch `ottoq_events`.** ~9 GB of an 11 GB database, append-only guarded.
- **A failure must never abort `decide_tick`.** Anything on the tick path is a
  total function: every input has a defined output, every `CASE` has an `ELSE`,
  and errors are swallowed and warned rather than raised. A rolled-back tick
  looks like "succeeded" in cron and produces zero stall assignments.
- **One concern per file.**

### 3. Commit — *before* applying

```bash
cd ~/Desktop/OTTOYARD/otto-q-core
git add db/migrations/NNNN_short_name.sql
git commit -m "migration NNNN: short_name — <what and why in one line>"
```

If applying it goes badly, the file already exists and describes exactly what
was attempted. That is the entire point of this ordering.

### 4. Apply it — from the file

Pick one. Whichever you use, the SQL that runs must be the SQL in the committed
file, unedited.

**a) Supabase MCP (what Claude uses):** `apply_migration` with `name` set to the
migration's `short_name` and `query` set to the file's contents. This writes a
ledger row.

**b) Supabase CLI:**
```bash
supabase db push          # from a linked project
```

**c) Dashboard SQL editor — last resort.** It runs the SQL but **does not write a
ledger row**, so the change becomes invisible to Sections A–C of the drift check.
If you must use it, say so in `MIGRATION_LOG.md` in the same sitting, and expect
Section D (routine counts) to be the only automatic evidence it happened.

### 5. Record the version the database assigned

```sql
SELECT version, name FROM supabase_migrations.schema_migrations
 ORDER BY version DESC LIMIT 1;
```

Put that `version` into the file's header, replacing `PENDING`. Confirm the
`name` matches `migration-name` exactly.

### 6. Refresh the drift manifest

```bash
bash scripts/gen-drift-sql.sh
```

This rewrites the generated block inside `scripts/check-drift.sql` from your
migration files' headers. It fails loudly if any file is missing its header.

### 7. Log it

Add one row to `MIGRATION_LOG.md`: date, file, what changed, why, applied by,
and — the column people skip — **verified**: the query or run that proves the
behaviour actually changed. "Applied without error" is not verification.

### 8. Commit again, then prove it

```bash
git add -A && git commit -m "migration NNNN applied: version <version>"
```

Run `scripts/check-drift.sql` against the live database. It must return
**CLEAN**. If it does not, you are not finished.

---

## Part 2 — the drift check

`scripts/check-drift.sql` is the smoke alarm. Run it:

- after every migration,
- at the start of any working session on the brain,
- before any demo,
- any time you are not sure whether the repo still matches reality.

It is read-only and safe to run at any time, including mid-demo.

**What it tells you**

| Section | Meaning |
|---|---|
| **VERDICT** | `CLEAN`, `INVESTIGATE`, or `DRIFT` — read this line first |
| **A. IN DATABASE, NOT IN REPO** | someone applied a change with no committed file. **This is the alarm.** Write the file today. |
| **B. IN REPO, NOT IN DATABASE** | a committed migration was never applied, or its header has the wrong version |
| **B2. WRITTEN, NOT YET APPLIED** | files still marked `PENDING` — normal while a change is in flight |
| **C. NAME MISMATCH** | the file and the ledger row disagree about what the migration is called |
| **D. ROUTINE COUNT vs BASELINE** | live function counts vs what `db/baseline/` recorded |

**What it cannot tell you.** Sections A–C read the migration ledger. SQL typed
directly into the dashboard editor writes no ledger row at all, so those sections
are blind to it by construction. Section D is the backstop: if A and B are clean
but D disagrees, the brain was edited outside the migration path. Section D
counts routines — it does not compare their bodies, so a same-count body edit
still gets past it. The only complete answer is re-exporting `db/baseline/` and
diffing. Nobody should mistake a green check for a guarantee.

---

## Part 3 — emergencies

It will happen: something breaks during a demo or an investor run and it has to
be fixed in the next ninety seconds. The rule bends here, and it bends in exactly
one direction.

1. **Fix it live.** Go ahead. Use the SQL editor. Keeping the system up wins.
2. **Before you do, snapshot.** One statement, five seconds, and it is the
   difference between a bad afternoon and a lost function body:
   ```sql
   INSERT INTO public.ottoq_schema_snapshots
          (label, object_kind, schema_name, object_name, definition, def_md5)
   SELECT 'hotfix_YYYY_MM_DD_pre', 'function', n.nspname, p.proname,
          pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = '<the function>';
   ```
3. **Write the file the same day.** Not "soon", not "next sprint" — the same day,
   while you still remember what you typed and why. Copy the exact SQL you ran
   into `db/migrations/NNNN_hotfix_short_name.sql`, note in the header comment
   that it was applied live first, commit it, and log it.
4. **Expect to be caught.** If you applied it through a path that wrote a ledger
   row, the drift check will report it under Section A until the file exists.
   That is the alarm working. If you applied it through the SQL editor, no alarm
   fires — which is precisely why step 3 is on you and not on the tooling.

An emergency changes *when* the file gets written. It never changes *whether*.

---

## Part 4 — edge functions

The 27 Supabase edge functions in `edge-functions/<slug>/index.ts` are not in
Postgres, so the SQL drift check cannot see them at all.

1. Edit `edge-functions/<slug>/index.ts` in this repo.
2. Commit it.
3. Deploy that file (`supabase functions deploy <slug>`, or the MCP
   `deploy_edge_function` tool with the file's contents).
4. Log it in `MIGRATION_LOG.md` like any other change.

To check for drift, fetch the deployed body (`get_edge_function`) and diff it
against the committed file. There is no automated alarm for this yet — it is a
known, open gap, written down here so it is not mistaken for covered ground.
