# TWIN_CORE.md — OTTO-Twin Core Hardening

**Run 3, Phase C7 deliverable.** 2026-08-19.
Artifacts: `db/migrations/0045_twin_determinism_and_playback.sql` (NOT yet applied — post-merge),
`scenarios/` (the nine canonical failure files), `metrics/demo_run_6727b04e.json` (the
end-to-end demonstration), and the nine freshly captured twin functions in `db/fn_current/`.

The twin was formalized, not rebuilt: everything below wraps or extends machinery that already
existed — the cert harness (`ottoq_cert_arm_start/step/finish`, the isolated benchmark depot
`22222222…`, `ottoq_score_run`, `ottoq_certify_run`), the content-hashed decision snapshots, the
132-type event catalog, and the itinerary-leg substrate.

---

## 1. Determinism certification (C7.1) — run, verdict, root cause, fix

**Method.** Two arms on the benchmark depot through the *existing* cert harness, identical in
every input: seed **424242**, policy `otto_q`, ab_group `c7de7e00-…424242`, 0 faults, identical
step cadence (1+7+6+6), shielded from the metronome/governor via `run_by='cert_harness'` (the
harness's own exemption). Canonical comparison: per-tick structural digest over the content-hashed
decision snapshots (vehicle id/state/SoC/stall + stall occupancy + session kW), aligned by
**sim-minute offset** so wall-clock anchoring cannot fake a diff.

**Verdict: FAIL — the twin is not deterministic under fixed seed today.**

| | Arm A `6727b04e` | Arm B `a1e3bdb3` |
|---|---|---|
| dispatches / commands issued / refused | 120 / 447 / 159 | 107 / 563 / 350 |
| throughput/hr (ottoq_ab_runs) | 8.1 | 7.1 |
| peak kW | 662.1 | 587.5 |
| aligned ticks identical | **0 of 20** | |
| first divergence | tick 2 (sim-min 60): 68/100 vehicle SoCs differ, 1 state, 0 stalls | |

Both runs are archived and stamped (`ottoq_run_archives` + the 0044 reproducibility key); their
`ottoq_ab_runs` scores are the first rows of the new era. **A same-seed pair currently shows a
~14% throughput spread — until 0045 is applied and re-certified, no CRN comparison is fully
paired, and every A/B claim must carry that caveat.**

**Root cause (exact).** Eleven RNG-salt sites in nine twin functions salt
`ottoq_sim_seeded_random`/`hashtextextended` with the **absolute sim clock**
(`… || p_sim_clock_now::text`), and every run anchors its sim clock to real `now()` at start
(`ottoq_cert_arm_start`, `twin.ottoq_sim_start_run`) — so two same-seed runs draw disjoint
streams by construction. The seeded-random discipline was right; the **salt domain** was wrong.
Offenders (all captured verbatim in `db/fn_current/`): `advance_deployed_telemetry` (the dominant
SoC-drain divergence), `advance_grid`, `advance_site_energy`, `advance_weather_and_solar`,
`bay_fault_handler`, `bess_step`, `dispatch_vehicle`, `emit_arrival_webhook` (×2),
`vehicle_exception_handler`.

**The fix (0045 §1–§2).** `twin.ottoq_sim_clock_salt(run, clock)` = whole seconds since the
run's own `sim_clock_start` — identical across same-seed runs by construction, falling back to
the old absolute text only when the run row is unknown. All 11 sites patched; every patched body
is byte-identical to its capture except the salt expression.

**The standing property test (0045 §3).** `ottoq_twin_run_digest(run)` +
`ottoq_twin_determinism_verdict(run_a, run_b)`. Re-certification procedure (run after 0045 is
applied): two arms exactly as above → `SELECT * FROM ottoq_twin_determinism_verdict(a, b)` →
expect `deterministic = true`; if false, `first_divergence_sim_min` points at the next offender.
One caveat stated up front: `ottoq_sample_calibrated` and the variability-card dealers are
downstream of the same seeds and are *expected* to become deterministic with the salt fix, but
only the re-cert can prove it — this test exists precisely so that claim is never hand-waved.

**Re-certification #2 (post-0047, 2026-08-19; arms `7821c9a8` / `a59a1f08` / `44252690`).**
Three findings, each caught by the cert doing its job:
1. **Harness leak (procedural):** `ottoq_cert_arm_start` labels runs `run_by='benchmark'`, but the
   metronome's exemption list is `('production_live','cert_harness')` — so cron ticks leak into
   cert arms at wall-clock-random points, misaligning the pair (arms C/D: 23 vs 24 ticks for
   identical 20-step procedures). **Every paired cert must set `run_by='cert_harness'` right
   after arm_start** (re-added to the procedure below); this also retroactively explains part of
   re-cert #1's residual divergence (arm A carried one stray tick).
2. **Twin bug (0048 §1):** with the exemption fixed, arm E died mid-tick on
   `idx_stalls_one_vehicle_per_stall`: both bay-admit blocks in
   `twin.ottoq_sim_advance_service_flow` flip the vehicle to its in-bay state BEFORE vacating its
   old stall; `trg_reassignment_guard` protects in-bay states, silently vetoes the release, and
   the following place-statement kills the whole tick. This is the mechanism behind the open
   B1 double-stall finding. Fix: handoff first, state write second (0048, post-merge).
3. **More absolute-clock salts (0048 §2):** the wash/detail/maintenance duration-card scopes
   (`ottoq_twin_deal`) key on `p_sim_clock_now::text` — the 0045/0047 defect class. Fixed the
   same way.
Re-certification #3 runs after 0048 is applied: arms with `run_by='cert_harness'` +
`next_tick_due_at` shield, expecting `deterministic = true`.

**Re-certification #6 (post-0051, 2026-08-19; arms `eb5a5d37` / `1a576926`, both verified
tick_count=0 at start).** 0051 verified applied (both md5s match the file-applied scratch).
The gate-assignment permutation is GONE — the assigner fix holds. Verdict: **8 of 20 ticks
identical, first divergence sim-min 270** — exactly the tick the sim clock crosses 22:00
America/Chicago and the overnight recall window opens. The tick-9 frame diff is a **single
swap**: a different deployed vehicle was recalled in each run (one `arrived_at_gate` in A,
the other in B), everything else paired. The recall cursor itself is run-stable
(`ORDER BY current_soc, id` — verified); the offender is its **eligibility filter**:
`public.ottoq_is_overnight_holdout` hashes `p_run::text` — the per-run-random sim_run_id
(the 0047 salt class) — so two same-seed runs hold out different vehicles by construction,
at both call sites (`ottoq_plan_dispatch_tick` 'recall' and `ottoq_evaluate_return_need`
rung 6). A sweep found the same class in `public.ottoq_comms_emit_telemetry` (run uuid +
absolute clock on the dropout/latency draw; comms staleness feeds the rung-8 recall, so
decision-path-reachable). `ottoq_book_appointment`'s stall picks were audited in the same
pass and are already run-stable (every pick ends `…, s.id`). Fix: **0052** (post-merge) —
holdout keyed on the run's random_seed (unknown-run callers byte-identical), comms seed on
run seed + `ottoq_sim_clock_salt`; captures md5-verified, diff-proven to two changed sites.
Re-certification #7 runs after 0052 is applied, expecting `deterministic = true`.
*Standing harness caveat, made explicit:* `sim_clock_start` is real `now()` at arm, so
hour-of-day and calendar-date expressions (deploy fraction by hour, night waves, wash-day
rotation, the holdout date term) agree across a cert pair only because arms start minutes
apart. **Cert arms must not straddle an hour boundary, midnight UTC, or 05:00
America/Chicago**; pinning `sim_clock_start` to a canonical anchor in the cert harness is
the recorded follow-up that would retire this caveat class entirely.

