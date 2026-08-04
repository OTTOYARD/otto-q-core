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

## Certification run for 0002 — V4/V5/V6 closed, and the falsifier resolved

Run `093c20f4-cf2d-4a6c-ab1c-693b98e51c0c` (seq 906), `busy_day`, seed 424242, live/3.0x,
depot `1111…1111`. **179.781 sim-min** (13:00:00 → 15:59:46.847), 733 ticks, auto-stopped by
the cron-12 metronome at its 60 real-min ceiling. Protocol floor of 139 sim-min cleared by
40.8 min. Run started 14:21:57 UTC, **after** the migration was applied at 14:09:58 UTC.
Evidence preserved in `public.phase13_*_424242`. All figures below were **re-derived
independently from live rows** in an adversarial pass, not copied from the capture harness.

| Test | Result |
|---|---|
| **V4 — cut-short work re-booked into a space it HELD** | **PASS, first time in four phases. 7 of 17 = 41.2%** (baseline 0 of 38, and 0 of 52 the phase before). Charging subset **7 of 12 = 58.3%** (baseline 0 of 33). Measured in the SIM domain (`b2.booked_at_sim > interrupted.released_at`). Every one of the 7 genuinely occupied its stall: held durations **12.2 / 15.0 / 27.5 / 36.0 / 52.5 / 72.0 / 79.3 sim-min** (median 36.0), clipped to the run window — 3 ended `done` / `window_elapsed_occupied`. None is a paper booking. The phase-11 failure mode "attempt fires, then finds no window" went **14 of 38 → 0 of 17**. |
| **V5 — tow retrieval fires end-to-end** | **PASS.** `vehicle.tow_retrieved_staged` fired **11 times**; it had never once fired. The paired sim-vs-real clock fix is proven at runtime. |
| **Approvals — absorbing state gone** | **PASS, in-run.** 48 `indepot_reassign` created, **48 decided, 0 pending, 0 expired** (baseline 7 created, 0 decided ever). Table-wide across all types and all runs: **0 pending**. No vehicle ends the run waiting on an unanswered question. |
| **Gate latency is non-zero (not cosmetic)** | **PASS with a caveat.** 44 of 48 went through the auto-gate with real latency: min 3.51, **median 8.28**, max 8.80 sim-min, computed purely in-domain (`payload.decision.decided_at_sim − payload.requested_at_sim`). Median lands on the dial `indepot_reassign_auto_decide_min = 8`. **Caveat:** 2 of 48 are *born-approved* at zero latency by the pre-existing `vehicle_fault_critical_immobilizing` safety carve-out — a deliberate safety path, not the decider. See the defect note below. |
| **Nemotron doctrine** | **HELD.** `copilot_seen=false`, `copilot_binding=false`, no `payload.copilot` on all 48. Nemotron was unreachable and the system still resolved every row, failing **closed** (decline = protect the atomic visit). Nemotron decided nothing. |
| **Re-routes still gated** | **HELD.** The readmit exclusion was narrowed, not removed: a pending `tech_greenlight`, or a pending `indepot_reassign` that is *not* a fault deferral, still bars readmission. Only the vehicle's own fault deferral is ignored. This run contained **0 genuine re-routes** (all 48 were `deferred_awaiting_tech` or `critical_immobilizing`), so nothing slipped through — but see the coverage gap below. |
| **V6 — protect list** | See below. Both hard-fail triggers pass. |

### Protect list, re-measured independently

**0 double-bookings** over 361 in-scope bookings (`held/active/done/interrupted`, self-joined
on `stall_id` with `&&` on `during`) — reproduced with my own query, not the harness's.
**0 starvation**: 7 of 112 arrivals returned under 85% SoC (min 79.9) and **none** ended the
run without a charge booking. Emission invariant **1.000** (17 interrupted bookings ↔ 17
`booking_interrupted` events). Phantoms **0 of 254**, reverse coverage **100%**,
inspection-zone parking **0.0%**, bay no-show **1 of 49** with grace verified still at 15.
Arrivals 112 vs baseline 117 (−4.3%) — a passed workload gate, not a collapse.

### The migration's own falsifier — RESOLVED, it did not trip

§10 V6 of `0002` said: if `gate_mode='deferred_awaiting_tech'` evictions start destroying
minutes, "the assumption is wrong and this migration is wrong." They went **0.00 → 245.37
minutes**. That looks damning and it is **not** a regression:

- **Phase 11 stamped a hardcoded zero.** In `phase11_eviction_evidence_424242`, all **45 of 45**
  deferred evictions carry `interrupted_with_min_remaining = 0.00` — while **38 of them** are
  `was_mid_service = true`. Forty-five mid-service evictions each destroying *exactly* zero
  minutes is not a measurement; it is a constant. §0002 line 1396 documents the constant and
  removes it.
- **The workload did not shift.** Mid-service deferred evictions: **38 in phase 11, 38 in this
  run.** Identical. What changed is that the number is now computed from the booking's real
  remaining window instead of being stamped `0`.
- **`declined` and `pending` really are indistinguishable to the eviction path.** The only
  status test in the resume branch is `a.status = 'approved'`; both `pending` and `declined`
  fail it identically and fall through to the same budget check. The migration's stated
  assumption **holds** on code reading.

**Therefore the two "regressed" protect figures are not comparable to their baselines.**
"Evictions cutting live work 20.3% → 31.8%" and "gate protection 90.0% → 84.4%" both have
numerators that depend on `interrupted_with_min_remaining > 0`, which phase 11 forced to zero
on the deferred path. Phase 11's true figures were worse, not better — reconstructed at
~1,359.78 destroyed minutes against **276.78** now. The honest read is a **−56.8% improvement
in minutes destroyed**, and the first trustworthy version of the rate. These two figures should
be **re-baselined off this run**, not treated as a regression.

### Open items — not blockers, but do not let them rot

1. **Zero-latency safety carve-out (2 of 48).** `vehicle_fault_critical_immobilizing` inserts
   its approval already `approved`, `decided_at = now()`. Defensible — a vehicle that cannot
   safely continue in place should not wait 8 minutes — but it stamps `decided_at` in the
   **REAL** domain while `payload.requested_at_sim` is **SIM**, and it writes no
   `payload.decision` object. Consequence: any latency computed as
   `decided_at − requested_at_sim` on those rows is meaningless. That is exactly where the
   capture harness's reported "min 0.01 / max 22.18 sim-min" came from — **both are
   clock-domain artifacts and should not be quoted.** Fix: stamp `p_sim_clock` and add the
   audit object, same shape as the auto-gate.
2. **Untested branches.** The decider's *approve* path (`zone_c_reopener_*`) and the narrowed
   readmit gate's *still-barred* path were both **unexercised** — this run produced no genuine
   re-route. Needs a scenario that raises an `indepot_reassign` for optimisation or congestion.
3. **cuOpt share is not certifiable from this run.** The harness's own supply-honesty invariant
   reads `cuopt_free_stall_undercount = 36 of 78` against a target of 0. Unrelated to this
   migration; do not quote 36.6%.

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
