# otto-q-core — the OTTO-Q brain, in files

## 1. What this is

This repo is the **source of truth for the OTTO-Q brain** — the decision-making
software that runs the depot. Until today that software existed in exactly one
place: a live database you can only reach by logging into a website. There was no
copy, no history, and no way to see what changed. This repo is that copy. From
here on, the brain is a set of files you can read, review, and roll back — and the
database is downstream of the files, not the other way around.

---

> # 2. THE RULE
> ## If it isn't a committed file, it didn't happen.
>
> Every change to the brain is **written as a migration file**, **committed to
> this repo**, and **then applied to the database from that file** — in that
> order. A change that only exists in the database is not a change we own. It is
> a change we will one day have to reverse-engineer.

---

## 3. Why this exists

Not a hypothetical. Three measured facts:

- **The brain had no source repo at all.** 455 database functions and 27 edge
  functions, all of them living only inside Supabase project
  `gxdrcyphqjzjsuhxuqtg`. Edits were typed at the live system.
- **The live database has 621 applied migrations. The founder's working folder
  had 80 migration files. Zero of the 80 appear in the live ledger.** The folder
  that looked like the history of the system had no overlap with the actual
  history of the system.
- **A snapshot repo drifted 457 migrations behind before anyone noticed.** It was
  never wired to fail loudly, so it just quietly stopped being true.

The cost of that is not abstract: nothing to review before a change, nothing to
revert to after one, and nothing to diff when something breaks. Every fix started
with archaeology.

This repo is where that stops. The baseline in `db/baseline/` is the brain as of
**2026-08-04**, verified against the live database the same day.

---

## 4. The map — where each piece of OTTO-Q actually lives

| Piece | Written where | Runs where |
|---|---|---|
| **The brain** — decisions, orchestration, the twin | **This repo** (`otto-q-core`) | Supabase project `gxdrcyphqjzjsuhxuqtg` |
| **The cockpits** — `ottoyarddepot-sim`, `ottoyard-field-ops`, the Orchestra app (`ottoyard-OTTO-Q`) | Their own GitHub repos | Lovable-hosted sites |
| **The energy optimizer** — `ottoq-intelligence` | Its own GitHub repo | An EC2 box that **production currently ignores** |
| **`otto-q-core-snapshot`** | Generated, never hand-written | Nowhere — it is a **photocopy used as a drift detector**, not a source |

Two things worth saying out loud:

- The repo named `ottoyard-OTTO-Q` is **misleadingly named**. It is the Orchestra
  cockpit app, not the brain. The brain is this repo.
- `ottoq-intelligence` runs, but production does not read from it today. Do not
  assume a number produced there is a number the depot acted on.

---

## 5. How to make a change

Full procedure: **`scripts/APPLYING.md`**. In four steps:

1. **Write it as a file.** Copy `db/migrations/0001_EXAMPLE_template.sql` to
   `db/migrations/NNNN_short_name.sql` and write the change there.
2. **Commit the file** — before it touches the database.
3. **Apply it to the database from that file.** Then record the version the
   database assigned in the file's header, run `bash scripts/gen-drift-sql.sh`,
   and add a row to `MIGRATION_LOG.md`.
4. **Run `scripts/check-drift.sql`.** It must come back **CLEAN**. If it doesn't,
   the repo and the database disagree — fix that before doing anything else.

---

## 6. What NOT to edit

**`db/baseline/`** and **the `otto-q-core-snapshot` repo.**

Both are generated photographs. Nothing reads them. There is no deploy step that
picks them up. If you "fix a bug" in either one, **the bug is still live in the
database and your fix is invisible** — to the system, to your teammates, and to
future you. Worse, the file now disagrees with reality, so the next person to read
it is misled.

Every generated file says so on line 1:

```
-- GENERATED / SNAPSHOT FILE — DO NOT EDIT. Changes go in db/migrations/.
```

Changes go in `db/migrations/`. Always.

---

## What is in here

| Path | What it is |
|---|---|
| `db/baseline/` | A photograph of the whole brain as of 2026-08-04 — functions, tables, RLS policies, cron jobs. Reference only. **Do not edit.** |
| `db/migrations/` | **Where every change is born.** One numbered file per change. |
| `edge-functions/<slug>/index.ts` | The 27 deployed Supabase edge functions. |
| `scripts/check-drift.sql` | **The smoke alarm.** Has anything been applied to the database that has no file here? |
| `scripts/gen-drift-sql.sh` | Refreshes the drift check's manifest from the migration files. |
| `scripts/APPLYING.md` | The procedure. Read before your first change. |
| `MIGRATION_LOG.md` | The human record: what changed, why, who, and how it was verified. |

---

## Is the repo currently telling the truth?

Run `scripts/check-drift.sql` against the live database and read the first row.

Last run — **2026-08-04, live**:

```
CLEAN  VERDICT   Every applied migration is accounted for. Repo is the source of truth.
INFO   SCOPE     Ledger rows: 621. Baseline covers everything up to version
                 20260803210034 (621 rows). Migration files in repo: 0.
                 Files written but not yet applied: 0.
OK     A. IN DATABASE, NOT IN REPO   none — nothing applied past the baseline without a file
OK     B. IN REPO, NOT IN DATABASE   none — every committed migration file is applied
OK     C. NAME MISMATCH              none — file names and ledger names agree
OK     D. ROUTINE COUNT vs BASELINE  schema ottoq   baseline 48,  live 48   (match)
OK     D. ROUTINE COUNT vs BASELINE  schema public  baseline 336, live 336  (match)
OK     D. ROUTINE COUNT vs BASELINE  schema twin    baseline 71,  live 71   (match)
```

Zero migration files is the correct and honest state on day one: the baseline
covers all 621 applied migrations, and nothing has been applied since.

---

## What this tooling does *not* cover — stated up front

- **SQL typed into the Supabase dashboard editor writes no ledger row**, so
  Sections A–C of the drift check are blind to it by construction. Section D
  (live routine counts vs baseline) is the backstop.
- **Section D counts routines, it does not compare their bodies.** A change that
  replaces a function without adding or removing one still gets past it. The only
  complete answer is re-exporting `db/baseline/` and diffing.
- **Edge functions are not in Postgres**, so the SQL check cannot see them at all.
  Diffing deployed edge functions against the committed files is manual today.

These gaps are written down rather than papered over. A green drift check is
strong evidence, not a guarantee — and knowing the difference is what makes it
worth running.
