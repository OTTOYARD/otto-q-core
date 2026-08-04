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
| 2026-08-04 | `db/migrations/0002_approval_gate_decider.sql` (ledger version **20260804140958**, name `approval_gate_decider`) | Made the in-depot reassignment gate **answer** instead of absorb. Added `public.ottoq_decide_indepot_approvals` (OTTO-Q's own policy decider: 8 sim-min latency, 30 sim-min hard expiry backstop that runs even when the kill switch is off). Replaced 5 existing functions: `public.ottoq_indepot_reassignment_guard` (stamps a sim-domain `requested_at_sim`/`decide_after_sim`/`expires_at_sim` trio + `clock_domain` tag into the payload, real columns untouched), `twin.ottoq_opportunistic_scan` (type-filtered to the twin's own approvals so a doctrine gate is never settled by a seeded coin flip), `ottoq.ottoq_readmit_reopened_needs` and `ottoq.ottoq_readmit_resumed_visits` (approval exclusion **narrowed**, not removed — the gate still blocks genuine changes of plan and is ignored only for the vehicle's own fault deferral; emitted doctrine string corrected to match the code), and `twin.ottoq_sim_vehicle_exception_handler` (technician flip now resolves the ledger row in the same transaction; `auto_staged` path resolved; **tow-retrieval clock domain fixed**; named top-level safety net added). 3 new policy dials catalogued. | `ottoq_ops_approvals` was an **absorbing state** for `indepot_reassign`: 55 pending rows, none ever decided, none able to expire. Root cause was a clock-domain mismatch — the guard stamped `decide_after`/`expires_at` with `now()` (REAL) while the only decider compared them to the SIM clock, 325 min apart in the measured run, so the rows were neither decidable nor expirable. Those rows then barred **27 of the 29 vehicles (93.1%)** holding cut-short work from readmission, which is why cut-short work was never re-booked: 0 of 38, then 0 of 52, three phases running. Paired defect: tow retrieval compared REAL `last_state_change` to the SIM clock and fired **zero** times, leaving broken vehicles unable to leave. | Claude, MCP `apply_migration` (name `approval_gate_decider`). **Applied byte-for-byte from the committed file** — the ledger's stored statement md5 `b2f860822b7df8037967962def5ed03d` equals the md5 of the file's exact contents, so the database and the repo hold identical SQL. | **Yes — the absorbing state is gone, measured, not asserted.** All 5 md5 guards matched live before apply. One call to the new decider resolved **55 of 55** stranded rows (`rows_resolved=55`); every one carries an audited `payload.decision`. **V1**: `indepot_reassign` now 55 `declined` + 3 `approved`, **0 pending**, 55/55 with a decider stamp and an audited decision, all with reason `atomic_visit_protected_bounded_defer_budget_governs` (the deferral verdict is DECLINED by design, so the eviction machinery and the phase-11 baseline are untouched). **V2** stuck-beyond-ceiling = **0**. **V3** technician-approved contradictions = **0**. Nemotron doctrine held: `copilot_recommendation='unavailable'`, `copilot_binding=false` on all 55 — it was unreachable and the system still decided, conservatively. **Readmission reachability on the real population** (denominator: the 29 vehicles holding an open reopened need with ≥1 atom not done/cancelled), OLD rule vs NEW rule evaluated against the preserved pre-fix approval states: barred **27 → 0**, reachable **2 → 29** (reproduces the diagnosed 93.1% exactly). **Tow clock fix**, evaluated with the real clocks of run `73f53ed5` (real ran **325.3 min ahead** of sim): old predicate `false` (never fires — matches the observed zero retrievals), new predicate `true` in both the sim and the legacy-real branch. `scripts/check-drift.sql` run live after apply: **VERDICT CLEAN**, Sections A/B/C/D all OK. Cron 10 and 12 left **active throughout** (no pause was needed) — 4/4 and 7/7 runs succeeded post-migration, zero failures. **NOT yet verified — needs the bounded run:** V4 (cut-short work actually re-booked into a space), V5 (tow retrieval firing end-to-end), V6 (phase-11 baseline re-cert). Those need ≥139 sim-min captured after the run is stopped, per the file's own §10. |
| 2026-08-04 | `db/baseline/` (snapshot, not a migration) | Captured the whole live brain into files for the first time: 336 `public` + 48 `ottoq` + 71 `twin` user-defined routines (455 total), tables, RLS policies, cron jobs, and the 27 deployed edge functions. Established `db/migrations/`, `scripts/check-drift.sql`, `scripts/gen-drift-sql.sh`, `scripts/APPLYING.md`, and this log. | The brain existed only inside Supabase with no source repo. The live ledger held **621 applied migrations**; the founder's working folder held 80 migration files and **none of the 80 appeared in the live ledger**. There was nothing to review, revert, or diff. Baseline = the line from which "if it isn't a committed file, it didn't happen" starts being true. | Claude (read-only session) | **Yes.** Counts re-verified live against `pg_proc`/`pg_depend` on 2026-08-04: public 336, ottoq 48, twin 71, ledger 621 rows, 27 edge functions all ACTIVE — all five match the export exactly, zero drift. `scripts/check-drift.sql` run live the same day: **VERDICT CLEAN**, Sections A/B/C/D all OK. Alarm proven to fire via a negative test (moved baseline cut + wrong name + phantom file → 2 CRITICAL drift rows, 1 CRITICAL name mismatch, 1 WARN orphan, 1 INVESTIGATE count diff). |

---

## Objects created outside a migration — declared, not hidden

The drift check counts routines, so a plain table created by hand is invisible to
it. Anything created outside the migration path gets declared here instead.

| Date | Object | Why it exists | Safe to drop? |
|---|---|---|---|
| 2026-08-04 | `public.pre0002_approvals_evidence` (58 rows) | Snapshot of `ottoq_ops_approvals` for `approval_type='indepot_reassign'` taken **immediately before** migration 0002's decider was first run, so the pre-fix state of the 55 stranded rows survives. It is what the 27→0 readmission-reachability before/after was measured against. Deliberately **not** `ottoq`-prefixed, so starting a run cannot purge it. | Yes, once the ≥139 sim-min certification run for V4–V6 is done and its results are logged. It holds no brain logic — it is evidence. |

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