**Re-certification #5 (post-0050, 2026-08-19; arms `8e8da5c5` / `0d920ed3`, both verified
tick_count=0 at start).** 0050 verified applied (all five md5s match the file-applied scratch).
The five patched advance functions are now deterministic — no crashes, 20v20 aligned, and the
in-bay service flow no longer permutes. Verdict: **9 of 20 ticks identical, first divergence
sim-min 300**, and the tick-10 frame diff is again a pure **vehicle↔stall matching permutation**,
now isolated to the **gate-admission assigner**: same states, same SoCs, same stall set in use,
different pairing. Root cause, two residual instances of already-fixed classes in
`twin.ottoq_sim_auto_charge_assign_tick`: (1) its stall-shuffle seed hashes the **absolute sim
clock** (`p_sim_clock_now::text` — the 0045 salt-domain class), so the seeded stall pick differs
across same-seed runs; (2) its vehicle cursor is `ORDER BY current_soc` with **no tiebreak** —
integer-SoC ties (measured: the 48/48 and 65/65 pairs at tick 10 are exactly the swapped
vehicles) fall back to heap order (the 0050 class). A sweep found the same absolute-clock salt
in `twin.ottoq_sim_auto_dispatch_tick`'s dispatch-ranking seed. Fix: **0051** (post-merge) —
both seeds re-salted via `ottoq_sim_clock_salt`, plus the run-stable `id` tiebreak; captures
md5-verified byte-exact against production, diff-proven to exactly three changed lines.
Re-certification #6 runs after 0051 is applied, expecting `deterministic = true`.

