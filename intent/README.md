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
