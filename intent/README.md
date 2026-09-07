# The Intent Artifact — machine-readable commander's intent

**What this is.** The agentic layer's single source of truth for *what is worth
doing among what is allowed*. It is the "commander's intent" made into a
versioned, fingerprinted, deterministic data artifact that the optimizer reads
and the deterministic core enforces.

**Where it sits.** On top of the three-layer funnel that already works:

```
agentic layer  ──  this artifact + the forecast + the learn loop
proposer       ──  forward_lex (built)
solver         ──  CP-SAT / HiGHS (built, lexicographic)
deterministic  ──  52-rule shield + decide path (built, the legal gate)
```

---

## The numeraire decision (why this is a taxonomy, not a soup of weights)

R-10 proved the thing that makes weighted-sum optimization wrong for a depot:
**no robotaxi operator has ever published a dollar value for a late minute or
an unready vehicle.** A weight is a price on lateness nobody agreed to. So the
objectives are ordered **lexicographically**, not summed — the same structure
`policies/forward.py` already ships (min tardy, then min peak), generalized to
the full objective space.

Every objective carries a `dollar_value` field. Where a sourced marginal dollar
figure exists (energy, demand charge, BESS, staff, degradation) it is stated
with its source. Where none exists (readiness, throughput, dwell, deadhead,
staging) it is flagged `NOT_FOUND` — and NOT_FOUND is a first-class value, not
a blank. A reviewer who asks "what is a minute of lateness worth?" gets the
honest answer: *nobody has published it, so we treat it as a floor, not a
coefficient.*

## The three tiers

- **Tier 1 — master objectives.** What "good" means for the business: readiness,
  throughput, energy cost, service completion.
- **Tier 2 — operational levers.** The mechanisms that serve the masters: dwell,
  deadhead, staging, staff, BESS peak-shaving, degradation, risk hedge.
- **Tier 3 — constraints.** Physics, legality, chemistry caps. **Hardcoded, never
  weighted.** Lives in the 52-rule shield, not in this artifact (this artifact
  points at it and does not duplicate it).

## Regimes — weights are not constant

Same depot, same assets, different correct answer by the clock. A `regime` is a
named operating condition (dispatch rush, overnight, grid peak, demand surge,
weather event) plus a priority ordering of objectives. `resolve_intent` picks
the regime from a declarative `match` and returns the active priority order.

**Floors are structural, not regime-dependent.** `readiness` (never strand an
asset) and `service_completion` (never miss a must-by) are prepended to every
resolved priority, in canonical order — a regime that omits them cannot drop
them. This is the DECISION_BOUNDARY rule made mechanical: anything that can
strand an asset is always-on, never a regime choice.

**Signals override the clock, structurally.** A regime that *requires* a signal
(`grid_peak`, `demand_surge`, `weather_event`) is evaluated before any pure-clock
regime, so a `grid_peak_imminent` signal at 07:00 resolves to `grid_peak`, never
`dispatch_rush` — the resolver does two passes (signal regimes, then clock
regimes), it does not rely on declaration-order luck. Among simultaneous
signals, the artifact declares `weather_event` first, so a grounding risk (safety)
outranks a cost signal (`grid_peak`) outranks a throughput signal (`demand_surge`).

## The signal bridge (intent/signals.py) — forecast → regime signals

The forecast predicts the demand-side world; the regimes respond to qualitative
events. This module is the seam: it turns the forecast's numbers into the
signals `resolve_intent` reads. Three signals, two derived:

| signal | derived from | mechanism |
|---|---|---|
| `demand_surge` | arrivals forecast | expected arrivals over the next window ≥ `surge_multiplier` × the fleet's mean hourly return rate |
| `grid_peak_imminent` | load forecast + site soft power target | the p90 load (conservative tail) over the next window reaches `peak_fraction` of the soft target — the demand charge is at risk |
| `weather_hold` | *external input* | passed through, never derived — the statistical forecast has no live-weather event model |

**The honest threshold discipline.** Each signal's *mechanism* is grounded (the
soft target is the sourced demand-charge ceiling, R-5/R-6; the arrival baseline
is the fleet's declared scale). The exact *numbers* (`surge_multiplier` 2.0,
`peak_fraction` 0.9, window lengths) have no published AV-depot value, so every
one carries `evidence_label: "inference"` and `source: "must-measure-on-twin"` —
a defensible default, flagged for calibration, never dressed up as a sourced
coefficient. The bridge is a pure function of its arguments, deterministic, and
TOTAL: a malformed forecast raises `ForecastContractError` (a missing field is
never silently treated as zero, which would hide a real surge or peak).

The loop closes end-to-end: `forecast_signals(...) → resolve_intent(..., signals=...)`
is tested, including a hot window at 07:00 resolving to `demand_surge` rather
than `dispatch_rush` (`intent/test_signals.py`).

## The pass sequencer (intent/solve.py)

