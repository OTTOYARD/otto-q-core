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
