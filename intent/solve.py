"""The pass sequencer — turn an ActiveIntent into an ordered solver pass list.

The intent declares eleven objectives. The SOLVER currently has variable terms
for exactly two of them. This module is the single place that truth lives: it
maps each objective to the solver pass that realizes it (or to None when no
variable term exists yet), then turns a resolved intent into the ordered,
deduplicated pass sequence the lexicographic solver should run.

THE HONEST CAPABILITY MAP — read this before assuming the regime "does
something". As of this writing:

  * readiness            -> min_tardy   (the floor: never strand an asset)
  * service_completion   -> (shield)     (must-by is a hard deadline the
                                          52-rule shield enforces; it is not a
                                          solver pass)
  * throughput           -> min_flow    (dwell/turnaround: finish vehicles
                                          soonest — the throughput lever)
  * dwell                -> min_flow    (same lever — deduped)
  * energy_cost          -> min_peak    (the demand-charge lever)
  * bess_peak_shave      -> min_peak    (same lever — deduped)

Everything else (deadhead, staging, staff, degradation, risk_hedge) has NO
variable solver term yet. The intent declares it and this map names it as
unmodeled, so the gap is visible at runtime rather than silently ignored.
Adding a pass is a one-line change here plus the model work, never a
re-architecture.

Consequence, stated plainly: with three variable passes available (min_tardy,
min_peak, min_flow) and the floors always first, the regime now genuinely
reorders the soft passes. dispatch_rush and demand_surge put min_flow before
min_peak (get vehicles out fast, spend energy); grid_peak and overnight put
min_peak first (flatten the demand charge); steady_state runs
(min_tardy, min_peak, min_flow). The schedule is now a function of the regime,
which is the point of the intent layer.
"""

from __future__ import annotations

from intent.intent import ActiveIntent

#: objective key -> solver pass mode, or None when no variable term exists.
#: "shield" marks objectives enforced by the deterministic shield as hard
#: constraints rather than optimized by a solver pass.
SOLVER_PASS: dict[str, str | None] = {
    "readiness": "min_tardy",
    "service_completion": "shield",
    "throughput": "min_flow",
    "energy_cost": "min_peak",
    "bess_peak_shave": "min_peak",
    "degradation": None,
    "dwell": "min_flow",
    "deadhead": None,
    "staging": None,
    "staff": None,
    "risk_hedge": None,
}


def pass_sequence(active: ActiveIntent) -> tuple[str, ...]:
    """The ordered, deduplicated solver pass modes for an active intent.

    Only objectives with a real solver pass are emitted, in priority order.
    Shield-enforced and unmodeled objectives are skipped — they are enforced
    elsewhere or pending a model extension (see `unmodeled`).
    """
    seen: set[str] = set()
    out: list[str] = []
    for key in active.priority:
        mode = SOLVER_PASS.get(key)
        if mode is not None and mode != "shield" and mode not in seen:
            seen.add(mode)
            out.append(mode)
    return tuple(out)


def unmodeled(active: ActiveIntent) -> tuple[str, ...]:
    """Objectives in priority order that have NO variable solver term.

    The honest gap, made visible: these are declared in the intent and present
    in this regime's priority, but the solver cannot optimize them yet. A
    caller that wants to log "I prioritized throughput but have no pass for it"
    reads this tuple rather than guessing.
    """
    seen: set[str] = set()
    out: list[str] = []
    for key in active.priority:
        if SOLVER_PASS.get(key) is None and key not in seen:
            seen.add(key)
            out.append(key)
    return tuple(out)


def shielded(active: ActiveIntent) -> tuple[str, ...]:
    """Objectives enforced by the deterministic shield, in priority order."""
    seen: set[str] = set()
    out: list[str] = []
    for key in active.priority:
        if SOLVER_PASS.get(key) == "shield" and key not in seen:
            seen.add(key)
            out.append(key)
    return tuple(out)
