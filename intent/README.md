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

This is the mechanism that turns "tonight is tight, pull this wash forward now"
(forecast-driven) into an objective the solver can act on.

## The honest gap (what is NOT yet wired)

This artifact is the *specification* of the full objective. The solver currently
implements two of the eleven objectives as objective modes (tardiness = the
readiness floor, peak = the energy lever). Wiring the remaining objectives
(wash timing, staff, degradation as solver terms) is follow-on work, one
objective at a time. The artifact makes that wiring orderable and auditable
instead of ad hoc. Every objective declares its `solver_wiring` status so the
gap is visible, not hidden.

## Robotaxi-first, multi-OEM

The taxonomy is robotaxi-first (the market). Multi-OEM is expressed in Tier 3:
per-OEM charge curves, battery chemistries, and sensor-suite calibration
cadences are constraint data, not objectives. The objective structure itself is
sector-agnostic — a mining pack or vertiport pack declares the same objectives,
different constraints (SEPARATION.md's kernel-purity test).
