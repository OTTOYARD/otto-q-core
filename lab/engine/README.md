# `lab/engine/` — the research lab's copy of the OTTO-Q engine, in a local PostgreSQL 17

The research lab of `docs/FRONTIER_PLAN_2026-11-03.md` (item E1): a private copy of the engine's database,
outside production, that runs the twin unpaced, forks a run at any tick, and runs several replicas at once.
It holds the twin depot's reference data and nothing else: no run data, no other depot, no person, no secret
(rule 8, rule 10).

**Two ways to build it, and only one is faithful.**

| build | from | matches production | use |
|---|---|---|---|
| `build_from_prod.sh` (since 2026-11-04) | an export of production's catalog and the twin depot's reference data, read through the Management API's read-only endpoint | every routine, table, trigger, index, policy, type, sequence, comment, ACL and cron job, and the ledger's versions (6 objects differ only as semantically identical deparse round-trips); the twin depot's world fingerprint exactly | **the lab** |
| `build_from_repo.sh` (2026-11-03) | `db/baseline/` + `db/migrations/` | 300 of 1,037 routines, 177 of 453 tables (G509) | measuring the repository as a record |

Read `reports/e1_acceptance_2026-11-04.md` for what the lab measured on 2026-11-04 (its three acceptance
tests, and what they found), and `reports/fidelity_2026-11-03.md` for why the repository alone cannot rebuild
the engine.

## Quick start

```bash
bash lab/engine/install_server.sh                       # once, as root: PostgreSQL 17 + PostGIS from PGDG
bash lab/engine/build_from_prod.sh lab/engine/export/2026-11-04 lab/engine/export/2026-11-04/data
PY=/var/tmp/ottoq_lab_venv/bin/python; D="host=/var/tmp port=55433 dbname=ottoq_lab user=postgres"
$PY -I lab/engine/acceptance/fidelity.py   --dsn "$D" --data lab/engine/export/2026-11-04/data --out /tmp/fidelity.json
$PY -I lab/engine/acceptance/forks.py      --dsn "$D" --out /tmp/forks.json
$PY -I lab/engine/acceptance/throughput.py --dsn-base "host=/var/tmp port=55433 user=postgres" --out /tmp/throughput.json
```

The build takes about 15 seconds. The committed export needs no token. A fresh export does:

```bash
export SUPABASE_ACCESS_TOKEN=...   # or Supabase_Key, the name the session environment used on 2026-11-04
python3 -I lab/engine/lib/export_prod.py --out lab/engine/export/$(date -u +%F)
python3 -I lab/engine/lib/export_reference_data.py --export lab/engine/export/$(date -u +%F) --out lab/engine/export/$(date -u +%F)/data
```

## What is here

