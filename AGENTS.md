# AGENTS.md — otto-q-core

> **Build doctrine → [`CLAUDE.md`](CLAUDE.md) · Research doctrine → [`HERMES.md`](HERMES.md).**

**This repo is the OTTO-Q brain, in files.** OTTO-Q is the orchestration layer for OTTOYARD's
autonomous-vehicle depots — the software that decides which vehicle goes where, when, in what order,
and **why**, and can prove the reasoning to an OEM auditor.

## The rule this repo exists to enforce

> **If it isn't a committed file, it didn't happen.**

Every change to the brain is written as a **migration file**, **committed**, and **then applied to
the database from that file** — in that order. This exists because the live database once had **621
applied migrations while the founder's working folder had 80 files with zero overlap**.

## Before you touch anything

1. **Read `MIGRATION_LOG.md`.** It is meant to be one row per change, with the symptom that started
   it, the objects touched, who applied it, and **the query that proves the behaviour actually
   moved**. "Verified" never means "applied without error." ⚠️ As of 2026-08-18 the log holds a
   single row against 41 migration files — until it is backfilled, the migration-file headers are
   the primary record.
2. **Read `db/baseline/`** — `functions_public.sql`, `functions_ottoq.sql`, `functions_twin.sql`,
   `tables.sql`, `rls_policies.sql`, `cron_jobs.sql`. You can understand the whole brain without
   touching the database.
3. **Migrations run 0001–0042 (there is no `0024`).** Per their headers all are applied, including
   `0017_stop_is_two_phase…` (initially held back, applied 2026-08-09 with live verification). No
   unmerged branches remain on origin. ⚠️ Files `0026`–`0033` and `0035`–`0042` (except `0034`)
   carry no `migration-version:` header, so `gen-drift-sql.sh` rejects them and
   `check-drift.sql`'s manifest cannot see them — backfill headers before trusting a CLEAN drift
   report. *(Reconciled 2026-08-18, Run 1 C1 — see `SYSTEM_TOPOLOGY.md`.)*

## Landmines specific to this repo

- **Never `DROP FUNCTION` before capturing `pg_get_functiondef`.** `pg_proc` is the only live copy.
- **`ottoq_stall_bookings.stall_id` is `ON DELETE CASCADE`.** Deleting a stall silently vaporises
  ledger rows with no error. **Re-home, never retire.**
- **`ottoq_purge_prior_runs` sweeps every `public.ottoq%` table with a `sim_run_id` column** — any
  new table you create with that column will be wiped at the next run start unless you add it to the
  exclusion list. It scans `information_schema.columns`, which includes **views**.
- **`enum::text = 'literal'` silently defeats partial indexes.** One such cast made a shield rule scan
  28,963 rows per call (2,449 ms → 0.83 ms once fixed); another made an occupancy check match **zero
  rows forever**, which is how the A/B baseline ended up with unlimited chargers.
- **`current_setting()` returns the GUC *display* form** (`'2min'`); `pg_settings.setting` returns the
  raw value (`'120000'`). Casting the former to a number raises 22P02 — that shipped a dead guard.
- **A routine that `COMMIT`s cannot carry a `SET` clause.** Use
  `PERFORM set_config('search_path','twin, ottoq, public, extensions', false);` in the body.
- **One pass, not N.** Per-item `prosrc LIKE` scans in a migration are quadratic and once saturated
  the instance for 25 minutes.
- **Any migration expected to exceed ~15 s is an outage risk.** Pause the run first, use
  `SET LOCAL lock_timeout='8s'`, resume. **Never blind-retry a timed-out migration — poll whether it
  landed.**
- **The Supabase MCP migration runner mis-parses `$$`-quoted function bodies.** Create functions via
  raw `execute_sql` with `$fn$` quoting, then `apply_migration` for the ledger row.
- **Every seam that maps a vocabulary must be a TOTAL function.** One unmapped `leg_type` value once
  aborted every decision in the depot **while cron reported success.**

## Verify before you PR

```bash
psql -f scripts/check-drift.sql   # or run it via your DB tool — must report CLEAN
```

Add your `MIGRATION_LOG.md` row in the same PR. All six columns.
---

## The full context lives elsewhere

**Read this first, before any substantive work:**

```bash
git clone https://github.com/OTTOYARD/ottoyard-agent-context.git
```

That repository is the shared brain for agents on this project: architecture, the founder's binding
doctrine, the known-issues register, a ranked backlog, hard-won lessons, and a verbatim copy of the
79 memory files Claude Code accumulated while building this system. Start with its `README.md` and
`docs/16_FIRST_SESSION_RUNBOOK.md`.

## Rules that apply in every OTTOYARD repo

**⚖️ The law.** *OTTO-Q decides. OTTO-TWIN executes and owns world state. The renderer only draws.*
Decision-layer code that mutates world state is a defect on sight. Renderer code containing world
logic is a defect on sight.

**Branch, verify, PR. Never merge.** Chase Ballenger (founder) is the only one who merges. Branch as
`hermes/<slug>` or `claude/<slug>`, prove it works yourself, then open a PR whose description carries
**the evidence** — real numbers, real row counts, real screenshots — plus what you did *not* verify
and what could break. Half-done labelled half-done is fine; half-done labelled done is not.

**🚨 `git fetch origin` before you reason about anything.** The clones on the founder's Desktop have
been up to **77 commits behind**. Compare against `origin/main`, never local `main`. A branch still
existing is not evidence it is unmerged — check
`git rev-list --count origin/main..origin/<branch>` (0 means merged).

**Two identity traps.** `OTTOYARD` on GitHub is a **personal account, not an organization**
(`/orgs/OTTOYARD/...` returns 404 — use `/user/repos`). And GitHub **rejects pushes authored as
`chase@ottoyard.com`** — commit as a noreply identity.

**Three Supabase projects — the engine is `gxdrcyphqjzjsuhxuqtg` (otto-q-core, us-east-1).**
`ycsisvozzgmisboumfqc` is the **OTTOYARD MVP** (us-east-2): the original demo backend, OrchestrAV's
auth/billing/retail (`ottoq_ps_*`) home, and Hermes's live `intelligence_events` pipeline — active,
never the engine. `sovyxwtrqfmizelrammm` (Fleet Dashboard) is INACTIVE with zero live callers.
⚠️ **Every `supabase/config.toml` in every OTTOYARD repo points somewhere else** — at dead refs
(`hfjaofyfxsyniohdfacg`, `odhpbdhnpcrjeaxvbrzd`), at the MVP, or at a placeholder. The real ref is
hardcoded in client code instead. **Pass `--project-ref gxdrcyphqjzjsuhxuqtg` explicitly to any
Supabase CLI command that writes.** *(DB labels reconciled 2026-08-18 by Run 1 C1 — see
`SYSTEM_TOPOLOGY.md`.)*

**Never disable pg_cron job 12** (`ottoq-demo-metronome`). It **is** the simulation run engine.
Disabling it stops every run while everything still looks green.

**Honesty about numbers is a hard requirement here.** Always state your denominator. Never quote
`vehicles_turned_around`, `fleet_ready_pct`, or `gate_backlog` — they are final-frame instantaneous
counts that structurally penalise OTTO-Q. Interrogate the baseline before believing a win: it has
been invalid twice, both times in our favour. Read
`ottoyard-agent-context/memory/reference_ottoq_real_edge.md` before quoting any comparative figure.