Maps the resolved intent to an ordered solver pass list. This is the single
place the truth lives about what the solver can *actually* do:

| objective | solver pass |
|---|---|
| readiness | `min_tardy` (the floor — always pass 1) |
| service_completion | `shield` (hard must-by deadline, not a pass) |
| throughput / dwell | `min_flow` (dwell/turnaround — finish vehicles soonest, deduped) |
| energy_cost / bess_peak_shave | `min_peak` (deduped) |
| deadhead, staging, staff, degradation, risk_hedge | *none — not yet a variable term* |

`pass_sequence(active)` returns the ordered, deduplicated pass modes;
`unmodeled(active)` returns the objectives a regime prioritizes but the solver
cannot yet optimize, so the gap is visible rather than silently ignored.

**The regime now genuinely reorders the schedule.** With three variable passes
(`min_tardy`, `min_peak`, `min_flow`) and the floors always first, the soft
passes follow the regime's priority: dispatch_rush and demand_surge run
`(min_tardy, min_flow, min_peak)` / `(min_tardy, min_flow)` (throughput before
energy); grid_peak and overnight run `(min_tardy, min_peak, …)` (energy first);
weather_event runs `(min_tardy,)` alone. Measured on the canonical scenario:
grid_peak finishes the fleet at flow 2937 min / peak 150 kW; dispatch_rush
finishes at flow 1676 min / peak 400 kW — a real, named throughput-vs-energy
trade-off, not a relabelled plan.

**Performance, stated not hidden:** `min_flow` does not prove OPTIMAL on slack
scenarios (large flat region) — it runs to a deterministic budget and returns
FEASIBLE. Determinism comes from the budget, so the plan is byte-stable; only
the third tier is truncated (tardiness and peak are proven OPTIMAL). A flow-first
chain also makes the trailing peak pass harder (it must hold a tight flow
ceiling). A cheaper per-tick flow formulation is the open hot-path item; for
offline planning and the demo the current solver is fine. See
`policies/test_regime.py` for the pinned trade-off numbers.

## The learn loop (intent/learn.py) — rejection and intractability reconciliation

The fourth line of the doctrine: *model proposes → optimizer disposes → shield
guarantees → loop learns.* This module is the LEARN step, in the only form that
is honest to build against the current world.

**The honest scope line.** FR-5 is documented as "offline RL / Bayesian tuning
from run outcomes." That half is deliberately **not built here** because run
outcomes are *contaminated*: the twin replays OTTO-Q's own decisions, so tuning
parameters against `ottoq_decisions` / dispatch history would be tuning against
our own bugs. It belongs in `ottoq-intelligence`, against real depot data or a
clean-world simulator.

**What IS clean is the deterministic boundary**, and that is what `learn.py`
reconciles:

- **Refusals** — the shield's "not allowable because of X" is *law* (allowability),
  not a decision outcome. `reconcile_refusals` classifies every production
  `reason_code` (migration 0086's ten-code vocabulary) into `transient` /
  `live_world` / `solver_gap`, flags anomalies (a solver_gap on any occurrence;
  a live_world on entity repetition), and emits **learned constraints** that plug
  straight into the next solve: `block_points`, `refresh_occupancy`,
  `reconcile_frame`, `fix_emitter`, `tighten_capacity`, `vehicle_override`.
- **Intractability** — `diagnose_solver` maps a solver status (INFEASIBLE /
  UNKNOWN / MODEL_INVALID / …) to its next action: enable rejection, raise the
  deterministic budget, retain the previous plan, or fix the model.

Both are pure functions of their arguments (never read the database), and the
closed loop is tested end-to-end: a faulted point learned from refusals is passed
as `blocked_points` and the solver routes around it (`intent/test_learn.py`).

**The remaining wiring** (not in this module, by design): an offline job reads
`ottoq_vehicle_commands.reason_code` (shield output, clean) and feeds
`reconcile_refusals`; the resulting constraints become the next propose's
`blocked_points` / capacity. That is a deployment concern, not a kernel change.

## The honest gap (what is NOT yet wired)

This artifact is the *specification* of the full objective. The solver currently
implements three of the eleven objectives as solver terms (tardiness = the
readiness floor, peak = the energy lever, flow = the throughput/dwell lever),
plus `service_completion` as a shield-enforced hard deadline. Wiring the
remaining objectives (deadhead, staging, staff, degradation, risk_hedge as
solver terms) is follow-on work, one objective at a time. The artifact makes
that wiring orderable and auditable instead of ad hoc. Every objective declares
its `solver_wiring` status so the gap is visible, not hidden.

## Robotaxi-first, multi-OEM

The taxonomy is robotaxi-first (the market). Multi-OEM is expressed in Tier 3:
per-OEM charge curves, battery chemistries, and sensor-suite calibration
cadences are constraint data, not objectives. The objective structure itself is
sector-agnostic — a mining pack or vertiport pack declares the same objectives,
different constraints (SEPARATION.md's kernel-purity test).
