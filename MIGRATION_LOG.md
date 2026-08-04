# MIGRATION_LOG.md — the human record

One row per change to the OTTO-Q brain. Newest at the top.

This is the record a person reads. `supabase_migrations.schema_migrations` says
*that* something was applied; this file says **what it did and why**, in language
someone can act on six months from now at 2am.

**Every applied migration gets a row here.** Including hotfixes typed live during
a demo — those get their row the same day. See `scripts/APPLYING.md`.

**"Verified" is not "applied without error."** It is the query, count, or run
that proves the behaviour actually changed. If that column says "n/a", the change
is not finished.

---

| Date | File | What changed | Why | Applied by | Verified |
|---|---|---|---|---|---|
| 2026-08-04 | `db/baseline/` (snapshot, not a migration) | Captured the whole live brain into files for the first time: 336 `public` + 48 `ottoq` + 71 `twin` user-defined routines (455 total), tables, RLS policies, cron jobs, and the 27 deployed edge functions. Established `db/migrations/`, `scripts/check-drift.sql`, `scripts/gen-drift-sql.sh`, `scripts/APPLYING.md`, and this log. | The brain existed only inside Supabase with no source repo. The live ledger held **621 applied migrations**; the founder's working folder held 80 migration files and **none of the 80 appeared in the live ledger**. There was nothing to review, revert, or diff. Baseline = the line from which "if it isn't a committed file, it didn't happen" starts being true. | Claude (read-only session) | **Yes.** Counts re-verified live against `pg_proc`/`pg_depend` on 2026-08-04: public 336, ottoq 48, twin 71, ledger 621 rows, 27 edge functions all ACTIVE — all five match the export exactly, zero drift. `scripts/check-drift.sql` run live the same day: **VERDICT CLEAN**, Sections A/B/C/D all OK. Alarm proven to fire via a negative test (moved baseline cut + wrong name + phantom file → 2 CRITICAL drift rows, 1 CRITICAL name mismatch, 1 WARN orphan, 1 INVESTIGATE count diff). |

---

## How to add a row

Copy the row shape above. Fill in all six columns.

- **Date** — the day it was applied to the live database, not the day you wrote it.
- **File** — `db/migrations/NNNN_short_name.sql`.
- **What changed** — the objects touched and the behaviour that moved. Not "fix".
- **Why** — the symptom that started it. A number is worth ten adjectives.
- **Applied by** — a person or agent, and the path used (MCP `apply_migration`,
  Supabase CLI, or dashboard SQL editor). If it was the SQL editor, say so —
  that path writes no ledger row and the drift check cannot see it.
- **Verified** — the proof. Query, count, or run result.

Then re-run `scripts/check-drift.sql` and confirm **CLEAN**.
