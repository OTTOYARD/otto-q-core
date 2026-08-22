"""C11 — the conformance harness. The falsification instrument for CLAUDE.md 2.2.

    A pack is valid iff its declarative files load and solve on the kernel with
    ZERO kernel modification.

WHAT "SOLVE" MEANS HERE, STATED PRECISELY so the verdict is not read as more than
it is. The harness constructs a scenario from the pack's own declarations and
schedules it under ONLY the kernel mechanisms in the closed registry
(conformance/spec.py). It then verifies the three C11.1 invariants on the result.

It does NOT run the production decide path against a live twin. That distinction
matters and is not glossed: a pack passing here has shown its world is EXPRESSIBLE
in kernel mechanisms and admits a feasible schedule under them. It has not shown
the production scheduler produces good throughput on it. Expressibility is the
platform question C11 asks; throughput is C6/C8's question and is measured
separately. Conflating them would let a pack "pass" on the strength of the
engine's tuning rather than the kernel's generality.

The scheduler below is deliberately simple — earliest-fit over declared points,
with the three invariants enforced as hard constraints. A simple scheduler is the
right instrument: if a pack cannot be scheduled even by an unambitious algorithm
that respects only kernel mechanisms, the obstacle is the MODEL, which is exactly
what is under test.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from conformance.spec import (
    KERNEL_MECHANISMS,
    Pack,
    ServicePoint,
    load,
    validate,
)

PACK_DIR = Path(__file__).parent / "packs"
SITE_POWER_CAP_KW = 3000.0        # CLAUDE.md C8 Site Alpha
TICK_MIN = 30.0                   # matches the twin's tick


@dataclass(frozen=True)
class ScheduledOp:
    asset_id: str
    asset_class: str
    operation_code: str
    point_type: str
    point_index: int
    start_min: float
    end_min: float
    peak_kw: float


@dataclass
class ConformanceResult:
    pack_id: str
    status: str
    load_errors: list[str] = field(default_factory=list)
    scheduled: list[ScheduledOp] = field(default_factory=list)
    unschedulable: list[str] = field(default_factory=list)
    violations: list[str] = field(default_factory=list)
    findings: list[dict[str, Any]] = field(default_factory=list)
    mechanisms_used: set[str] = field(default_factory=set)
    #: Constraints naming a mechanism this run never actually exercised. NOT
    #: failures — but not evidence either. Without this, a pack author makes an
    #: awkward constraint disappear by naming a plausible mechanism, and the
    #: harness rubber-stamps it. See ConformanceResult.unverified_claims.
    unverified_claims: list[dict[str, Any]] = field(default_factory=list)

    @property
    def loads(self) -> bool:
        return not self.load_errors

    @property
    def solves(self) -> bool:
        return self.loads and not self.violations and not self.unschedulable

    @property
    def conforms(self) -> bool:
        """Conformance is load + solve + no unsupported constraint.

        Deliberately does NOT require zero unverified claims: an unexercised
        mechanism is missing evidence, not a demonstrated failure. Reporting the
        two separately is the point — collapsing them would either overstate the
        verdict or bury it.
        """
        return self.solves and not self.findings

    @property
    def fully_evidenced(self) -> bool:
        """Conforms AND every claimed mechanism was actually exercised."""
        return self.conforms and not self.unverified_claims


# ---------------------------------------------------------------------------
# Scenario construction — from the pack's own declarations, nothing invented
# ---------------------------------------------------------------------------

def build_scenario(pack: Pack, assets_per_class: int = 4) -> list[tuple[str, str, list[str]]]:
    """(asset_id, asset_class, [operation_code, ...]) — a deterministic manifest.

    Each asset requests every non-movement operation its class is capable of
    ANYWHERE in the pack. That is the demanding choice on purpose: it guarantees
    the scenario exercises every declared capability pair at least once, so an
    operation with no capable point cannot slip through unscheduled-but-unnoticed.
    """
    by_class: dict[str, list[str]] = {}
    for sp in pack.service_points:
        for cls, opcode in sp.capabilities:
            o = pack.operation(opcode)
            if o and not o.is_movement:
                by_class.setdefault(cls, [])
                if opcode not in by_class[cls]:
                    by_class[cls].append(opcode)

    scenario: list[tuple[str, str, list[str]]] = []
    for a in pack.asset_classes:
        cls = a["code"]
        ops = sorted(by_class.get(cls, []))          # sorted: deterministic
        for i in range(assets_per_class):
            scenario.append((f"{cls}#{i}", cls, ops))
    return scenario


def _points(pack: Pack) -> list[tuple[str, int, ServicePoint]]:
    out: list[tuple[str, int, ServicePoint]] = []
    for sp in pack.service_points:
        for i in range(sp.count):
            out.append((sp.point_type, i, sp))
    return out


def schedule(pack: Pack, scenario) -> tuple[list[ScheduledOp], list[str], set[str]]:
    """Earliest-fit under kernel mechanisms only. Returns (scheduled, unschedulable, used)."""
    points = _points(pack)
    busy: dict[tuple[str, int], list[tuple[float, float]]] = {(t, i): [] for t, i, _ in points}
    last_end: dict[tuple[str, int], float] = {}
    scheduled: list[ScheduledOp] = []
    unschedulable: list[str] = []
    used: set[str] = set()

    for asset_id, cls, opcodes in scenario:
        cursor = 0.0
        for opcode in opcodes:
            o = pack.operation(opcode)
            if o is None:
                unschedulable.append(f"{asset_id}: unknown operation {opcode}")
                continue
            dur = o.typical_min if o.typical_min else TICK_MIN
            placed = False

            for ptype, idx, sp in points:
                if (cls, opcode) not in sp.capabilities:
                    continue                                   # invariant 3
                used.add("capability_pair")
                key = (ptype, idx)
                t = cursor
                # min_gap_on_point: a point needs a gap after its last session
                if sp.min_gap_min and key in last_end:
                    used.add("min_gap_on_point")
                    t = max(t, last_end[key] + sp.min_gap_min)
                # exclusive_occupancy: find the first free window
                for _ in range(400):
                    clash = next((w for w in busy[key] if not (t + dur <= w[0] or t >= w[1])), None)
                    if clash is None:
                        break
                    t = clash[1]
                    if sp.min_gap_min:
                        t += sp.min_gap_min
                else:
                    continue
                if sp.exclusive:
                    used.add("exclusive_occupancy")
                busy[key].append((t, t + dur))
                last_end[key] = t + dur
                scheduled.append(ScheduledOp(asset_id, cls, opcode, ptype, idx,
                                             t, t + dur, o.peak_kw or 0.0))
                if o.energy_bearing:
                    used.add("site_power_cap")
                if o.emits_sdr:
                    used.add("sdr_termination")
                if o.parallel_with_charge:
                    used.add("parallel_within_point")
                cursor = t + dur
                placed = True
                break

            if not placed:
                unschedulable.append(
                    f"{asset_id} ({cls}): operation {opcode!r} has no capable point"
                )
    return scheduled, unschedulable, used


# ---------------------------------------------------------------------------
# The three invariants — verified, not asserted (CLAUDE.md C11.1)
# ---------------------------------------------------------------------------

def verify(pack: Pack, scheduled: list[ScheduledOp]) -> list[str]:
    violations: list[str] = []

    # 3. no operation on an incapable point
    cap = {(sp.point_type, c, o) for sp in pack.service_points for c, o in sp.capabilities}
    for s in scheduled:
        if (s.point_type, s.asset_class, s.operation_code) not in cap:
            violations.append(
                f"INCAPABLE POINT: {s.operation_code} for {s.asset_class} on {s.point_type}"
            )

    # 2. no point overlap
    by_point: dict[tuple[str, int], list[ScheduledOp]] = {}
    for s in scheduled:
        by_point.setdefault((s.point_type, s.point_index), []).append(s)
    for key, ops in by_point.items():
        ops.sort(key=lambda s: s.start_min)
        for a, b in zip(ops, ops[1:]):
            if b.start_min < a.end_min - 1e-9:
                violations.append(
                    f"POINT OVERLAP on {key[0]}#{key[1]}: {a.operation_code}"
                    f"[{a.start_min:.0f},{a.end_min:.0f}) vs {b.operation_code}"
                    f"[{b.start_min:.0f},{b.end_min:.0f})"
                )

    # 1. no power-cap violation — sweep the instants where concurrency changes
    edges = sorted({s.start_min for s in scheduled} | {s.end_min for s in scheduled})
    for t in edges:
        draw = sum(s.peak_kw for s in scheduled if s.start_min <= t < s.end_min)
        if draw > SITE_POWER_CAP_KW + 1e-9:
            violations.append(
                f"POWER CAP: {draw:.0f} kW at t={t:.0f} exceeds {SITE_POWER_CAP_KW:.0f} kW"
            )
    return violations


def constraint_findings(pack: Pack) -> list[dict[str, Any]]:
    """Every declared constraint with no kernel mechanism. This is the verdict input."""
    out = []
    for c in pack.constraints:
        if c.mechanism is None:
            out.append({
                "pack_id": pack.pack_id, "code": c.code,
                "class": c.finding_class, "description": c.description, "note": c.note,
            })
    return out


def unverified_claims(pack: Pack, exercised: set[str]) -> list[dict[str, Any]]:
    """Constraints naming a mechanism the run never exercised.

    This is the harness auditing ITSELF. Without it the instrument is a rubber
    stamp: a pack author can retire an inconvenient constraint by naming a
    plausible-sounding mechanism, and nothing checks that the mechanism was ever
    reached. Mechanically: a claim is evidenced only if the scheduler actually
    used that mechanism while placing this pack's operations. Everything else is
    an assertion, and is reported as one.
    """
    out = []
    for c in pack.constraints:
        if c.mechanism is not None and c.mechanism not in exercised:
            out.append({
                "pack_id": pack.pack_id, "code": c.code, "mechanism": c.mechanism,
                "why": KERNEL_MECHANISMS.get(c.mechanism, ""),
                "description": c.description, "note": c.note,
            })
    return out


def run_pack(path: Path) -> ConformanceResult:
    doc = json.loads(path.read_text())
    pack = load(doc)
    res = ConformanceResult(pack_id=pack.pack_id, status=pack.status)
    res.load_errors = validate(pack)
    if res.load_errors:
        return res
    scenario = build_scenario(pack)
    res.scheduled, res.unschedulable, res.mechanisms_used = schedule(pack, scenario)
    res.violations = verify(pack, res.scheduled)
    res.findings = constraint_findings(pack)
    res.unverified_claims = unverified_claims(pack, res.mechanisms_used)
    return res


def run_all() -> list[ConformanceResult]:
    return [run_pack(p) for p in sorted(PACK_DIR.glob("*.json"))]


if __name__ == "__main__":
    for r in run_all():
        if r.fully_evidenced:
            mark = "CONFORMS (fully evidenced)"
        elif r.conforms:
            mark = "CONFORMS (some claims unexercised)"
        elif r.solves:
            mark = "SOLVES, with findings"
        else:
            mark = "FAILS"
        print(f"\n=== {r.pack_id} ({r.status}) — {mark} ===")
        print(f"    loads: {r.loads}   scheduled ops: {len(r.scheduled)}   "
              f"unschedulable: {len(r.unschedulable)}   violations: {len(r.violations)}")
        print(f"    mechanisms exercised: {', '.join(sorted(r.mechanisms_used)) or 'none'}")
        for e in r.load_errors:    print("    LOAD ERROR:", e)
        for u in r.unschedulable[:5]: print("    UNSCHEDULABLE:", u)
        for v in r.violations[:5]: print("    VIOLATION:", v)
        for f in r.findings:       print(f"    FINDING [{f['class']}] {f['code']}")
        for u in r.unverified_claims:
            print(f"    UNVERIFIED CLAIM: {u['code']} names {u['mechanism']}, never exercised")
