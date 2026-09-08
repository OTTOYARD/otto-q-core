"""The intent-driven orchestrator — the regime reorders the lexicographic passes.

ForwardOrchestratorPolicy hardcodes the two-pass (min_tardy, min_peak) solve and
its frozen artifact pins that. This module is where the commander's intent
actually drives the solver: resolve the active regime from (hour, signals), map
its priority to an ordered pass list via the intent sequencer, and run that list
through the generalized lexicographic chain (forward.lexicographic_solve).

The third lever, min_flow (dwell/turnaround), is what makes the regime mean
something. dispatch_rush and demand_surge put throughput before energy (get
vehicles out fast, spend energy); grid_peak and overnight put energy first
(flatten the demand charge); steady_state runs (tardy, peak, flow). The
readiness floor is structural — the resolver prepends it to every regime, so
min_tardy is always pass 1.

This is a POLICY layer module: it reads the intent artifact (declared doctrine)
and the scenario (declared world), and never writes state. It is the seam where
"tonight is tight, pull this wash forward" becomes an ordered objective the
solver acts on.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from assignment_policy import Assignment, AssignmentPolicy          # noqa: E402
from forward import lexicographic_solve                             # noqa: E402
from intent.intent import ActiveIntent, load_intent, resolve_intent  # noqa: E402
from intent.solve import pass_sequence                              # noqa: E402

#: Loaded once: the intent is doctrine, verified by fingerprint at load, and
#: identical for every solve in the process. Reading it per-tick would re-verify
#: the same bytes for no reason.
#:
#: IT IS A DEFAULT, NOT A SINGLETON (finding L-52). Every function here takes an
#: `intent=` override; what was broken is that the two callers that matter --
#: forward_proposer.propose() and RegimeOrchestratorPolicy -- did not offer one,
#: so a process could hold exactly one doctrine and the kernel default is
#: robotaxi-flavoured in places a pack then reads unconditionally (its
#: service_completion metric names wash/tire/brake/software/inspection/
#: calibration; its staff wiring says "a packing objective in the robotaxi
#: pack"). A mining pack cannot conform to a kernel that only knows one sector's
#: doctrine, so the override is threaded end to end.
INTENT = load_intent()

#: Per-pack intent artifacts, keyed by RESOLVED PATH. Each is fingerprint-checked
#: once at load, like the kernel default, and reused thereafter.
_PACK_INTENTS: dict[str, object] = {}

#: Where a pack's own doctrine lives, beside the pack file it belongs to.
PACK_INTENT_DIR = HERE.parent / "conformance" / "packs"


def pack_intent_path(pack_id: str) -> Path:
    """The artifact a pack MAY declare; absent means the kernel default."""
    return PACK_INTENT_DIR / f"{pack_id}_intent_v1.json"


def intent_for_pack(pack_id: str | None):
    """The pack's own intent if it ships one, else the kernel default.

    Falling back is deliberate and is what keeps a pack DECLARATIVE: a pack that
    is content with the kernel's priority orderings ships no artifact and gets
    them, and a pack whose doctrine genuinely differs states it as data rather
    than as a kernel patch. PACK_SPEC.md 2 records the file name.
    """
    if not pack_id:
        return INTENT
    path = pack_intent_path(pack_id)
    if not path.exists():
        return INTENT
    key = str(path)
    if key not in _PACK_INTENTS:
        _PACK_INTENTS[key] = load_intent(path)
    return _PACK_INTENTS[key]


def resolve_active(hour_of_day: int, signals: frozenset = frozenset(),
                   intent=None) -> ActiveIntent:
    """Resolve the active regime for the given clock and signals."""
    return resolve_intent(intent or INTENT, hour_of_day=hour_of_day,
                          signals=signals)


def intent_orchestrate(sc, hour_of_day: int = 0,
                       signals: frozenset = frozenset(), *,
                       intent=None, budget=None) -> tuple[dict, ActiveIntent, dict]:
    """Resolve the regime and run its lexicographic chain against `sc`.

    Returns (plan, active_intent, optima) — the final schedule, the resolved
    regime (so the caller can log WHY this order was chosen), and the held
    optimum per pass. Pure: reads declared doctrine and world, writes nothing.
    """
    active = resolve_active(hour_of_day, signals, intent=intent)
    modes = pass_sequence(active)
    plan, optima = lexicographic_solve(sc, modes, budget=budget)
    return plan, active, optima


class RegimeOrchestratorPolicy(AssignmentPolicy):
    """The intent-driven orchestrator as a policy — the regime reorders the passes.

    Not registered in ALL_POLICIES for the same reason ForwardOrchestratorPolicy
    is not: the frozen comparison artifact is byte-asserted, and adding a run
    would silently regenerate it. The regime policy is exercised directly.
    """

    name = "regime"

    def __init__(self, hour_of_day: int = 0, signals: frozenset = frozenset(),
                 budget: dict | None = None, intent=None):
        self.hour_of_day = hour_of_day
        self.signals = signals
        self.budget = budget
        #: None means the kernel default, resolved at decide() time so a caller
        #: may also pass a pack's intent (see intent_for_pack).
        self.intent = intent

    def decide(self, state, arrivals):
        plan, _active, _optima = intent_orchestrate(
            state.sc, self.hour_of_day, self.signals, budget=self.budget,
            intent=self.intent)
        starts = {}
        for a in plan["assets"]:
            for op in a["ops"]:
                if op["op"] == "charge":
                    starts[a["aid"]] = (op["point"], op["start"])
        #: Same as ForwardOrchestratorPolicy: a rejected asset has no start and
        #: gets no assignment, rather than a KeyError on a supported budget key
        #: (finding L-21).
        placed = [a for a in arrivals if a.aid in starts]
        out = []
        for asset in sorted(placed, key=lambda a: (starts[a.aid][1], a.aid)):
            point_id, start = starts[asset.aid]
            state.book_charge(asset, state.point(point_id), start)
            out.append(Assignment(asset.aid, point_id, start))
        return out
