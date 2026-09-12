# SOLVER_STATE.md — The Decision Architecture, As It Actually Is

**Run 2, Phase C4 deliverable.** 2026-08-19. Every number below was read from the live
`gxdrcyphqjzjsuhxuqtg` ledgers this day, or from the dated evidence tables named inline.
Companions: `db/fn_current/` (the live decide-path function set, captured verbatim with md5s —
16 policy-named backups indexed in §5) and `solvers/cpsat/` (the step-4 prototype).

---

## 1. cuOpt, ledger-backed (the C4 step-1 quantification)

**The retention context first, because it changes what the ledger can say.**
`cuopt_invocation_log.sim_run_id` is engine-class in the run-scope registry: rows die with their
runs. The live table therefore holds only the current-window record; the durable historical record
lives in the dated evidence tables (`cuopt_enactment_proof_2026_08_01`,
`cuopt_supply_proof_2026_08_02`, `cuopt_supply_ledger_2026_08_03`, `p7_cuopt_supply_proof_2026_08_03`)
— which is working exactly as the registry design intends, but means "255 invocations" is a
window count, not a lifetime count.

**The retained window (measured 2026-08-19; all rows 2026-08-18 except two 08-02 stragglers):**

| Ledger fact | Count |
|---|---|
| Invocations logged, total | **255** |
| `sql_gate` abstentions — `sql_gate_no_candidates` | **249** |
| `sql_gate` passes (posted to the edge fn; 28 candidate-vehicles pinned) | 2 |
| `edge` abstentions — `no_candidates_in_instance` (re-validation emptied it) | 2 |
| `no_running_run` / `missing_sim_run_id` | 1 / 1 |
| NVIDIA HTTP calls with a logged `http_status` | **0** |
| `proposals_out` recorded | **0** |
| Deferral ledger (`ottoq_cuopt_deferrals`) | 14 rows, all `state='clear'` (armed → cleanly released; no starvation) |
| `ottoq_decisions` in window with `l2_engine='cuopt'` | **0** (engines: deterministic_v1 1,045 · needs_card 92 · nemotron 87 · inspect_seam 28 · others 10) |

**The dated evidence (2026-08-01 → 08-03), the durable record:**

| Evidence fact | Count |
|---|---|
| NVIDIA HTTP receipts (`kind='nvidia_http_receipt'`, 08-01 proof table) | **51** |
| cuOpt proposals captured (`kind='proposal'`) | **21** |
| cuOpt-enacted decisions proofed (`kind='decision'`, `l2_engine='cuopt'`, `outcome_status='enacted'`, full 52-rule shield trace attached) | **2** |
| Supply-side ledger rows preserved (08-02/08-03 stall-supply forensics) | 3,022 + 1,514 + 7 |

The supply forensics are the story behind the numbers: the 2026-08-03 root cause (documented in
`edge-functions/ottoq-cuopt-propose/index.ts` v25) found `ottoq_ocpp_chargers.station_state`
misused as an occupancy mirror, collapsing perceived supply to 0 free stalls on 11 gate-passed
calls while the booking ledger showed avg 22.64 of 45 charge stalls free. The fix landed in v25;
migration `0032` then converted enactment to an atomic pre-cursor batch
(`ottoq_enact_cuopt_batch`, live) because sequential enactment let the greedy path claim stalls
first (measured: proposals produced, 0 enacted).

**The honest sentence the deck may use (both directions, per the standing rule):**

> *cuOpt is wired into the live tick as a gated proposer with a one-tick right of first refusal,
> and every invocation is ledgered: in the current retained window it was invoked 255 times and
> abstained 253 — 249 of those because the SQL gate found no eligible vehicle — producing no
> proposals; in the preserved 2026-08-01→03 evidence it made 51 receipted NVIDIA calls, returned
> 21 proposals, and 2 of them were enacted through the full 52-rule shield. No measured
> throughput delta exists yet, because `ottoq_ab_runs` — the CRN A/B substrate built to measure
> exactly that — currently holds zero rows (§4).*

Any claim stronger than that sentence, in either direction, is not ledger-backed today.


### 1a. Re-measured 2026-09-01 (live ledger, 7:20 PM CT) — supersedes the numbers above for any new claim

The §1 table was read on 2026-08-19 and says "255 invocations". That was a window count then and is
stale now. Live `cuopt_invocation_log` on 2026-09-01, span 2026-08-02 → 2026-09-02:

| Ledger fact | Count |
|---|---|
| Invocations logged, total | **9,570** |
| Abstained without an HTTP call | **9,554** |
| — pacing abstentions: `debounce` 5,790 · `first_refusal_arm` 2,689 | 8,479 |
| — `sql_gate` stage: no reason recorded 513 · `sql_gate_no_candidates` 60 · `policy_disabled` 3 · `no_running_run` 1 | 577 |
| — `edge` stage: `no_candidates_in_instance` 383 · `no_free_stalls_demand_present` 114 · `missing_sim_run_id` 1 | 498 |
| NVIDIA HTTP calls with a logged `http_status` | **16**, all `200` |
| `proposals_out` returned, total | **136** (across those 16 calls) |
| `ottoq_decisions` with `l2_engine='cuopt'` | **27**, all `outcome_status='enacted'` |
| Deferral ledger (`ottoq_cuopt_deferrals`) | 28,460 rows: `clear` 28,397 · `spent` 63 |
| `ottoq_ab_runs` | **68 rows** (§4 said zero; not yet analysed for a cuOpt-vs-baseline delta) |
| All decisions in the same window, by engine | deterministic_v1 856,107 · inspect_seam 77,381 · greedy_constrained 52,708 · reservation_honoured 16,988 · needs_card 7,731 · charge_disposition 1,518 · reservation_reassigned 908 · nemotron 262 · reservation_broken 189 · ottoq_service_priority 108 · service_sequencing 105 · deterministic_fallback 79 · **cuopt 27** |

**The honest sentence, re-issued 2026-09-01 (both directions, per the standing rule):**

> *cuOpt is wired into the live tick as a gated proposer with a one-tick right of first refusal,
> and every invocation is ledgered. Over 2026-08-02 → 09-02 it was invoked 9,570 times and
> abstained 9,554 — 8,479 of those by design (debounce and first-refusal pacing), 577 at the SQL
> gate, 498 at the edge for lack of candidates or free stalls. It made 16 receipted NVIDIA calls,
> all HTTP 200, returned 136 proposals, and 27 decisions carrying `l2_engine='cuopt'` were enacted
> through the shield. Against 856,107 deterministic decisions in the same window, cuOpt disposed
> 27. `ottoq_ab_runs` now holds 68 rows; no measured throughput delta has been extracted from it
> yet, so none is claimed.*

**In certification runs specifically (round 5, 2026-09-01, 24 arms):** cuOpt was invoked 560 times
and returned **0** proposals (debounce 360 · first_refusal_arm 152 · edge no_candidates 24 · 24 gate
passes that found nothing). `ottoq_external_proposals` carried 76 rows, all from deterministic
internal proposers (`ottoq_service_priority` 28 pending / 28 superseded; `greedy_constrained` 4 / 16).
Zero decisions with `l2_engine='cuopt'`. 1,368 deferral rows. **In rounds 3–6 the certification
matrix has not exercised an external proposer.** (Strictly: one `cert_harness` run on 2026-08-30
received a single proposal from the wired remote solver and did not enact it — the only such
event in the ledger.) That is the fact §8 below is built on.

**Provenance of the 16 receipted calls in the window:** 11 from `claude_v2_validation` (my own
V2 runs, 08-29; 88 proposals, 6 enacted), 2 from `operator_demo` (08-29; 26 proposals, 0
enacted), **2 from `production_live` (08-30; 21 proposals, 21 enacted)**, 1 from `cert_harness`
(08-30; 1 proposal, 0 enacted). 21 of the 27 enacted `l2_engine='cuopt'` decisions in the window
were made in the production loop.

