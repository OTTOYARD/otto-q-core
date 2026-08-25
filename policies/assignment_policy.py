"""C5 — AssignmentPolicy: one interface over every scheduling policy.

    AssignmentPolicy { name; decide(state, arrivals) -> [Assignment] }

Wraps, in one comparable shape: FIFO, greedy, the local decide path (as-is
reduction), and the C4 CP-SAT prototype. The CRN discipline of ottoq_ab_runs is
preserved exactly: ONE scenario draw per seed, shared verbatim by every policy
(paired comparison), and the policies consume no randomness of their own — the
statistical spine of every future claim.

`otto_q_asis` is a faithful REDUCTION of the live cursor, not the SQL itself:
its ordering and gating rules are transcribed from public.ottoq_decide_tick
section (3) and the dcfc_first policy (db/fn_current/, md5-stamped 2026-08-19):
candidates ordered by urgency then lowest-SoC then id; DCFC preferred below the
plug-target threshold, L2 otherwise; earliest-available capable point; the
production disposer remains the SQL function.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "solvers" / "cpsat"))
from model import build_and_solve, charge_segments  # noqa: E402


@dataclass(frozen=True)
class Assignment:
    aid: str
    point_id: str
    start: int          # minutes from t0

    def as_dict(self):
        return {"aid": self.aid, "point_id": self.point_id, "start": self.start}


class AssignmentPolicy:
    name: str = "abstract"

    def decide(self, state: "HarnessState", arrivals: list) -> list[Assignment]:
        raise NotImplementedError


# ---------------------------------------------------------------------------
# Helpers shared by the myopic policies (no randomness — CRN-safe)
# ---------------------------------------------------------------------------

def _chain_minutes(sc, asset, point):
    return sum(s["minutes"] for s in charge_segments(sc, asset, point["kw"]))


def _earliest_start(state, asset, point):
    return max(asset.arrival_min, state.point_free_at(point["id"]))


class FifoPolicy(AssignmentPolicy):
    """Strict arrival order; first capable point that frees earliest
    (ties broken by scenario point order — deterministic)."""
    name = "fifo"

    def decide(self, state, arrivals):
        out = []
        for asset in sorted(arrivals, key=lambda a: (a.arrival_min, a.aid)):
            best = min(state.charge_points(asset),
                       key=lambda p: (_earliest_start(state, asset, p),
                                      state.point_order(p["id"])))
            start = _earliest_start(state, asset, best)
            state.book_charge(asset, best, start)
            out.append(Assignment(asset.aid, best["id"], start))
        return out


class GreedyPolicy(AssignmentPolicy):
    """Myopic per-vehicle: the point minimizing THIS vehicle's charge end."""
    name = "greedy"

    def decide(self, state, arrivals):
        out = []
        for asset in sorted(arrivals, key=lambda a: (a.arrival_min, a.aid)):
            best = min(state.charge_points(asset),
                       key=lambda p: (_earliest_start(state, asset, p)
                                      + _chain_minutes(state.sc, asset, p),
                                      state.point_order(p["id"])))
            start = _earliest_start(state, asset, best)
            state.book_charge(asset, best, start)
            out.append(Assignment(asset.aid, best["id"], start))
        return out


class OttoQAsIsPolicy(AssignmentPolicy):
    """AS-IS reduction of ottoq_decide_tick (3) + dcfc_first.

    Ordering: immediate-dispatch urgency first (none in the reduced scenario),
    then LOWEST SoC first, then id — verbatim from the live cursor's ORDER BY.
    Point choice: dcfc_first below the plug target threshold (SoC < 55 prefers
    DCFC; the live committed-kW taper's own breakpoint), else the
    earliest-available capable point. Enact-and-record is one act (the harness
    books in the same step — the P0 invariant).
    """
    name = "otto_q_asis"
    #: DELIBERATELY NOT capability-aware. This class is a faithful reduction
    #: of the live robotaxi cursor, which has no multi-class capability
    #: concept; teaching the reduction things the production function does
    #: not know would make it stop being a reduction. Multimodal comparisons
    #: therefore EXCLUDE it with a stated reason instead of letting it book
    #: aircraft onto car chargers and score noise.
    PLUG_TARGET_SOC = 55

    def decide(self, state, arrivals):
        out = []
        for asset in sorted(arrivals, key=lambda a: (a.soc, a.aid)):
            dcfc = [p for p in state.charge_points() if p["kind"] == "dcfc"]
            l2 = [p for p in state.charge_points() if p["kind"] == "l2"]
            pref = dcfc + l2 if asset.soc < self.PLUG_TARGET_SOC else l2 + dcfc
            best = min(pref, key=lambda p: (_earliest_start(state, asset, p),
                                            state.point_order(p["id"])))
            start = _earliest_start(state, asset, best)
            state.book_charge(asset, best, start)
            out.append(Assignment(asset.aid, best["id"], start))
        return out


class CpSatPolicy(AssignmentPolicy):
    """The C4 prototype as a policy: one joint solve, assignments read off the
    plan. Deterministic under the scenario seed (single worker, fixed seed)."""
    name = "cpsat"

    def decide(self, state, arrivals):
        plan = build_and_solve(state.sc)
        starts = {}
        for a in plan["assets"]:
            for op in a["ops"]:
                if op["op"] == "charge":
                    starts[a["aid"]] = (op["point"], op["start"])
        out = []
        for asset in sorted(arrivals, key=lambda a: (starts[a.aid][1], a.aid)):
            point_id, start = starts[asset.aid]
            point = state.point(point_id)
            state.book_charge(asset, point, start)
            out.append(Assignment(asset.aid, point_id, start))
        return out


class WaymoStagingPolicy(AssignmentPolicy):
    """PARKED — do not implement, do not run.

    TODO(C5, parked): staged-dispatch policy per Waymo patent US 12,545,288 B2
    ("pre-positioning of autonomous vehicles at staging areas"). Kept as a stub
    so the comparison harness has the slot; implementing it is a deliberate
    product/legal decision, not an engineering default. Compiles; refuses to run.
    """
    name = "waymo_staging"

    def decide(self, state, arrivals):
        raise NotImplementedError(
            "WaymoStagingPolicy is PARKED (US 12,545,288 B2). "
            "It deliberately refuses to run; see C5 notes in policies/README.md.")


ALL_POLICIES = [FifoPolicy, GreedyPolicy, OttoQAsIsPolicy, CpSatPolicy]
PARKED_POLICIES = [WaymoStagingPolicy]
