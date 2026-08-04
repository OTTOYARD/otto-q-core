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
| 2026-08-04 | `db/migrations/0003_bay_work_recovery.sql` (ledger version **20260804183836**, name `bay_work_recovery`) | **Gave bay work the second witness charging already had.** Replaced `public.ottoq_vehicle_needs_card` (new `owed` CTE reads the outstanding-work LEDGER, not the cadence clock; three new appended columns `owed_bay_svcs` / `owed_bay_min` / `rebook_owed`; `must_do_now` becomes cadence-due UNION ledger-owed, `deferrable_now` narrowed so the two can never contradict). Replaced `public.ottoq_decide_tick` (section 4b only: charge firewall narrowed by one three-clause exception, resumed work floored at urgency `due`, per-lane per-tick resumption budget `bay_resume_share_max`, and `is_resume` / `eff_urgency_rank` / `fresh_waiting_lane` / `resume_cap_lane` / `resumed_bay_work` stamped so recovery is countable straight off `ottoq_decisions`). Replaced `public.ottoq_indepot_reassignment_guard` (P1a/P1b: all **three** born-approved fast paths now stamp `decided_at` in the SIM domain and carry the same `payload.decision` audit object the auto-gate writes). Added view `public.ottoq_indepot_gate_latency` (P1b: the one canonical, never-mixed-domain latency measurement). One new policy dial catalogued (`bay_resume_share_max`, default 0.5). P1(c) eviction re-baseline recorded in-file as §7. | **Bay work recovered 0 of 5 interrupted jobs** (0 of 4 excluding the one genuine no-space refusal) while charging recovered 7 of 12. Root cause: `ottoq_decide_tick` (4b) picks bay candidates only from `must_do_now`, which was built from the CADENCE PROFILE alone — and the twin resets that profile when it credits a job "completed", in one measured case crediting a 35-minute service for 27 seconds of work. Charging recovers because `vehicles.current_soc` is a physical fact the engine re-reads every tick; bay work had no equivalent second witness, so the outstanding-work ledger said the work was owed while the cadence clock said the car was fine. Vehicle 5cee8fb3 logged 33 consecutive refusals to redeploy over 30 sim-min and was never once considered for a bay. | Claude, MCP `apply_migration` (name `bay_work_recovery`). **The ledger's stored statement is the committed file byte-for-byte** — 165,517 chars / 166,702 bytes / md5 `994a98708a25ad1c6a00e907f1c85ad6`, equal to the md5 of the file as committed at `a06cf4f` (header `PENDING`, trailing newline included). ⚠️ **METHOD NOTE, and it differs from 0002.** The file is 166 KB, too large for one MCP tool-call payload, so it was transferred in 10 run-length-encoded ASCII-safe chunks into `public.mig0003_transfer`, each chunk md5-verified on arrival, then decoded into `public.mig0003_decoded` and verified against the file's own md5 **before anything was executed**. `apply_migration` then ran a small guarded executor that re-checks that md5 and replays the file's 11 top-level statements (boundaries from a dollar-quote/string/comment-aware tokenizer, round-trip verified). The ledger row's `statements` was then set to the file's exact bytes, because that is the SQL that was actually applied to the brain; the executor shim is preserved verbatim in `public.mig0003_decoded` id=2. ⚠️ Also note **0002's ledger md5 is the file-with-`PENDING` *minus its trailing newline*** (100,846 chars, `b2f860…`) — confirmed by reconstruction. 0003's is the full file including the newline. The two are not computed the same way; do not compare them as if they were. | **Partly — V1/V2/V3 pass now; V4–V7 need a bounded run and are NOT yet done.** All guards matched live before apply: `ottoq_decide_tick` = `d279aa48…`, view `ottoq_vehicle_needs_card` = `4f42015a…` (both from `db/baseline/`), and `ottoq_indepot_reassignment_guard` against 0002's own post-snapshot — pre-snapshots recorded under label `0003_bay_work_recovery_pre`, post under `0003_bay_work_recovery_post`. **V1** ledger detector live on 116 vehicles, `charge` leaked into `owed_bay_svcs` **0 times** (0 owed at rest — no run active, so the detector is proven sane, not yet proven to fire). **V2** `must_do_now` ∩ `deferrable_now` contradictions **0**. **V3** gate latency now measurable in ONE domain: sim **46 rows, min 3.51 / avg 8.19 / max 8.80 sim-min** (matches the dial `indepot_reassign_auto_decide_min=8`); real 58 legacy rows; `unmeasurable` **2** — exactly the two pre-0003 born-approved rows the migration predicted would land there. The bogus "min 0.01 / max 22.18" mixed-domain range is gone by construction. **Routine counts unchanged and verified live: public 337, ottoq 48, twin 71** — this migration adds ZERO routines (two `CREATE OR REPLACE` functions, one replaced view, one new view), so Section D needed no edit. `scripts/check-drift.sql` run live after apply: **VERDICT CLEAN**, Sections A/B/C/D all OK. **NOT yet verified — needs the bounded run (≥139 sim-min, captured after STOP, SIM domain, per arriving vehicle):** V4 (the P0 number — bay work actually re-booked into a bay it holds), V5 (fresh arrivals not starved), V6 (charge path flat), V7 (0002 protect list intact). V8 (the decider's approve branch / still-barred readmit branch) remains an open coverage gap. |
| 2026-08-04 | `db/migrations/0002_approval_gate_decider.sql` (ledger version **20260804140958**, name `approval_gate_decider`) | Made the in-depot reassignment gate **answer** instead of absorb. Added `public.ottoq_decide_indepot_approvals` (OTTO-Q's own policy decider: 8 sim-min latency, 30 sim-min hard expiry backstop that runs even when the kill switch is off). Replaced 5 existing functions: `public.ottoq_indepot_reassignment_guard` (stamps a sim-domain `requested_at_sim`/`decide_after_sim`/`expires_at_sim` trio + `clock_domain` tag into the payload, real columns untouched), `twin.ottoq_opportunistic_scan` (type-filtered to the twin's own approvals so a doctrine gate is never settled by a seeded coin flip), `ottoq.ottoq_readmit_reopened_needs` and `ottoq.ottoq_readmit_resumed_visits` (approval exclusion **narrowed**, not removed — the gate still blocks genuine changes of plan and is ignored only for the vehicle's own fault deferral; emitted doctrine string corrected to match the code), and `twin.ottoq_sim_vehicle_exception_handler` (technician flip now resolves the ledger row in the same transaction; `auto_staged` path resolved; **tow-retrieval clock domain fixed**; named top-level safety net added). 3 new policy dials catalogued. | `ottoq_ops_approvals` was an **absorbing state** for `indepot_reassign`: 55 pending rows, none ever decided, none able to expire. Root cause was a clock-domain mismatch — the guard stamped `decide_after`/`expires_at` with `now()` (REAL) while the only decider compared them to the SIM clock, 325 min apart in the measured run, so the rows were neither decidable nor expirable. Those rows then barred **27 of the 29 vehicles (93.1%)** holding cut-short work from readmission, which is why cut-short work was never re-booked: 0 of 38, then 0 of 52, three phases running. Paired defect: tow retrieval compared REAL `last_state_change` to the SIM clock and fired **zero** times, leaving broken vehicles unable to leave. | Claude, MCP `apply_migration` (name `approval_gate_decider`). **Applied byte-for-byte from the committed file** — the ledger's stored statement md5 `b2f860822b7df8037967962def5ed03d` equals the md5 of the file's exact contents, so the database and the repo hold identical SQL. | **Yes — the absorbing state is gone, measured, not asserted.** All 5 md5 guards matched live before apply. One call to the new decider resolved **55 of 55** stranded rows (`rows_resolved=55`); every one carries an audited `payload.decision`. **V1**: `indepot_reassign` now 55 `declined` + 3 `approved`, **0 pending**, 55/55 with a decider stamp and an audited decision, all with reason `atomic_visit_protected_bounded_defer_budget_governs` (the deferral verdict is DECLINED by design, so the eviction machinery and the phase-11 baseline are untouched). **V2** stuck-beyond-ceiling = **0**. **V3** technician-approved contradictions = **0**. Nemotron doctrine held: `copilot_recommendation='unavailable'`, `copilot_binding=false` on all 55 — it was unreachable and the system still decided, conservatively. **Readmission reachability on the real population** (denominator: the 29 vehicles holding an open reopened need with ≥1 atom not done/cancelled), OLD rule vs NEW rule evaluated against the preserved pre-fix approval states: barred **27 → 0**, reachable **2 → 29** (reproduces the diagnosed 93.1% exactly). **Tow clock fix**, evaluated with the real clocks of run `73f53ed5` (real ran **325.3 min ahead** of sim): old predicate `false` (never fires — matches the observed zero retrievals), new predicate `true` in both the sim and the legacy-real branch. `scripts/check-drift.sql` run live after apply: **VERDICT CLEAN**, Sections A/B/C/D all OK. Cron 10 and 12 left **active throughout** (no pause was needed) — 4/4 and 7/7 runs succeeded post-migration, zero failures. **NOT yet verified — needs the bounded run:** V4 (cut-short work actually re-booked into a space), V5 (tow retrieval firing end-to-end), V6 (phase-11 baseline re-cert). Those need ≥139 sim-min captured after the run is stopped, per the file's own §10. |
| 2026-08-04 | `db/baseline/` (snapshot, not a migration) | Captured the whole live brain into files for the first time: 336 `public` + 48 `ottoq` + 71 `twin` user-defined routines (455 total), tables, RLS policies, cron jobs, and the 27 deployed edge functions. Established `db/migrations/`, `scripts/check-drift.sql`, `scripts/gen-drift-sql.sh`, `scripts/APPLYING.md`, and this log. | The brain existed only inside Supabase with no source repo. The live ledger held **621 applied migrations**; the founder's working folder held 80 migration files and **none of the 80 appeared in the live ledger**. There was nothing to review, revert, or diff. Baseline = the line from which "if it isn't a committed file, it didn't happen" starts being true. | Claude (read-only session) | **Yes.** Counts re-verified live against `pg_proc`/`pg_depend` on 2026-08-04: public 336, ottoq 48, twin 71, ledger 621 rows, 27 edge functions all ACTIVE — all five match the export exactly, zero drift. `scripts/check-drift.sql` run live the same day: **VERDICT CLEAN**, Sections A/B/C/D all OK. Alarm proven to fire via a negative test (moved baseline cut + wrong name + phantom file → 2 CRITICAL drift rows, 1 CRITICAL name mismatch, 1 WARN orphan, 1 INVESTIGATE count diff). |

---

## Smoke test for 0003 — a cut-short BAY job took a bay, for the first time

Targeted, bounded, and **not** a substitute for the V4–V7 certification run (still owed).
Run `0003bee5-0000-4000-8000-000000000003`, depot `1111…1111`, sim clock 16:00:00.
Cron 10 and 12 were paused for the window and **restored and verified afterwards**
(both `active=true`; 16 subsequent runs of job 12 and 8 of job 10, **all `succeeded`,
zero failures**). Evidence preserved in `public.mig0003_smoke_receipt_decisions` /
`…_bookings` — the `ottoq_*` originals are purged when the next run starts.

**The scenario reproduces the exact deadlock, not a convenient one.** Vehicle
`00cc3d0a` was given a detail-bay job that had been booked, started at 15:40 and cut
short at 15:41:25 (`cut_short_at` + `reopened_at` on the atom, `meta->'reopen'` on the
row) — and its cadence profile was then reset to *spotless*, which is what the twin
does when it credits an interrupted job as complete. Battery was set to 99% so the
charge path was never involved: this tests the bay lane and nothing else.

| Check | Result |
|---|---|
| **The card, pre-0003 behaviour** | `cabin_urgency = 'ok'`, `overall_urgency = 'ok'` — the cadence clock says the car is clean. Before this migration `must_do_now` would have been empty and the bay loop would never have looked at it again. |
| **The card, with the ledger detector** | `must_do_now = {interior_deep_clean}`, `owed_bay_svcs = {interior_deep_clean}`, `owed_bay_min = 25`, `rebook_owed = true`, `must_do_legs = {detail}`. **The second witness fires while the cadence clock still says "ok" — that is the whole fix, observed directly.** |
| **The decision** | one `decide_tick` call: 2 built, 2 enacted, **0 errored**. The bay row: `resolved_action_context='stall_assignment'`, `outcome='enacted'`, `source='needs_card'`, `need='interior_deep_clean'`, **`resumed_bay_work=true`**, `resumed_need='interior_deep_clean'`, `bay_booked=true`, `is_resume=true`, **`eff_urgency_rank=3`** (the `due` floor doing its job, against a cadence urgency of `ok`), `fresh_waiting_lane=0`, `resume_cap_lane=1` (budget correctly did not bite with no fresh competition). |
| **The bay it HELD** | a real `wash_bay` stall, `purpose='detail'`, `state='held'`, window **16:00 → 16:25 = 25.00 min** (matching the 25 owed minutes), `booked_at_sim` in the SIM domain, `source='needs_card'`, `need_code='interior_deep_clean'`. Not a paper booking: `stalls.current_vehicle_id` = the vehicle, `vehicles.current_stall_id` = the stall, `current_state='in_detail_bay'`. |
| **Cleanup** | vehicle released through the engine's own `ottoq_release_vacated_spaces`; 0 bookings left open, 0 bays left occupied, 0 runs left running, synthetic ledger row deleted. All four replaced objects still md5-identical to the `0003_bay_work_recovery_post` snapshot, so the smoke test changed no code. |

**What this does and does not prove.** It proves the mechanism end to end — ledger
detector → card → `decide_tick` (4b) → enacted assignment → a booking that holds a real
bay — on the precise failure shape that measured 0-of-5. It does **not** yet give the
P0 rate under load, nor V5 (fresh arrivals not starved), V6 (charge path flat) or V7
(0002 protect list intact). Those still need the ≥139 sim-min bounded run.

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

## Certification run for 0003 — the P0 headline is REFUTED, the two P1 fixes are PROVEN

Run `fc1ad933-c5c2-44e1-9cd1-e724a81d3d3e` (seq 908), `busy_day`, seed 424242, playback `live`,
`speed_x` 3.0, `run_by` operator_demo, depot `1111…1111`. Sim window 13:48:00 → 16:48:10.352 =
**180.173 sim-min** (protocol floor 139 cleared by 41.2), 781 ticks, 60.01 real-min, **109 arrivals**
(baseline 112, −2.7%). Auto-stopped by the cron-12 metronome at its 60-real-minute ceiling; cron 12
and 10 were never paused. **All numbers captured after `status='completed'`, SIM domain only.**
Evidence preserved out of the `ottoq_*` namespace: `phase14_bookings_424242` (736),
`phase14_decisions_424242` (10,738), `phase14_dispatches_424242` (112), `phase14_visit_needs_424242`
(110), `phase14_approvals_424242` (63), `phase14_gate_latency_424242` (51), `phase14_runrow_424242`,
and the full narrative in `phase14_cert_424242` (20 rows).

### V4 — ⭐ THE P0 NUMBER: **BAY WORK RECOVERED 0 OF 2. THE HEADLINE DOES NOT HOLD.**

2 bay bookings reached `state='interrupted'` (detail ×2); **0** received a replacement — unchanged
from the baseline's 0 of 4. The migration's own instrument is unambiguous: across 10,738 decisions
and 781 ticks, **`resume_candidates_seen = 0` and `bay_work_resumed = 0`. The new code path never
executed once.**

**Root cause, isolated to two independent gates — both measured, not assumed:**

1. **The `must_do` clause in the §3 ledger CTE.** Of 107 open/in-progress `ottoq_visit_needs` rows,
   **32** carry interruption evidence, **14** of those have a bay-lane atom, **13** still have that
   atom open — but only **1** has `must_do = true`. The owed bay atoms are `mechanical_pm` ×8,
   `interior_deep_clean` ×3, `sensor_calibration` ×2, `cosmetic_repair` ×1 — all `must_do = false`;
   the lone `fault_repair` is the only one that qualifies. `AND COALESCE((a.value->>'must_do')::boolean,
   false)` collapses the detector **14 → 1, a 93% loss.** The file states this as doctrine
   ("deferrable work does not get to jump a scarce bay"); the measured consequence is that the P0 fix
   is inert for 12 of 13 real cases.
2. **The `staged_awaiting_service` gate in `ottoq_decide_tick` (4b).** The one surviving candidate
   (`96b10b07`, `fault_repair`, `must_do=true`, `owed_bay_min` 114) spent the rest of the run in
   `charging_l2` and never entered `staged_awaiting_service`, so the bay cursor never saw it. The
   migration's own charge carve-out could not rescue it either — that exception requires **no free
   charger**, and this vehicle was *on* one.

**Honest denominator:** of the 2 bay interruptions, `b2222222` released as
`vehicle_fault_eviction_deferred_resumed` and has **zero** open needs rows — its work resumed in
place, nothing was owed. The genuinely-lost bay denominator is therefore **1**, and recovery is 0 of 1.

**The numbers were not flattered by shrinking the denominator.** Bay jobs *started* = 46 bookings /
109 arrivals = **0.422 per arrival** vs the baseline's 49 / 112 = **0.4375**. Flat. Bay work was
attempted at the same rate; the smaller interruption count (2 vs 4) is workload variance.

### V5 / V6 — fresh work not starved; charge path not moved by this migration

`fresh_displaced_by_resumed = 0`, but **trivially** — no resumed row was ever enacted, so the
anti-starvation budget (`bay_resume_share_max`, resolved live at 0.5) is **untested at runtime.**
13 fresh bay admissions enacted, 5 refused on genuine scarcity.

Charging recovery is **not re-certified and not a regression**: 7 of 16 same-purpose = 43.8% (baseline
7 of 12 = 58.3%); on a same-class basis (dcfc↔l2 both count) 10 of 16 = 62.5% (baseline 8 of 12 =
66.7%). The **numerator is identical (7)**; the denominator grew. Not attributable to 0003 — a
line-level diff of the pre/post `ottoq_decide_tick` snapshots shows **all 22 removed lines lie inside
section 4b**, with nothing removed from the charge path, cuOpt, or Gate B, and
`ottoq.ottoq_enact_space_assignment` still hard-refuses `dcfc`/`l2`. All 7 replacements genuinely
**held** their stall: 2.21 / 9.91 / 24.33 / 34.54 / 35.79 / 49.40 / 56.87 sim-min, median 34.54.
**There was not one bay replacement to trace.**

### P1(a) and P1(b) — both CONFIRMED FIXED at runtime

- **P1(a)** 4 born-approved fast-path rows, **all** `clock_domain='sim'`, **all**
  `has_audit_object=true`, reason `zone_c_reopener_vehicle_fault_service_cannot_continue_in_place`,
  `decided_at_sim == requested_at_sim`, latency 0.00. Baseline had 2 such rows with no audit object
  and a REAL `decided_at`.
- **P1(b)** all **49 decided** gate rows are `clock_domain='sim'`. Declines (41) min 8.00 / **median
  8.21** / max 9.03 sim-min, landing on the dial `indepot_reassign_auto_decide_min = 8`. The bogus
  "0.01 – 22.18" range is impossible by construction. The 2 `unmeasurable` rows are `pending`, aged
  **7.18 and 5.13 sim-min** at the stop — *below* the 8-min dial, i.e. in flight at truncation, not
  stranded.

### P1(c) — §7's arithmetic verified, and a claimed correction to it REFUTED

Independent reconstruction from `phase11_eviction_evidence_424242`: 45 deferred resumes, **24** closed
a booking, 24 live at close, raw 1,631.48, **net 1,359.77** — matching §7's recorded 1,359.78 to the
decimal. A figure of ~815.77 does **not** reproduce. Verified live: the two twin handlers carry 4
emission sites and **zero** hardcoded `interrupted_with_min_remaining = 0`.

### Protect list

**HELD** — emission invariant 19/19/19 = 1.000 · real double-bookings **0 of 325** in scope (partly
structural: `ottoq_stall_bookings_no_overlap_v3` enforces exactly this scope) · inspection-zone
parking 0 · starvation 0 (on a denominator of **one** low-SoC arrival) · churn 5 (baseline 19).

**MOVED AGAINST, recorded rather than buried, and not attributable to a migration that never fired** —
bay no-show 5 of 46 = 10.9% (baseline 1 of 49 = 2.0%; grace verified unchanged at 15; all 5 are
planner reservations with `source IS NULL`, not enacted admissions) · evictions cutting live work
19 of 43 = 44.2% (baseline 31.8%) · minutes destroyed 560.60 (baseline 276.78) · gate protection
71 of 90 = 78.9% (baseline 84.4%) · enacted ex-inspect per arrival 1.183 (baseline 1.295) · work done
per arrival 2.807 (baseline 3.071).

### Verdict — **do not revert, do not advertise the P0 as fixed**

No hard-fail occurred: no starvation, no double-booking, no fresh arrival displaced by resumed work.
The change is additive and **inert**: it removed nothing from the charge path, left all four guarded
objects md5-identical to the `0003_bay_work_recovery_post` snapshot, raised no engine warning
(`decide_tick` never failed; the only log warnings are the pre-existing
`ottoq_world_advance: no running production run`), and `check-drift.sql` re-run live after the run
reports **CLEAN** with routine counts public 337 / ottoq 48 / twin 71 all matching. Reverting would
discard two runtime-proven fixes and buy nothing. **Migration 0004 should relax exactly the two gates
named in V4 and re-certify.**

---

## Objects created outside a migration — declared, not hidden

The drift check counts routines, so a plain table created by hand is invisible to
it. Anything created outside the migration path gets declared here instead.

| Date | Object | Why it exists | Safe to drop? |
|---|---|---|---|
| 2026-08-04 | `public.pre0002_approvals_evidence` (58 rows) | Snapshot of `ottoq_ops_approvals` for `approval_type='indepot_reassign'` taken **immediately before** migration 0002's decider was first run, so the pre-fix state of the 55 stranded rows survives. It is what the 27→0 readmission-reachability before/after was measured against. Deliberately **not** `ottoq`-prefixed, so starting a run cannot purge it. | Yes, once the ≥139 sim-min certification run for V4–V6 is done and its results are logged. It holds no brain logic — it is evidence. |
| 2026-08-04 | `public.phase14_*_424242` — `bookings_424242` (736), `decisions_424242` (10,738), `dispatches_424242` (112), `visit_needs_424242` (110), `approvals_424242` (63), `gate_latency_424242` (51), `runrow_424242` (1), `cert_424242` (20) | Raw evidence for the 0003 certification run `fc1ad933` (180.173 sim-min, 109 arrivals), preserved **immediately after** `status='completed'` and before any subsequent run start, since `ottoq_start_demo_run` purges the prior run. `phase14_cert_424242` carries the full narrative including the two-gate root cause of the 0-of-2 bay recovery. Deliberately **not** `ottoq`-prefixed. | Not until migration 0004 has re-certified bay recovery — this is the only surviving record of *why* 0003 never fired. |

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