| path | what it is |
|---|---|
| `install_server.sh` | installs PostgreSQL 17 and PostGIS from PGDG (the steps run on 2026-11-04; no Docker daemon was available to test a container) |
| `build_from_prod.sh` | builds `ottoq_lab` from a production export: roles, shims, the cron stand-in, the schema to a fixpoint, the reference data, `lab.build_info` |
| `build_from_repo.sh` | builds `ottoq_lab` from this repository (G509's measurement) |
| `export/<date>/` | a production export: `NN_<phase>.sql` (one statement per `-- @@ kind identity` marker), `manifest.json` (read times, counts, file digests, production's engine hash), `data/` (the twin depot's reference data, one JSON file per table, and its manifest with production's world fingerprint) |
| `lib/prod_read.py` | the only way the lab reads production: `POST /v1/projects/{ref}/database/query/read-only` (runs as `supabase_read_only_user`, `transaction_read_only = on`), one project, token from the environment, never printed |
| `lib/export_prod.py` | the schema export: production's own deparsers with `search_path = ''`; refuses object kinds it does not reproduce and any statement shaped like a secret |
| `lib/export_reference_data.py` | the twin depot's reference data: an explicit list of 90 tables with a filter and a reason each, and the list of what is never copied (personal data, credentials, history, run data, evidence) |
| `lib/load_export.py` | loads an export phase by phase, to a fixpoint; default privileges go on last |
| `lib/load_reference_data.py` | loads the reference data with triggers off, then reports every foreign key whose parent was not copied |
| `lib/lab_server.sh` | the lab server's settings and bootstrap, shared by both builds; refuses to build if a job scheduler is loaded |
| `lib/lab_run.py` | the tick driver and fork driver: an arm started exactly as one arm of `ottoq_determinism_pair`, ticked, digested with `ottoq_ab_arm_atoms` and per tick, forked with savepoints |
| `lib/fidelity_full.py` | the object-by-object comparison with production (the 2026-11-03 census plus `sql/fidelity_extra.sql`) |
| `acceptance/fidelity.py`, `forks.py`, `throughput.py` | E1's three acceptance tests |
| `sql/00_roles.sql`, `sql/10_supabase_shims.sql` | production's roles (all `NOLOGIN`) and the Supabase stand-ins: `auth`, `net` (no outbound HTTP), `vault` (empty), `storage`, `supabase_migrations`, extensions, the database's locale settings |
| `sql/12_cron_standin.sql` | the `cron` schema without a scheduler (see "The lab server") |
| `sql/20_repo_gaps.sql`, `sql/30_post_build.sql`, `lib/load_baseline.py`, `lib/apply_migrations.py`, `lib/classify_failures.py`, `lib/compare_ledger_text.py`, `lib/fidelity.py`, `lib/sqlsplit.py` | the repository build and its 2026-11-03 measurement |
| `sql/31_post_build_prod.sql` | the production build's last step: every cron job inactive, `lab.build_info` records the export |
| `reports/` | build results, fidelity measurements, the acceptance report and its evidence |

## The lab server

| | |
|---|---|
| PostgreSQL | 17.11 from apt.postgresql.org, PostGIS 3.7.0 (production: 17.6, PostGIS 3.3.7; extension-owned objects are left out of every comparison) |
| data / socket / port | `/var/tmp/ottoq_lab_pg17`, `/var/tmp`, `55433` (no TCP listener) |
| started as | the `postgres` OS user, by `lib/lab_server.sh` on first use |
| job scheduler | **none.** pg_cron is not installed or loaded. Its scheduler held a session open in the lab database even with `cron.launch_active_jobs = off`, and `CREATE DATABASE … TEMPLATE` refuses a template anyone is connected to, which the parallel replicas and long forks need (measured 2026-11-04). `sql/12_cron_standin.sql` gives the lab pg_cron 1.6's tables and the functions the engine calls; production's 24 jobs are rows in it, all inactive, and no process exists to run them. |
| outbound HTTP | none: neither the `http` extension nor `pg_net` is installed; `net.http_get/post/delete` return a fresh id and do nothing. So the agent's and the solvers' calls go nowhere, and a certification arm (cuOpt quiesced at run scope, 0152) runs the deterministic core alone, as in production. |
| locale | database `ottoq_lab` is ICU `en-US` (collation version 153.121, the version production reports), `LC_COLLATE`/`LC_CTYPE` `en_US.UTF-8`, `extra_float_digits = 0`, `jit = off`, as production |
| one deliberate difference | production's `statement_timeout` is 120 s; the lab keeps 0, because research runs are long transactions |

## How the copy is made, and what it is not

- **Read-only, enforced by production.** Every read runs as `supabase_read_only_user` in a read-only
  transaction (statement_timeout 2 min). The token in this session's environment can see three projects;
  `lib/prod_read.py` reads one.
- **What ran, not what was filed.** Definitions come from production's catalog, deparsed with
  `search_path = ''` so every name is schema-qualified, as `pg_dump` writes them. Six objects re-parse to
  a different tree than production stores (three CHECKs whose `BETWEEN`-born nested AND flattens; three views
  whose second `UNION` branch's unused column name re-derives as `text`). Their meaning is identical;
  `pg_dump` has the same round-trip.
- **ACLs exactly.** Objects are created with no default privileges in force, then each non-null ACL is
  rebuilt in its own array order, then production's default privileges are installed.
- **The twin depot only (rule 8).** 90 tables, 9,278 rows: the depot, its stalls, chargers, structures,
  battery, tariffs, staffing, scenarios, its 120 cars and their need profiles, the learned fits the kernel
  reads, the owners' contracts, and the engine's catalogs and settings (global and the twin depot's dial
  settings; never a past run's). Two foreign keys point at rows deliberately not copied: two fleet
  build-outs (`fleet150`, `fleet200`, both inactive) borrow 34 and 84 cars from the Benchmark depot, and two
  twin operators name API keys. So those build-outs cannot be switched on in the lab until their lent cars
  are copied too.
- **No run data, no evidence, no history, no people, no secrets.** `vault.secrets` is empty; event signing
  finds no key and records events unsigned, as production does when its vault is unreadable.
- **No other Supabase.** No PostgREST, GoTrue, Storage or Realtime. `postgres` is a superuser here and is
  not on Supabase.

## Forks and replicas

A fork is a `SAVEPOINT` in an arm's transaction (`lib/lab_run.py`): run to tick F, take the savepoint, run a
branch, digest it, `ROLLBACK TO SAVEPOINT`, run the next. Two things do not roll back: sequences (ids minted
in a later branch are higher) and `gen_random_uuid()`. Thirteen atoms are blind to both; the end state is not,
because it hashes the `robot_leg_id` 0764 mints into each cleaned visit's atoms (G510; `0794` is the fix,
in production and in this lab since 2026-11-05). Each branch sets `ottoq.sim_run_id` itself (the GUC hazard of `0329`/`0421`). A replica is
`CREATE DATABASE … TEMPLATE ottoq_lab`, for running arms in parallel or forks longer than one transaction
should hold.