**Re-certification #4 (post-0049, 2026-08-19; arms `a4ce46d4` / `523f770e`, both verified
tick_count=0 at start — the airtight-start procedure below).** 0049 verified applied; **no tick
crashed** — the 0048/0049 state-machine fixes hold end-to-end. Verdict: **11 of 20 ticks
identical, first divergence sim-min 360, and at that tick every one of the 100 vehicle SoCs was
paired** — all seeded randomness is now deterministic. The residual diff is a pure
**stall-assignment permutation**: the same stalls paired to a vehicle queue shifted by one.
Root cause: **eleven per-tick processing cursors across five twin functions iterate with no
ORDER BY** — physical heap order, which drifts between runs, decided who claimed a shared
resource first. Fix: **0050** (post-merge) — run-stable ORDER BY (vehicle.id / stall.id; never
per-run-random or real-clock keys) on all eleven; diff-proven additive-only.
*Harness lessons now standing procedure:* (a) relabel `run_by='cert_harness'` immediately after
arm_start **and verify `tick_count = 0` before the first step** — a metronome tick can land in
even a 2-second window (it contaminated the first arm-B attempt, `94982168`, discarded); (b) a
CTE combining arm_start with the relabel does NOT work (the outer UPDATE cannot see rows the
CTE's function inserted in the same statement).

**Re-certification #3 (post-0048, 2026-08-19; arm `5822181f`, correct `cert_harness` labeling).**
0048 verified applied (md5 match). The 0048 reorder works — and the cert then surfaced the next
gate mismatch, one layer deeper: a tick died on the **vehicle-side arm interlock** even though
the admit path had asked `twin.ottoq_arm_refuse_move` first. The mirror and the backstop evaluate
the tether in **two different clock domains, exactly one tick apart**: refuse_move used the
caller's in-flight tick clock (persisted clock + 30 min), the interlock trigger uses the run's
persisted `sim_clock_current` (advanced only at tick end). A demate expiring exactly on the tick
boundary (vehicle `02f1a60b`, until = the new tick's own timestamp) was therefore "movable" to
the mirror and "held" by the backstop. Fix: **0049** (post-merge) — refuse_move sources its
clock from the guard's exact expression, making mirror and backstop provably consistent for
every caller; the boundary case defers one tick. Re-certification #4 runs after 0049 is applied.

**Re-certification #1 (post-0045, 2026-08-19; arms `2ab6ab11` / `e12faa29`, seed 424242).**
The cert worked exactly as designed: **10 of 20 aligned ticks identical (was 0 of 20)**, and at
the first divergence (sim-min 330) **all 100 vehicle SoCs were paired** — the 0045 salt fix
holds across every patched stream. The residual divergence is a *single vehicle* (charging in
arm A, still at the gate in arm B): charge-session **rate noise** shifted one session's
completion tick, which shifted a stall hand-off. Root cause: two salt sites the 0045 census
missed — `twin.ottoq_sim_advance_charge_sessions` (×2) and `twin.ottoq_sim_start_charge_session`
(×2) salt their noise with the per-run-random **session UUID** and the **absolute clock**.
Fix: **0047** (committed, NOT yet applied — post-merge), same salt-domain treatment via
`ottoq_sim_clock_salt` on (vehicle, run-relative offsets). Re-certification #2 runs after 0047
is applied, expecting `deterministic = true`.

**Bonus finding from the same runs:** `ottoq_certify_run` on arm A: `certified = false` —
2 of 21 frames show a stall held by two vehicles (`over_stall_ticks=2`). The frame-level B1
invariant is violated under the batch cuOpt enactment era; needs its own root-cause (candidate:
frame capture mid-enactment vs. the EXCLUDE calendar, which cannot itself double-book).

## 2. What 0045 changes when applied (post-merge)

| § | Change | Risk |
|---|---|---|
| 1–2 | salt-domain fix, 9 functions | behavior of *individual draws* changes once (new stream); distributions unchanged; nothing reads the old salts |
| 3 | digest + verdict fns | additive, read-only |
| 4 | 5 canonical event types registered | additive catalog rows |
| 5 | `ottoq_twin_playback_timeline` view | additive, read-only |
| 6 | **decision surfaced for merge review:** `ottoq_ab_runs` reclassified engine → evidence (purge stops deleting A/B scores; the C4 mystery of the empty table) | A/B rows now outlive runs, as `ottoq_run_archives` already does |

## 3. Canonical event vocabulary (C7.2) — the audit

Catalog holds 132 types. Mapping to the canonical thirteen:

| Canonical | Exists today as | 0045 action |
|---|---|---|
| arrival | `twin.vehicle_arrived` (+ `ottoq.arrival_forecast`, `fleet.arrival_delayed`) | none (mapped) |
| op_start / op_end | `twin.service_started`, `charge.session_started/completed`, `task.state_changed` | none (mapped) |
| fault | `charge.session_faulted`, `charge.fault_injected`, `twin.bay_fault_reroute` | none (mapped) |
| point_blocked / point_cleared | `stall.state_changed` (+ bay_fault equipment_config lifecycle) | none (mapped) |
| power_loss / power_restored | `twin.grid_brownout`, `twin.grid_voltage_sag`, `twin.grid_frequency_excursion` | none (mapped) |
| **move_start / move_end** | — | **registered (0045)**; emitters follow with the playback adoption |
| **recall_issued / recall_refused** | — (`early_recall_log` holds the concept) | **registered (0045)**; C9 emits |
| **touch_event** | — (KPI-4 currently enumerates human actor types) | **registered (0045)**; supersedes the enumeration once emitters adopt |

## 4. Failure-scenario library (C7.3)

`scenarios/` — the canonical nine, each a committed data file with an honest `status`:
**executable today** (blocked_point, overstay, immobile_asset, mid_session_charger_fault — each
names its live injector: bay-fault policy knobs, eta_delay variability, breakdown-rate profile,
cert-arm `fault_chargers` / `inject_fault`), **partial** (zone_power_loss — site-wide cap
injectors exist, per-zone does not), and **provisional** with the unlocking work named
(human_path_crossing → twin path-resource model; swap_dock_jam → yard-logistics pack;
tug_unavailable → vertiport paper pack; work_side_recall_refusal → C9).

## 5. Playback timeline (C7.4)

`ottoq_twin_playback_timeline` (0045 §5): `(entity_id, event_type, t_start, t_end, from_pose,
to_pose)` per itinerary leg, poses from stall geometry, `playback_schema_version = 'v1'`,
security-invoker view, pure SQL. Zero Isaac imports in the path — this is the seam the in-house
3D layer renders from and through which Track B can return (CLAUDE.md 2.8). Verified rendering
rows on the scratch instance.

## 6. Discipline check (C7.5)

Nothing added carries a new run-scoped column (views and the salt helper are stateless; the five
event types are catalog rows). `data_source` co-existence untouched. The one retention change
(§6, ab_runs) is a *surfaced decision*, not a silent drift — merging 0045 is deciding it.

## 7. The demonstration run, end-to-end into the C6 CLI (the deliverable's spine)

Run **`6727b04e-b890-45e3-87c1-ac4c558e2a81`** (benchmark depot, `normal_day`, seed 424242,
policy `otto_q`, 690 sim-minutes — over the 139-minute credibility floor): driven by the cert
harness → scored into `ottoq_ab_runs` → archived (`ottoq_archive_run`) → stamped with the 0044
reproducibility key → **`ottoq_kpi_five(run)` returns all five canonical KPIs** (committed
verbatim in `metrics/demo_run_6727b04e.json`, with the safety-cert result and the determinism
verdict alongside). Headline: peak_site_kw 662.1 · turns/point/day 1.84–1.92 ·
touch_events_per_turn 0.059 · p95_time_to_service 0 min · asset-hours 773.4+27.6.
Every number above traces to that run ID.
