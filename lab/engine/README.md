# `lab/engine/` — the OTTO-Q engine, rebuilt from this repository in a local PostgreSQL 17

This is the first piece of the research lab (`docs/FRONTIER_PLAN_2026-11-03.md`, item E1, on branch
`claude/frontier-plan-certified-intelligence`): a private copy of the engine's database, outside
production, built only from what this repository holds, and measured object by object against
production. It runs nothing. It holds no run data and no reference data.

**Read `reports/fidelity_2026-11-03.md` before using it.** On 2026-11-03 the copy matched production on
300 of 1,037 routines and 177 of 453 tables. The repository alone cannot rebuild the engine today, and
the report says why, file by file.

## What is here

| path | what it is |
|---|---|
| `build_from_repo.sh` | (re)builds database `ottoq_lab` on the lab server; every step's result lands in `reports/` |
| `sql/00_roles.sql` | the cluster roles the engine's SQL names (production's, all `NOLOGIN` here) |
| `sql/10_supabase_shims.sql` | Supabase stand-ins: `auth`, `net`, `vault`, `storage`, `supabase_migrations`, extensions, default privileges, the database's locale-sensitive settings |
| `sql/20_repo_gaps.sql` | objects production has and no repo file creates, without which the baseline cannot load: schemas `ottoq`/`twin`, 26 enum types, 2 composite types (labels read from production's catalog, dated) |
| `sql/30_post_build.sql` | marks every pg_cron job inactive; writes `lab.build_info` (commit, branch, cutoff) |
| `sql/fidelity_objects.sql` | the object census run identically on the lab and on production |
| `sql/reference_closure.sql` | the call closure of the demo-run start and the tick, and the tables it names |
| `lib/sqlsplit.py` | statement splitter for the baseline dump (quotes, dollar quotes, comments) |
| `lib/load_baseline.py` | loads `db/baseline/` statement by statement, to a fixpoint |
| `lib/apply_migrations.py` | applies `db/migrations/` one file per transaction, in ledger order |
| `lib/classify_failures.py` | sorts migration failures by what stopped them |
| `lib/compare_ledger_text.py` | checks each migration file against the SQL the production ledger says ran |
| `lib/fidelity.py` | lab-side census, the production queries (printed, never run from here), the summary tables |
| `reports/` | build results (`build_<date>_*`), the fidelity report and its evidence (`fidelity_<date>/`) |

## The lab server

| | |
|---|---|
| PostgreSQL | 17.11 from apt.postgresql.org (`postgresql-17`, `postgresql-17-postgis-3` 3.7.0, `postgresql-17-cron` 1.6.8) |
| data / socket / port | `/var/tmp/ottoq_lab_pg17`, `/var/tmp`, `55433` (no TCP listener) |
| started as | the `postgres` OS user: `pg_ctl -D /var/tmp/ottoq_lab_pg17 -l /var/tmp/ottoq_lab_pg17/startup.log start` |
| beside it | the PG16 scratch server the repo's tests use (`/var/tmp`, port `55432`) is a separate cluster and is not touched |
| pg_cron | real, preloaded, `cron.database_name = ottoq_lab`, **`cron.launch_active_jobs = off`** (no job ever launches), and the build marks every job inactive as well |
| outbound HTTP | none: neither the `http` extension nor `pg_net` is installed; `net.http_get/post/delete` are stubs that return a fresh id and do nothing |
| locale | database `ottoq_lab` is ICU `en-US` (collation version 153.121, the same version production reports) with LC_COLLATE/LC_CTYPE `en_US.UTF-8`, so text sorts as it does in production |

Install once (root): add the PGDG apt source, put `create_main_cluster = false` in
`/etc/postgresql-common/createcluster.conf` (so no default cluster appears on port 5432/5433), then
`apt-get install postgresql-17 postgresql-17-postgis-3 postgresql-17-cron`. The script does the rest:
`initdb` on first use, the `en_US.UTF-8` libc locale, a Python venv with psycopg 3.3.7 at
`/var/tmp/ottoq_lab_venv`.

## Rebuild

```bash
bash lab/engine/build_from_repo.sh          # as root (it uses su postgres for initdb/pg_ctl), ~15 s
```

It drops and recreates `ottoq_lab`, then: roles → shims → repo gaps → `db/baseline/` → every
post-baseline migration that is not `PENDING` → post-build. Outputs:
`reports/build_<date>_baseline.{tsv,json}`, `reports/build_<date>_migrations.{tsv,json,log}`;
`lib/classify_failures.py reports/build_<date>_migrations.tsv` adds the failure causes.

**Baseline cutoff: ledger version `20260803210034`.** `db/baseline/README.md` verified its export against
a ledger of exactly 621 rows on 2026-08-04. On 2026-11-03 production's
`supabase_migrations.schema_migrations` holds exactly 621 versions below `0002`'s (`20260804140958`), the
last of them `20260803210034`. So the baseline stands for ledger rows up to that version and
`db/migrations/` starts at `0002`.

**Order.** Files with a ledger version are applied in version order. A file whose header says
`APPLIED-NO-LEDGER-ROW` or `UNVERIFIED-NO-LEDGER-ROW` has no version to sort by; it is placed straight
after its numeric predecessor's version (an inference: file numbers and versions disagree in 153
places). `PENDING` files are skipped and listed.