## 2. The local decide path, in plain language (the disposer)

Reconstructed from the live functions (captured in `db/fn_current/`, md5-stamped) and the 16
policy-named backups. Cadence first, then the per-tick procedure.

**Cadence (who calls what):**
- **pg_cron job 12 `ottoq-demo-metronome`** (every minute) is the run engine: per running run it
  advances the world (`ottoq_sim_advance_tick_world`), then **alternates beats** — odd ticks run
  `ottoq_sim_decide_and_dispatch` (which itself fires `ottoq_cuopt_refresh` *then*
  `ottoq_decide_tick`, so a solve is always in flight one beat ahead), even ticks open a cuOpt
  solve window (`cuopt_solve_window_ms`, default 4000, policy-tunable per run) — but only under
  the `otto_q` run policy. **Run policy is already a first-class attribute of the run row** —
  the exact hook C5 wraps.
- **pg_cron job 10 `ottoq-depot-tick`** (*/2 min) → `ottoq_cron_tick`: world-advance safety net,
  expired-proposal sweep, then HTTP to `ottoq-orchestrate-tick` (25 s budget, cuOpt + energy +
  sequencing + shield), the Prime orchestrator agent every ~10 min, and wave admission.
- **pg_cron job 17 `ottoq-run-governor`** (*/2 min) — auto-stop guardianship
  (`ottoq_run_governor_auto_stop`, the stall_watchdog policy's descendant).

**One `ottoq_decide_tick(run)` pass (1,020 lines, sections in source order):**
1. **Reconcile before deciding.** Promote bookings `held→active` where the vehicle physically
   stands on its stall; release bays the twin emptied but never cleared (the P1 sweep that ended
   the 5-vehicle bay deadlock); slide forward ("honour or re-plan, never let it rot") any bay
   reservation whose vehicle is still on a charger; book in place any bay occupancy the twin
   admitted without a stall claim. All release-only: reconciliation can free space, never claim it.
2. **Energy/BESS** dispatch decision (MPC-informed when `energy_mpc_follow=1`).
3. **Deploy-readiness** — proposer-assisted (cuOpt/Nemotron may propose the redeploy; heuristic
   fallback), gated, and **command-emitting**: since migration 0039 OTTO-Q mutates no world
   state — it emits `ottoq_vehicle_commands`; the twin executes and confirms (refusal path 0036).
4. **Reopened needs are first-class demand** (P0): a cut-short charge re-competes in the same
   tick, through the same cursors, as a fresh arrival.
5. **Stall assignment**, the core loop. Advance the cuOpt deferral ledger exactly once
   (`ottoq_cuopt_defer_roll`: releases every previous-tick hold, consumes fresh arms — a hold can
   never span two ticks, so no vehicle starves). Then per candidate vehicle (ordered:
   immediate-dispatch urgency, then lowest SoC; staff-capacity-capped):
   `ottoq_honour_reservation_proposal` **proposes** (priority: honoured reservation → pending
   cuOpt proposal → deterministic/greedy) → **52-rule shield probe** (every rule result logged;
   790,192 evaluations lifetime) → blocked ⇒ L1 safe default; passed ⇒ reserve stall, **emit**
   `begin_charge`, claim tick kW, start concurrent atoms (the parallel-with-charge work), plan
   the itinerary, and — the P0 invariant — **record the booking on the forward calendar in the
   same transaction, against the exact stall enacted** (`ottoq_record_enacted_booking`; the
   EXCLUDE constraint is the physical backstop). Every decision lands in `ottoq_decisions` with
   propose/shield/enact latencies.
6. **Gate intake for no-charge arrivals** (3b) — staging by purpose and duration, never a gate
   queue (founder doctrine 2026-07-28).
7. **Charge disposition** (4) — the charge-stall→wash-bay door, gated by the tether check (a
   mated vehicle moves nowhere until the ~11.5 s demate completes — the demate_deadlock lesson),
   service-need routing (don't burn a wash bay on a clean car), and choose+claim+record as one act.
8. **Needs-card space routing** (4b, P1) — for staged vehicles, read the needs card, take the
   highest-priority space-requiring must-do, place it through the same one-act enactment. Ordered
   within a vehicle by catalog `sequence_order`; across vehicles by urgency → fits-window → EDF →
   shortest-job → deterministic id tiebreak. Guarded by a five-clause **charge firewall** (bays
   can never consume a charger or a charging tech) and a per-lane **anti-starvation budget**
   (resumed work capped at half a lane's free bays per tick, only while fresh work competes).
9. **Service sequencing** (5) — proposer-assisted ordering, same shield, same one-act calendar.

The three properties a hostile reviewer should test, and where they're enforced: **no decision
without a shield trace** (every path inserts into `ottoq_decisions` with `rule_results`);
**no enactment without a calendar row in the same transaction** (P0, sections 3/3b/4/4b/5); **no
world-state write from the brain** (0039: commands out, twin confirms, refusals recorded — the
31,157-executed/0-refused era is closed by 0036's pre-execution validation).

## 3. The three-layer architecture, with ledger numbers

| Layer | What it is | Live numbers (2026-08-19) |
|---|---|---|
| **L1 — deterministic rules** | 52 versioned, tenant-parameterizable rules; every evaluation logged; safe defaults on block | 790,192 evaluations · 1 overridden-to-default decision in window |
| **The decide path** | `ottoq_decide_tick` + reconciliation + command emission, alternating-beat metronome cadence | 1,262 decisions in window: 874 enacted · 387 noop_no_candidate · 1 overridden; engines: deterministic_v1 1,045 / needs_card 92 / nemotron 87 / inspect_seam 28 |
| **Proposers** | cuOpt (gated, debounced, deferral-armed, batch-enacted), Nemotron advisory ring (Prime, copilots, feed agents), energy MPC bridge (EC2 LP), external proposals table | §1 for cuOpt · `ottoq_external_proposals` in window: 1 superseded row (`ottoq_service_priority`) · MPC: `ottoq_energy_plan` plan rows, `energy_mpc_follow` defaults 0 |

Doctrine check against reality: **"agents propose, solver disposes" holds** — no proposer writes
a final assignment; everything returns through the shield + one-act enactment. The
deferral/right-of-first-refusal pattern described in CLAUDE.md 2.5 **is live** in
`ottoq_decide_tick`/`ottoq_cuopt_refresh`/`ottoq_cuopt_defer_*` (migration 0032's removal of it
was superseded; 0040 restored the tick pipeline — the live code carries both the deferral arm
and the atomic batch enactment).

## 4. What the A/B substrate can and cannot say today

`ottoq_ab_runs` (the CRN-paired, seed-keyed comparison table with `ottoq_ab_paired_summary` /
`ottoq_ab_stats`) **holds zero rows**, and all 145 rows of `ottoq_run_archives` carry
`policy='otto_q'` — no FIFO or greedy run is currently archived. The machinery is real (schema,
stat functions, `ottoq_sim_runs.policy` plumbed through the metronome); the *data* was purged or
never re-generated after the August engine rebuilds. Consequence: **no comparative throughput
claim is currently reproducible from a run ID.** C5's comparison run regenerates this from the
existing machinery — wrap, don't rebuild — and that run becomes the first citable baseline of
the new era.

## 5. The captured IP (closing the "only lives in the database" gap)

`db/fn_current/` now holds the live definitions (verbatim, md5-stamped, 2026-08-19) of the 19
decide-path/cuOpt-seam functions: `ottoq_decide_tick`, `ottoq_cron_tick`, `ottoq_demo_metronome`,
`ottoq_sim_decide_and_dispatch`, `ottoq_evaluate_return_need`, `ottoq_charge_plan_for_visit`,
`ottoq_l2_optimize_assignments`, `ottoq_release_expired_tethers`, `ottoq_run_governor_auto_stop`,
`ottoq_twin_snapshot`, `ottoq_cuopt_refresh`, `ottoq_enact_cuopt_batch`, `cuopt_log_gate`,
`ottoq_cuopt_first_refusal_arm`, and the twin five (`advance/start/stop_charge_session`,
`confirm_commands`, `start_run`). The 13 `ottoq_fn_backup_*` policy tables (16 pre-change
captures, 2026-08-12→14) remain in the DB as recovery substrate; their index (fn → md5 → date):

| Policy backup | Function(s) captured | Backed up |
|---|---|---|
| cold_start | twin.ottoq_sim_start_run | 08-13 |
| dcfc_day_night | twin.ottoq_sim_advance_charge_sessions, twin.ottoq_sim_start_charge_session | 08-13 |
| dcfc_first | ottoq_charge_plan_for_visit, ottoq_l2_optimize_assignments | 08-13 |
| demate_deadlock | ottoq_release_expired_tethers, twin.ottoq_sim_stop_charge_session | 08-13 |
| frozen_target | twin.ottoq_sim_advance_charge_sessions | 08-13 |
| geometry_contract | ottoq_twin_snapshot | 08-13 |
| night_waves | ottoq_evaluate_return_need | 08-13 |
| plug_target_policy | ottoq_charge_plan_for_visit | 08-13 |
| single_run | twin.ottoq_sim_start_run | 08-14 |
| soc_clamp | twin.ottoq_sim_advance_charge_sessions | 08-12 |
| stall_watchdog | ottoq_run_governor_auto_stop | 08-13 |
| supersede_churn | twin.ottoq_sim_confirm_commands | 08-14 |
| tick_observability | ottoq_demo_metronome | 08-13 |

## 6. The deterministic-core recommendation (C4 step 4) — and the prototype

**Recommendation: (b) — CP-SAT enters as an additional proposer under the existing
right-of-first-refusal pattern. The local decide path is not replaced and remains the named
policy.** Grounds, from §1–§3:
1. The propose/dispose pipeline is the proven, shield-audited spine; §1 shows the risk of a
   proposer integration is starvation/supply bugs, and the deferral + one-act-calendar machinery
   is precisely what contains that risk. Re-using it costs nearly nothing.
2. The per-vehicle greedy cursor structurally cannot see the joint problem (chargers + bays +
   moves + site power + cooldowns at once). That joint problem is CP-SAT's home turf — and it is
   where the 2.5 requirements live. The prototype proves the whole requirement set fits one model.
3. No A/B evidence exists today (§4). A takeover decision without CRN evidence would violate the
   house epistemics; a proposer entry generates that evidence through C5/C6 first.

**The prototype** (`solvers/cpsat/`, OR-Tools CP-SAT 9.15, ~420 lines + tests): the reduced
canonical scenario (`scenario_canonical.json`, seed **424242**, 12 assets over the 3 live class
codes with the 0043 energy curves, 4×DCFC/2×L2/2×wash/1×service points) solved to **OPTIMAL**,
honoring every 2.5 modeling requirement — piecewise charge segments above 70% SoC (chained
intervals, per-segment kW), the 18-min DCFC cooldown as a minimum gap **on the point**
(occupancy = chain + cooldown), cold-start as a first-segment duration modifier, the multi-term
objective with exposed weights (tardiness 10/min · on-peak kW-minute 1 · peak-kW excursion above
the soft site target 20/kW, exact via IntVar cumulative capacity · move 15), concurrency within a
point (parallel ops inside the charge window, serialized per asset), inter-point moves as
scheduled operations on a capacity-2 path resource, and rolling re-solve with previous-feasible
retention (started ops pinned; solver failure returns the previous plan — the site is never
without a schedule). Output is a proposal batch in the exact `ottoq_external_proposals` shape,
`source='cpsat'`.

Test battery (`test_cpsat_prototype.py`, re-run 2026-08-27; the 2026-08-19 transcript this
block used to carry was stale — the scenario has moved since, so the T1 line quoted a plan
the committed scenario no longer produces):

```
T1  PASS determinism: sha256 330efe0721c119a6… identical across 2 solves (OPTIMAL, objective=135)
T1b PASS truncated solve (FEASIBLE, det budget 0.06) byte-identical idle vs 5 contending processes
T1c PASS default solve is deterministically budgeted with no wall-clock limit;
         a wall-clocked plan is labelled reproducible=False
T1d PASS fresh-process solve matches: sha256 330efe0721c119a6…
T2  PASS point exclusivity + 18-min DCFC cooldown held on every point
T3  PASS site power: true peak 440 kW <= hard cap 1000 kW; excess over soft target = 0 kW
T4  PASS piecewise segments taper above 70% SoC; cold-start modifier applied
T5  PASS concurrency-in-point + 4-min moves as scheduled operations
T6  PASS re-solve at t=120 with NASH-DCFC-02 blocked: 9 started ops retained, none on the blocked point
T7  PASS 12 proposals in ottoq_external_proposals shape (source='cpsat'); nothing writes state
T8  PASS charge_segments derives from the class energy_curve
```

### 6.1 The determinism claim was false, and how (2026-08-27)

The prototype's header claimed determinism under fixed seed on the strength of a fixed
`random_seed`, a single worker, and a stable build order. It also set
`solver.parameters.max_time_in_seconds` — **a wall-clock limit** — and said nothing about it.
A search truncated by the clock stops wherever the machine happened to be at that instant, so
the plan is a function of how loaded the box was, not of the seed.

T1 could not catch this. The canonical scenario proves OPTIMAL, so no limit ever binds and the
two solves agree for reasons unrelated to the budget. **A determinism test on a case that
finishes early is not a determinism test.**

Measured on the canonical scenario, one worker, seed 424242, at a 1.2 s wall-clock limit:

| budget | contending processes | status | objective | plan sha256 |
|---|---|---|---|---|
| wall 1.2 s | none | FEASIBLE | 7311 | `eeb58aed4f4bf15a…` |
| wall 1.2 s | all cores | FEASIBLE | **10261** | **`22797ea092062a6f…`** |
| det 0.06 | none | FEASIBLE | 13461 | `b809de73c3fef4af…` |
| det 0.06 | all cores | FEASIBLE | 13461 | `b809de73c3fef4af…` |

Same seed, same scenario, same config: a 40 % worse schedule because the machine was busy —
and it would have shipped under the same run ID. The deterministic budget is unmoved by the
same load.

The exposure was not hypothetical. `scenario_deck.json` — the 48-asset deck scenario — solves
in **19.34 s** against the old **20 s** default. Three percent of margin between the numbers in
the deck and a different set of numbers.

The fix: `max_deterministic_time` (CP-SAT work units, machine-independent) is the binding limit
at a 5.0-unit budget, ~7× the worst committed scenario's 0.70; `max_time_in_seconds` is left
unset. A caller may still pass `time_limit_s` — the live proposer has one tick of
right-of-first-refusal before the local path pre-empts it — but the plan then carries
`repro.reproducible = False` unless it proved OPTIMAL, because optimality is limit-independent
and a truncated search is not. `forward_proposer.propose()` surfaces the same flag in its
solver accounting, so "truncated by the clock" stays distinguishable in a fire record, the same
discipline `cuopt_invocation_log` applies to abstention.

No plan moved: all four committed scenarios and the C5 comparison hash byte-identically before
and after.

### 6.1a Rejection and churn — the two T2 features that were genuinely missing

Reading the prototype against the defense spec's T2 definition (rolling-horizon CP-SAT *with
rejection, churn term, hints, frozen window*), four of the five already existed and ran: rolling
re-solve, `AddHint` warm-starting, the frozen commitment window (started work pinned at `t_now`),
and the multi-term objective. **Rejection and the churn term were absent.** Both are now built, and
both are **off by default** — the four committed scenarios, the C5 comparison and the 24h KPI gate
hash byte-identically with them off, so no published number moves until a caller opts in.

**Rejection** (`allow_rejection=True`). Without it `AddExactlyOne` forces every asset onto a point,
so an over-subscribed site returns INFEASIBLE and the decide path is left with no schedule at all.
That is the wrong failure for a site under pressure and the wrong one for a contested site. With it,
on a deliberately tightened canonical scenario that is INFEASIBLE by default: **10 of 12 served, zero
tardiness on the served set**, and the two it could not serve enter the proposal batch as
`abstain: true` — a field `ottoq_external_proposals` already carries and the dispose path already
reads, so no new vocabulary. The default penalty is 100,000, an order of magnitude above the worst
single-asset tardiness the horizon can produce, so the solver rejects only when the alternative is
infeasibility rather than as a cheap way to duck a hard asset.

**Churn** (`objective_weights.churn_per_change`). The previous plan was only ever *hinted*; nothing
priced leaving it, so a rolling re-solve would relocate an asset for a one-minute objective gain — in
the yard, a real vehicle making a real trip for nothing. Measured on a re-solve an hour in with one
DCFC point out of service: **unpriced, 4 of 12 assets change point; at weight 500, 2 do.** The two
that still move are the ones the blocked point displaced, and they **cost nothing** — a forced move
is free, because charging for it would price the site's own failure to the asset. The term is built
only when a weight is set; "add it with weight 0" is not equivalent, since the extra variable can
land the search on a different equally-optimal plan (§6.2).

**A bug found by trying to falsify the guard rather than trusting it.** Rejection's first
implementation excused a rejected asset from tardiness with
`m.Add(tardy == 0).OnlyEnforceIf(served.Not())`. That reads as removing a price; it imposes a
constraint. Combined with `tardy >= finish - ready_by` it forces `finish <= ready_by` for an asset
nobody is serving, and that asset's own parallel-op durations can make it impossible: on the tight
scenario with `ready_delta_min [5, 12]` the model went **INFEASIBLE with rejection enabled** —
exactly the failure the feature exists to prevent. Every other assertion in the battery passed. The
fix removes the term from the *objective* instead (a `charged` tardiness variable, which the
lexicographic passes also read so a rejected asset cannot eat `max_tardy_total`), and **T9b pins the
scenario that exposes it**. The canonical scenario is far too slack to show it, which is why the bug
survived its first review.

T9's pinned objective and rejected set are load-bearing for the same reason: mutation-testing showed
that removing the `served` gate on wash/inspect (so a rejected asset still holds a bay) and removing
the tardiness excuse **both passed every structural assertion** while silently changing which assets
were dropped. The number is what sees them.

### 6.1b A tariff window outside the horizon made every site infeasible

Found while testing rejection through the production bridge, and worth separating from it because
at first it looked like *"rejection enabled and still no plan"* — precisely the failure rejection
exists to prevent. It was not that. **One asset on one free point was infeasible too**, which is what
proved it had nothing to do with capacity.

The on-peak overlap held `max(charge_start, window_start)` in a variable bounded by the horizon. So
whenever the tariff window began **after the horizon ended**, `max(s, 240)` was unrepresentable in
`[0, 180]` and the model returned INFEASIBLE outright — with a message blaming the site.

Measured on the bridge's own frame, one vehicle needing 48 minutes on one free stall:

| horizon | on-peak window | result |
|---|---|---|
| 120 min | [240, 420] | **INFEASIBLE** |
| 180 min | [240, 420] | **INFEASIBLE** |
| 240 min | [240, 420] | OPTIMAL |

This is ordinary production input, not a corner: plan the next two hours at 08:00 against a
16:00–19:00 on-peak window and **nothing is ever schedulable**. The window is now clamped to the
horizon, and when it does not intersect at all the term is not built — a window outside the horizon
costs nothing, because every interval ends by `H` and no charge can run in it. All four committed
plans hash byte-identically, since their windows lie inside their horizons.

T11 pins it with **one asset against the full point set**, deliberately: a larger fleet at that
horizon is genuinely capacity-bound, and a test that cannot tell a real limit from a modelling bug
sends you looking in the wrong place — which is exactly what happened the first time.

Two smaller fixes came with it, both in `proposer/forward_proposer.py`:

- **`plan_to_proposals` silently dropped a rejected vehicle.** Its `continue` past any asset with no
  charge op was harmless while every asset was guaranteed a point, and became a silent drop the
  instant the solver could decline one — leaving *no row at all*, indistinguishable from a vehicle
  nobody asked about. That distinction is the whole reason `cuopt_invocation_log` exists on the
  other proposer. Every vehicle now gets a row; the guard is row count, and mutation-testing
  confirms it is the only assertion in that file that sees the drop.
- **T\* summed `tardy_min` over rejected assets**, which are `None`. A rejected vehicle has no
  deadline to miss because nothing is being done for it, so it is excluded — matching the model,
  whose lexicographic passes read *charged* tardiness for the same reason.

### 6.1c What the solver is actually worth, measured (2026-08-27)

Written because `docs/BENCHMARK_CREDIBILITY.md` (2026-08-23) said the opposite and was quoted as
current for four days after it stopped being true. Both of its legs are superseded; that file now
carries the correction and the reasoning behind it.

**On the canonical scenario, CP-SAT and greedy tie at the certified floor.** Under the scenario's
own weights, re-derived from `policies/comparison_seed424242.json` at HEAD: greedy 135, cpsat 135 —
both 0 tardy, both finishing before the on-peak window opens, both paying only the 9-move cost. The
118 tardy minutes that used to separate them were a model bug fixed 2026-08-24.

**Under the real tariff they separate.** `policies/cost_seed424242.json`: cpsat **$8,160.71/mo**,
fifo $8,162.27, otto_q_asis $9,466.70, greedy $9,532.40 — `pareto_optimal: ["cpsat"]`,
`dominated: ["fifo", "greedy", "otto_q_asis"]`. The synthetic objective prices only *excess above a
soft target*, which is dead under abundance; a utility bill prices peak **absolutely**.

**Where a cap actually binds, the naive baselines produce unrunnable schedules.**
`scenario_vertiport.json` declares 1,231 kW installed against an 800 kW service.
`policies/multimodal_seed424242.json`: fifo and greedy both peak at 843 kW, 43 kW over, stamped
`physically_runnable: false`; the CP-SAT lexicographic forward policy holds **300 kW at zero
tardiness**, and is the only runnable policy in the set.

**The caveat, stated because it cuts against us:** fifo and greedy here have no power-cap check at
all, so part of that gap is baseline naivety rather than solver skill. A cap-aware heuristic has
never been built or measured. Until it is, the *existence* of the advantage is evidenced and its
*size* is not.

### 6.2 The same run needs the same OR-Tools, and CI was installing a range

`verify.yml` installed `ortools>=9.10`. Measured on the four committed scenarios, 9.11.4210 vs
9.15.6755:

| scenario | objective 9.11 | objective 9.15 | plan sha256 9.11 | plan sha256 9.15 |
|---|---|---|---|---|
| canonical | 135 | 135 | `0558a9e0dc83…` | `330efe0721c1…` |
| 24h | 1490 | 1490 | `1c8f7ab7828b…` | `c720132fdeed…` |
| deck | 296 | 296 | `ed8b131f7c9c…` | `008f3beb155e…` |
| vertiport | 60 | 60 | `e1a41d82a3f3…` | `d1edb255a000…` |

**Every objective is identical; every plan differs.** Neither version is worse — both prove
optimal — but they break ties among equally-optimal schedules differently, so *which* asset goes
to *which* point at *which* minute moves. The schedule is what ships; the objective is a number
about it. This is precisely the failure the defense spec's T1 row names: integer-quantised costs
tie constantly, and unspecified tie-breaks are the classic source of "why did it change?"

So the version is part of the reproducibility key. `verify.yml` now pins `ortools==9.15.6755`,
`plan["repro"]["ortools_version"]` records it, and the drift message diagnoses a mismatch by name
instead of leaving a reviewer to guess. Had CI ever resolved 9.11, the old battery would have
silently rewritten `plan_seed424242.json` to a different schedule and reported success.

One related sharp edge: `CpSolver` only grew a `deterministic_time` accessor around 9.15; on 9.11
the number lives on the response proto alone. `_det_time()` reads whichever exists, so an older
ortools produces a clear result rather than an AttributeError mid-solve.

### 6.3 The guards

T1b is the standing guard — a deliberately truncating deterministic budget solved idle and under
full CPU contention, asserting byte-identical plans **and** asserting the budget actually bound,
so the test can never pass vacuously the way T1 did. T1c asserts the posture directly (finite
deterministic budget, no finite wall-clock limit, single worker); T1d re-solves in a fresh
process, since repeat solves in one process can agree through warmed state.

The committed `plan_seed424242.json` is the reproducibility artifact: same seed → same sha256.
It is now **compared** by the battery rather than overwritten by it. Previously the battery
rewrote the artifact on every run and nothing in CI ever read it — a proof that regenerated
itself out of any disagreement it might have found. Regenerating is now deliberate
(`REGEN_PLAN=1`) and lands as a reviewable diff.

## 7. Nothing deleted (C4 step 5)

No function, table, proposer, or policy was removed or modified in this phase. The local decide
path remains the `otto_q` named policy; cuOpt's gate, deferral, and batch enactment remain live;
the prototype is additive and unwired until C5 wraps it as a policy.


---

## 8. Proposals and the verdict — the gate before the agentic layer (added 2026-09-01; reframed 7:35 PM CT)

> **Scope note (Chase, 7:30 PM CT):** the solver/proposer choice is **open**. cuOpt is not a
> commitment; it is one candidate, and the right tool is to be determined once the deterministic
> layer is fully functional. Nothing in this section presumes cuOpt. Every mechanism below is
> proposer-agnostic — it applies identically to CP-SAT (`solvers/cpsat/`), the forward orchestrator
> (`proposer/`), cuOpt, an LLM, or a proposer that does not exist yet. cuOpt appears in §1/§1a only
> because it is the proposer that is *currently wired into the tick* and therefore the one the
> ledger has numbers for. §1a's finding that it is invoked in every certification run (560 times in
> round 5, always abstaining) is a fact about the present engine, not an endorsement.

**Where the pair verdict stands after 0148.** `ottoq_determinism_pair` hashes six streams per arm
— `fp` (boot world), `h_cmd` (vehicle commands), `h_dec` (decisions), `h_evt` (events), `h_bkg`
(stall bookings), `h_nrg` (energy commands) — plus `endst` (end state) and `complete`. Every hash
now sorts by every field it hashes (0148). **Proposals are not in it.** `ottoq_external_proposals`,
`ottoq_cuopt_deferrals`, `cuopt_invocation_log` and `ottoq_cuopt_fire_log` sit outside every hashed
surface, exactly where the energy tables sat before 0148 and where the end state sat before 0139.

**Why that has not bitten yet.** §1a: in certification runs cuOpt returns zero proposals and the
proposal table carries only deterministic internal proposers. Nothing nondeterministic has been
allowed to propose during a certified run, so there has been nothing for the blind spot to hide.
That will stop being true the day *any* proposer — CP-SAT in `solvers/cpsat/`, the forward
orchestrator in `proposer/`, a remote solver, an LLM, or one not yet chosen — is wired into a cert run.

**"Agents propose, solver disposes" is currently an architectural statement, not a certified
one.** To certify it, two things must be separately observable per pair:
1. what was proposed (so a nondeterministic proposer is caught as such, not misread as a
   disposer fault), and
2. that identical proposals produce identical disposals (which `h_dec`/`h_cmd` already prove,
   *given* identical proposals — a premise the verdict cannot currently check).

### 8.1 `h_prop` — proposals enter the verdict, before any agent does

Add to the per-arm object, computed exactly like `h_cmd` (before `stop_and_reset`, stored in
`validation_notes` arm_a/arm_b automatically, entering `v_equal`):

```
'h_prop', (SELECT md5(COALESCE(string_agg(
    p.action_context||'|'||p.entity_type||'|'||COALESCE(p.entity_id::text,'-')
    ||'|'||p.source||'|'||p.status
    ||'|'||public.ottoq_scrub_ids(p.proposal::text),
    E'\n' ORDER BY p.action_context, p.entity_type, COALESCE(p.entity_id::text,'-'),
                   p.source, p.status, public.ottoq_scrub_ids(p.proposal::text)), ''))
  FROM ottoq_external_proposals p WHERE p.sim_run_id = v_run)
```

Excluded: `proposal_id` (uuid), `sim_run_id`, `depot_id` (constant per run), `created_at`,
`expires_at` (wall-clock TTLs — 0129/P3 made these sim-domain, but a timestamp is still not
content). `proposal` jsonb is id-scrubbed because proposals reference stall/booking ids that
are stable world ids when they are stalls and fresh uuids when they are bookings; scrubbing both
is the conservative choice and matches `endst`. `entity_id` is a vehicle — a stable fleet id —
so it is hashed raw, as `h_cmd` does. ORDER BY lists every hashed field (the 0148 rule).

A companion `h_defr` over `ottoq_cuopt_deferrals` (`vehicle_id|state|armed_at_tick|
spent_at_tick|cleared_at_tick|defer_count`, ordered by all of them) makes the right-of-first-
refusal mechanism itself certifiable. Cheap, and it is the one place a pacing bug would show.

**Expected effect today:** with only deterministic internal proposers, `h_prop` and `h_defr`
match across arms and the matrix gains two canon columns that never move. That is the point:
they are tripwires, armed before there is anything to trip them.

**Proof the migration must carry (falsifiable):** `h_prop` recomputed over round 5's twelve pairs
must be EQUAL on all twelve (the internal proposers are deterministic — if they are not, that is
a finding, not a proof failure, and the migration must stop and say so). There is no historical
pair on which `h_prop` should be UNEQUAL — none has run an external proposer — so unlike `h_nrg`
the migration cannot demonstrate discrimination on real data. State that plainly in it.

### 8.2 External proposers under certification — the decision Chase owns

Any proposer that runs outside the database — a remote solver, an LLM, a service behind an HTTP
call — is not reproducible under a seed from this side of the wire. Today that describes the two
that happen to be wired (a remote solver and an LLM); it will describe whatever is chosen later. Three defensible postures, not mutually exclusive:

| Posture | What it certifies | Cost | Honest limit |
|---|---|---|---|
| **A. Pin cert runs to deterministic proposers** (`policy_disabled` for external ones inside `run_by='cert_harness'`) | The disposer and the internal proposers, fully | One gate check | Says nothing about the engine *with* agents. The certified artefact and the shipped one differ by a switch. |
| **B. Record-and-replay** — production runs ledger every external proposal (the ledger discipline already exists: 136 proposals logged for the currently-wired proposer); a cert mode replays a recorded proposal stream into both arms | "Given these exact proposals, the disposer is deterministic" — the actual propose/dispose contract | A replay source for `ottoq_external_proposals` keyed by (tick, entity); `h_prop` is then the check that both arms *received* the same proposals | Does not certify the proposer. It is not supposed to. |
| **C. Live external calls in cert, proposals hashed** | Whether the external proposer happens to be reproducible | Nothing new | It is not reproducible, so this manufactures red pairs that are not engine faults. Reject. |

**Recommendation:** A now, B as the agentic layer's first deliverable, C never. Under A+B the
sentence becomes provable: *the disposer is certified deterministic against recorded agent
proposals; agents are measured, not trusted.* That is the edge Chase wants to show — an
orchestration kernel that lets AI propose without letting AI make the schedule irreproducible —
and it is a claim the harness can back with run IDs.

### 8.3 Sequence

1. `h_prop` + `h_defr` into the verdict (one migration, 0148 pattern, forces recert). Apply
   after round 6, alongside 0150/0151. One more round to re-establish canon with eight hashes.
2. Posture A: cert runs refuse external proposers explicitly (a check that fires if one proposes).
3. Posture B: replay source + the first recorded-proposal certification pair. That is the door to
   the agentic layer, and it opens with the harness already watching.

None of this starts until the deterministic core is green on the corrected instrument (round 6)
and the remaining core items are closed (0050/0051 peak_site_kw; 0150/0151).

#### 8.3a Status, 2026-09-08 22:30 CT (2026-09-09 03:30 UTC) — step 3 is DONE

Step 1 shipped as 0199. Step 3 shipped tonight, ahead of step 2, and it took four migrations
rather than the one this section imagined:

| | | |
|---|---|---|
| 0236 | a proposal knows which tick it was made in | APPLIED |
| 0237 | record and replay an agent proposal stream | APPLIED |
| **0238** | **the selector that consumes it is total on content** | **APPLIED — forces recert** |
| 0239 | `ottoq_determinism_pair_replay`, the replay-driven arm | APPLIED |

**0238 was not in the plan and is the reason the rest is trustworthy.** The proposal selector
ordered by `created_at DESC`, and `created_at` defaults to `now()` — the *transaction*
timestamp — while a certification pair runs both arms and every tick in one transaction. Measured:
821 of 827 runs carrying proposals have every proposal sharing one `created_at`. So the order was
decided by index-scan order, proven by a flip that was run and rolled back (`db/checks/0156`):
the same two proposals submitted A,B chose A and submitted B,A chose B. 0237's capture is
content-ordered by design and the runs it records from consumed in submission order, so a
faithful-looking replay could have enacted a *different* proposal than the run it came from —
with all fourteen atoms matching. Step 3 would have been a green verdict over a silently
different experiment.

**The proof is `db/checks/0157`.** Five pairs, one key, `p_replay_id` the only variable:

| run | replay | outcome | `h_prop` | `h_dec` |
|---|---|---|---|---|
| P0 | none | passed | `d41d8cd9…` (md5 of empty) | `c16074c6…` |
| P1 | R | **passed** | `c270c2c5…` | `4fe7b305…` |
| P2 | R | passed | `c270c2c5…` | `4fe7b305…` |
| P3 | R′ — perturbed a proposal nothing read | passed | `8db15dc6…` **moved** | `4fe7b305…` unmoved |
| P4 | R″ — perturbed a proposal it *enacted* | passed | `bfd3767c…` **moved** | `2f4cbbb9…` **moved** |

P1 is the sentence 8.2 asked for. P0 is the control that says the stream was not a no-op — a
certification today sees *no* proposals at all, because 0152/0105 quiesce the producers, so
P0's `h_prop` is literally md5 of the empty string. P2 is between-pair reproducibility, which is
the harder claim. P3 and P4 disagree deliberately: **`h_prop` is sensitive to the whole stream,
`h_dec` only to the part the disposer consumed** — what the agent *said* versus what the agent
*changed*.

Of the 24 replayed proposals in P1's arm A, the disposer **enacted 4, superseded 5, and left 15
pending**, at run `ac0f7263-5208-47d4-ade0-1630ed2d73d3`. That is propose/dispose as a ledger
row rather than a slogan, and the split is reproducible because `h_prop` hashes exactly those
statuses.

Two honest limits, stated so they are not quoted past: the stream is **synthetic** (no run in
this database has ever carried a tick-stamped proposal — 0236 shipped hours earlier and every
run since has been a certification, which quiesces the producers), and it ran on the **grid
fixture**, not the flagship depot. What is proven is the disposer's half. The capture half is
proven by 0237's assertions and awaits its first production stream.

Step 2 (Posture A — a cert that *refuses* a live external proposer) is now the only open item in
this sequence, and it is smaller than it was: 0152 already quiesces the producers run-scoped,
so what remains is a detector that fires rather than a gate that blocks.

#### 8.3b Step 2 is CLOSED too — 2026-09-09 00:19 CT (05:19 UTC)

**The whole 8.3 sequence is now shipped.** Posture A landed as **0241**, and the version that
shipped is not the version anyone would write first.

The obvious Posture A is *a certification refuses the agent door*. That was written, and then the
door was measured: **372 proposals reach 148 CERTIFICATION runs through it**, from
`ottoq_service_priority_propose` — which `ottoq_sim_decide_and_dispatch` calls **inside the
certified tick**. Banning the door would have deleted a certified proposer, narrowed what the
harness tests without saying so, and shipped under a `forces_recert FALSE` header that was simply
false. It would have passed a textual review.

Two column-based discriminators were tried next and both were also wrong: `declared_source` is
NULL for the internal proposers (only the door stamps it), and `submitted_by_role` is *not* null
for `ottoq_service_priority`. **Internal versus external is not visible in any column.** Which
proposer it is, is.

So Posture A is a registry — `ottoq_certified_proposers`, seeded from measurement rather than
intent (`greedy_constrained` 12,403 proposals / 542 cert runs, `ottoq_service_priority` 1,904 /
821, `cuopt` 1 / 1) — and its A5 asserts that seed **complete against every proposal ever written
to a certification run**. That is what makes `forces_recert FALSE` a measurement rather than an
argument. A replay is admitted by *being* a replay, never by registration, so Postures A and B
stay independent.

The same registry then closed a defect the Posture-B proof could not have caught (**G42**,
`db/checks/0159`, migration **0242**): `ottoq_proposal_replay_capture` defaulted `p_sources` to
NULL, meaning *every* source, so recording a run picked up the internal deterministic proposers —
and replaying that injects them at tick −1 while the proposer **also regenerates them** at their
real ticks. One list, two uses, one meaning: a certification *hears* these because they are the
certified core, and a capture *skips* these because a replay would double them.

Shipped state of the sequence:

| step | | |
|---|---|---|
| 1 | `h_prop` + `h_defr` in the verdict | 0199 |
| 2 | **Posture A — a cert hears only its certified proposers** | **0241** |
| 3 | Posture B — replay-driven certification | 0236 / 0237 / 0238 / 0239, proof `db/checks/0157` |
| — | the capture stops double-counting what regenerates | 0242 |
| — | the NVIDIA door leaves a ledger row either way | 0240 |

`ottoq_decide_tick` and `ottoq_determinism_pair` both keep their md5 through all of it; the recert
floor stays where 0238 put it (`2026-09-09 03:15:07`), which **round 31 then certified against on
all six columns with zero of fourteen atoms moved** (`db/canons/round31.md`).

---

## 9. cuOpt re-derived, 2026-09-08 — the honest sentence is much narrower

CLAUDE.md Part 1 rule 6: *"Any cuOpt statement — docs, decks, comments — is quantified from that
ledger. Unquantified claims are forbidden in both directions."* And Part 3, on its own
2026-09-03 refresh: *"rule 6's cuOpt sentence must be re-derived before it is spoken."*

Re-derived here against the live ledger on 2026-09-08. **Every earlier figure in this document
and in CLAUDE.md is superseded, including the ones that were correct when written.** They are
left in place as the point-in-time records they are.

> ### ⚠ AMENDMENT, 2026-09-08 22:4x CT (2026-09-09 03:4x UTC) — THE LEDGER THIS SECTION IS DERIVED FROM WAS INCOMPLETE
>
> Everything below is a correct reading of `cuopt_invocation_log`. What was not
> checked, until tonight, is whether that ledger sees every call.
>
> **It did not.** `db/checks/0158` (G40): three ACTIVE edge functions hold the NVIDIA
> cuOpt URL and only one of them wrote the ledger.
>
> | function | writes `cuopt_invocation_log` | reachable |
> |---|---|---|
> | `ottoq-cuopt-propose` | yes — the path §9 measures | from the decide path |
> | `ottoq-orchestrate-tick` | **no** | **unattended, from `ottoq_cron_tick` every 2 min** |
> | `ottoq-assign-optimize` | **no** | manual |
>
> `ottoq_cron_tick`'s own line 23 has said so since migration 0113 — *"this edge
> function calls cuOpt DIRECTLY; a deterministic-only session gates it off"*. 0113
> gated the path for certifications and nobody made it write a row.
>
> **§9.2's headline sentence still stands, but it was standing on one leg.** The
> second leg, measured tonight: over ten days `ottoq-depot-tick` fired 5,996 times
> and **5,986 (99.83%) returned in under 200 ms** — the line-5 early return, no work
> at all. Only 7 fires did real work, all inside the single `production_live` window
> of 2026-08-30, which carried `cuopt_propose_enabled = 0` explicitly, so the
> orchestrate dispatch was gated shut on every one. Independently: no
> `function_edge_logs` at all in a five-hour window during which 148 depot-ticks
> averaged 0.015 s.
>
> That second leg is real evidence but it is **circumstantial and perishable** —
> reconstructed from `cron.job_run_details`, which is pruned, and one
> `ottoq_policy_params` row. **Both doors now write the ledger** (edge versions
> `orchestrate-tick:v9` and `assign-optimize:v5`, deployed and verified 03:42 UTC —
> a row appears even on the abstaining early-return path), and migration 0240 makes
> the database-side *dispatch* a row too, because `net.http_post` is fire-and-forget
> and a request that dies before the function runs is otherwise indistinguishable
> from a gate that never opened.
>
> **Nothing in §9 needs its arithmetic redone. What needed redoing was the claim
> that the arithmetic was complete.** From 0240 onward the next derivation needs one
> leg again, and it is the ledger.
>
> One more fact from the same measurement, which belongs beside every sentence in
> this document about "the live production brain": in the last ten days this
> database has started **824 `cert_harness` runs, 8 `benchmark` runs, and 2
> `production_live` runs** — both of the latter on 2026-08-30. The production loop
> has not run in ten days. The proof harness is the only tenant.

### 9.1 The number everyone has been quoting is a log-row count

`cuopt_invocation_log` holds **15,250 rows**, spanning 2026-08-02 → 2026-09-08. CLAUDE.md's
refresh calls this "12,478 cuOpt invocations." It is not a count of invocations of anything. It
is a count of *decisions about whether to invoke*, and 15,234 of the 15,250 decided **no**.

The table has two stages and they answer different questions:

| stage | rows | abstained | reached NVIDIA (HTTP 200) | proposals |
|---|---|---|---|---|
| `sql_gate` — the in-database gate | 14,714 | 14,179 | 0 | 0 |
| `edge` — `ottoq-cuopt-propose` itself | 536 | 520 | **16** | **136** |

The gate posted 535 requests to the edge function. The edge function abstained on 520 of them
and made **16 network calls**, all of which returned HTTP 200 and 136 proposals between them.

### 9.2 Why the other 15,234 abstained — all of it, no rounding

| reason | rows | span |
|---|---|---|
| `debounce` | 6,128 | 08-29 → 09-02 |
| `policy_disabled` | 5,163 | 08-30 → **09-08** |
| `first_refusal_arm` | 2,827 | 08-29 → 09-02 |
| *(gate posted to the edge; no abstention, no call of its own)* | 535 | 08-29 → 09-02 |
| `no_candidates_in_instance` | 405 | 08-30 → 09-02 |
| `no_free_stalls_demand_present` | 114 | 08-29 → 08-30 |
| `sql_gate_no_candidates` | 60 | 08-29 → 08-30 |
| **`(called the endpoint)` HTTP 200** | **16** | **08-29 → 08-30** |
| `missing_sim_run_id` | 1 | 08-02 |
| `no_running_run` | 1 | 08-02 |

Two facts fall straight out of that table and neither is in any deck:

1. **The NVIDIA endpoint has not been called since 2026-08-30.** Nine days as of writing.
2. **Every row since is `policy_disabled`** — 5,163 of them. That is 0152 doing exactly what it
   was built to do: quiesce the proposer so the deterministic core is certified alone. It is
   correct, it is deliberate, and it means *cuOpt has been switched off for the entire
   certification era*. Anyone reading "12,478 invocations" as evidence of an agentic system
   running in production has been misled by a row count.

### 9.3 What it disposed, against a denominator that is fair

Only **4 sim runs** ever reached the endpoint. Scoping to exactly those runs — rather than to
all-time, which flatters nothing and clarifies nothing:

| | |
|---|---|
| decisions in those 4 runs | 6,154 |
| carrying `l2_engine='cuopt'` | **27** |
| of those, `outcome_status='enacted'` | **27** (all) |
| share of decisions in runs where cuOpt could act at all | **0.44 %** |
| other engines in the same runs | deterministic_v1, greedy_constrained, inspect_seam, needs_card, nemotron, charge_disposition, reservation_honoured, reservation_reassigned, service_sequencing, ottoq_service_priority, deterministic_fallback |

`ottoq_cuopt_deferrals` holds **29,712** rows — 29,645 `clear`, 67 `spent`. The deferral
mechanism (one-tick right of first refusal, then the local path pre-empts) has run tens of
thousands of times and released cleanly every time but 67. Nothing has starved.

### 9.4 The sentence the deck may use

> cuOpt is wired into the live tick as a gated proposer with a one-tick right of first refusal,
> and the gate is instrumented end to end. Across 15,250 logged gate decisions between
> 2026-08-02 and 2026-09-08, the NVIDIA endpoint was called 16 times — all on 29–30 August — and
> returned 136 proposals; 27 of those were enacted through the 52-rule shield, all of them, in
> the four runs where the proposer was live. Since 30 August the proposer has been switched off
> by policy so the deterministic core can be certified alone, which is why the other 15,234 rows
> are abstentions rather than calls. The propose/dispose pipeline is real and audited. The claim
> it supports today is that OTTO-Q *can* take an external optimiser's proposals and dispose them
> under an inviolable rule layer — not that it is doing so at scale.

That is a smaller claim than "12,478 invocations" and it is the one the ledger will survive
being asked about.

### 9.5 What this does not yet answer

No A/B delta. `ottoq_ab_runs` exists and §4 of this document noted 68 rows, but none of the four
cuOpt-live runs is paired against a cuOpt-off arm under common random numbers, so there is no
measured outcome difference to report and none is claimed. Producing one is a task, not a query:
it needs a cert-shaped pair with the proposer on in one arm — which, per §8, is exactly the
posture (C) this document already rejected for certification and would have to be run as an
experiment outside the certification lane.

---

## 10. The capability envelope, 2026-09-08 — the decomposition is forced, and CP-SAT is *determinizable*, not deterministic

§9 established what cuOpt has *done* (16 endpoint calls, 136 proposals, 27
enacted, no A/B). This section establishes what cuOpt *can express* — a different
question, and the one that settles the architecture.

Source: `docs/research/answers/R-12-cuopt-capability-envelope-beyond-routing.md`,
answered by Hermes 2026-09-08 against NVIDIA's own documentation at cuOpt
**26.08**, plus a direct check of the OR-Tools side recorded below.

### 10.1 What cuOpt cannot express — vendor-sourced, four for four

Our site is a resource-constrained flexible flow shop (`CLAUDE.md` 2.3). Its four
load-bearing constructs, against cuOpt 26.08:

| construct | ours | cuOpt |
|---|---|---|
| **cumulative resource** | site power cap, kW, consumed concurrently | **absent.** `add_capacity_dimension` is a per-vehicle knapsack along a route, not a shared time-varying pool |
| **disjunctive machine** | one stall, non-overlapping visits | **absent** |
| **sequence-dependent gap** | DCFC cooldown, 18 min on the service point | **absent.** `service_time` is a fixed per-stop constant |
| **a scheduling solver family** | — | **absent.** Routing (GA) + convex LP/QP + **MIP in beta** |

NVIDIA's own wording on the MIP beta: *"The solver currently excels at finding
high-quality feasible solutions quickly with GPU-accelerated primal heuristics.
**Proving feasible solutions optimal remains under active development.**"*

**So the decomposition — CP-SAT scheduling inside a site, cuOpt routing recalls
between sites — is FORCED by the API surface, not chosen by us.** The sentence
for the A/B design note is not "we prefer CP-SAT"; it is **"the site layer is not
expressible in cuOpt at all,"** and that is vendor-sourced rather than opinion.

Nor is there a bridge: warm start exists only cuOpt-to-cuOpt (routing accepts its
own prior solutions; the MIP beta documents no warm-start parameter at all), so
the matheuristic option is closed too.

### 10.2 CORRECTION to R-12's closing claim, found by direct check

R-12 ends: *"The byte-identical, reproducible output the certification rests on
is a CP-SAT property, not a cuOpt property."* **The cuOpt half is right and
well-sourced. The CP-SAT half carries no source and is materially incomplete.**

Checked directly on 2026-09-08:

- **Single worker is deterministic.** Fine.
- **Multiple workers are not, by default.** Determinism under parallelism requires
  the search to be split into fixed-size batches — `interleave_batch_size`,
  conventionally ~2× the worker count. Reported failures include *one worker
  returning optimal while eight returned infeasible on the same model.*
- **OR-Tools 9.4 and 9.5 shipped nondeterministic results even single-worker.**
  A vendor regression, in two consecutive releases, in exactly the property our
  certification depends on.
- **A wall-clock limit destroys determinism regardless of seed or threads.**
  `max_time_in_seconds` is hardware- and load-dependent; `max_deterministic_time`
  counts abstract ticks and is the reproducible one.

**CP-SAT is therefore determinizable, not deterministic**, and the difference is
four configuration pins, each of which must be asserted rather than assumed:

1. **Pin the OR-Tools version.** The 9.4/9.5 regression proves the property is not
   stable across releases.
2. **`max_deterministic_time`, never `max_time_in_seconds`.** A wall-clock budget
   inside a certified path is a nondeterminism source by construction — the same
   defect class as G15 (the L1 shield reading the wall clock inside the twin).
3. **Pin `num_workers=1`, or a fixed `interleave_batch_size`.**
4. **A determinism canary in CI** that would have caught 9.4/9.5 — the same
   instrument the SQL engine already has in the certification pair.

### 10.3 What this settles, and what it does not

**Settled:** cuOpt can never be the site scheduler, and cuOpt can never be inside
the certified deterministic path — its routing solver documents **no seed and no
determinism parameter at all**, and its MIP determinism mode is explicitly labelled
*"experimental … does not yet guarantee fully deterministic results in all
scenarios."*

That is not a mark against propose/dispose — **it is the argument for it.** A
nondeterministic proposer behind an inviolable deterministic shield, with its
proposals hashed into the verdict (`h_prop`, G4), is the only safe way to consume
a solver that cannot promise reproducibility. The architecture `CLAUDE.md` already
mandates turns out to be the one the vendor documentation requires.

**Not settled, and not to be implied:** that CP-SAT beats the local decide path,
or that either proposer improves any KPI. **No A/B pair has ever been run.** R-12
was explicitly scoped to exclude that question because it is ours to measure, and
nothing in this section measures it.

### 10.4 Alternatives considered, and declined for now

Given cuOpt cannot express the site layer, is a different scheduler worth
evaluating before we go deeper? Considered and declined:

- **HiGHS, Gurobi, or any MILP** — same gap as cuOpt's MIP beta: no native
  cumulative or disjunctive primitive, so the four constructs above become
  hand-rolled big-M encodings. That is us writing a MILP, not a solver feature.
- **Timefold / OptaPlanner** — metaheuristic, not exact; determinism is again
  configuration-dependent, and it adds a JVM to a Python/SQL stack.
- **Keep hand-rolling** — the local decide path already exists and remains a named
  policy regardless (`CLAUDE.md` C4 step 5).

**CP-SAT stays the choice**, because `AddCumulative` and `AddNoOverlap` are
native primitives for exactly the two constructs cuOpt lacks, and the prototype in
`solvers/cpsat/` already exists and passes 8 tests. This is a confirmation of
`CLAUDE.md` 2.5's existing decision on new evidence, not a re-opening of it.

**Sources for §10.2**, checked 2026-09-08 with Chase's explicit permission to
search (see `CLAUDE.md` Part 1 rule 3, amended the same day):
- https://github.com/google/or-tools/issues/3590 — "CP-SAT produces nondeterministic results"
- https://github.com/google/or-tools/issues/3842 — optimal at 1 worker, infeasible at 8
- https://d-krupke.github.io/cpsat-primer/05_parameters.html — `interleave_batch_size` and batch determinism
- https://github.com/google/or-tools/issues/2604 — `max_time_in_seconds` behaviour

---

## 11. Posture B, stress-tested 2026-09-09 — the replay path is exonerated by evidence, not by assumption

§8.3b closed the Posture A/B sequence. Overnight the replay rig was pushed at
flagship scale for the first time, and the first thing it did was **fail** —
which is worth recording, because the failure was not the replay's.

The pair `busy_day / 314159 / 12t` with a recorded agent stream injected came
back `failed` with exactly one of the fourteen atoms moved, `h_evt`, and it
moved on **one arm only**. The investigation is `db/checks/0160` and the finding
is opened as **G43**; the short version is that the two arms did not boot from
the same world, and the enforced atom whose job is to detect exactly that — `fp`,
the start-of-run world fingerprint — reported them identical, because it does not
hash the four `robotic_tether_*` columns and neither does the per-arm fleet reset.

**What matters for this document is what the controls established about the
replay itself**, and they are unambiguous:

| control | what it ran | result |
|---|---|---|
| C1 | the replay function with `p_replay_id NULL` | passed, both arms on the canon |
| C2 | the identical replay pair, run again | **passed**, both arms on the canon |

C2 is the one that settles it. It replayed the same recorded stream into the same
column and produced `h_prop = 0299e5e6b7112f6978a1177ba12230fe` — byte-identical
to the `h_prop` of the pair that failed, identical across its own two arms, with
the same `replay_injected = 5`. Four arms, two transactions, half an hour apart,
one proposal ledger.

**The injection is reproducible.** Whatever moved `h_evt`, it was not the replay
being nondeterministic, because it is not. `db/checks/0157`'s Posture B proof
stands, and `0239` is not implicated.

Two smaller things the same investigation settled, both worth having:

- **The double-count is real and is invisible to a pair.** `0159`'s P2 was
  confirmed exactly — a no-replay arm holds 5 proposals, each replay arm holds 9:
  the same 5 the run regenerates for itself, plus 4 injected copies. Both arms
  double-count *identically*, so `h_prop` agrees and the certification cannot see
  it. That is why `0242` had to fix the capture rather than the comparison, and
  it is a standing caution: **a determinism pair is the wrong instrument for a
  defect that is symmetric across arms.**
- **`0159`'s P3 was falsified.** It predicted the pair would pass. It failed —
  for an unrelated reason. The prediction was wrong; the mechanism it asserted
  (symmetry hides the double-count) was right, and is now measured.