**Each file is one transaction:** `psql -X -1 -v ON_ERROR_STOP=1 -f FILE` (every file has at most one
`BEGIN`/`COMMIT` pair and nothing after it). A file whose first error is an undefined-object error
(42P01/42883/42703/42704/3F000) is retried once with `check_function_bodies = off` and recorded as
`ok_bodies_unchecked`; any other error is final, because production (which creates functions with
`check_function_bodies = on`) would have refused the file too. A file that applies and carries a ledger
version gets its row in the lab's `supabase_migrations.schema_migrations` (statements = the file's text).

## Measuring fidelity again

```bash
D="host=/var/tmp port=55433 dbname=ottoq_lab user=postgres"
O=lab/engine/reports/fidelity_$(date -u +%F)
/var/tmp/ottoq_lab_venv/bin/python -I lab/engine/lib/fidelity.py lab --dsn "$D" --out $O
/var/tmp/ottoq_lab_venv/bin/python -I lab/engine/lib/fidelity.py prod-sql aggregate --out $O   # also: routines, relations, types
```

`prod-sql` prints a single read-only `SELECT`. Run it against production through a read-only channel
(on 2026-11-03: the Supabase MCP tool's `execute_sql`) and save the answer as
`$O/prod_routines_classified.txt` etc., in the format of the 2026-11-03 files. The lab's objects travel
inside the query as 20-character tokens (identity and content digests), so production returns only
counts and the names of what differs or is missing: no function body and no row leaves production.
`fidelity.py summarize --out $O` prints the routine table the report quotes.

## What this copy is not

- **Not production's engine.** See the report: 557 of 1,037 routines and 255 of 453 tables are missing,
  177 routines and 21 tables differ, and 233 of 236 triggers are missing (the baseline export carries no
  triggers at all).
- **No run data and no reference data.** No depot, stall, vehicle, rule row, policy catalog row or
  calibration. The report lists the tables a demo run at the twin depot reads, with production's row
  counts for that depot; copying them is a separate, approved step.
- **No secrets.** `vault.secrets` starts empty and nothing is copied into it. The engine's signing keys
  live in production's vault; signing code finds no key here.
- **Supabase shims, not Supabase.** `auth.*` reads `request.jwt.*` settings nothing sets (so every
  function returns NULL); there is no PostgREST, GoTrue, Storage or Realtime. Roles exist only so that
  grants and `SET ROLE` resolve. `postgres` is a superuser here and is not on Supabase.
- **Settings differ in one deliberate place:** production's `statement_timeout` is 120 s (configuration
  file); the lab keeps 0, because research runs are long transactions.
