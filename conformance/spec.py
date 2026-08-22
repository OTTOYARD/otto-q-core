"""C11 — the pack schema and the CLOSED kernel-mechanism registry.

The registry is what makes this a falsification instrument rather than a rubber
stamp: a pack author cannot add a mechanism. Every entry below names something the
engine demonstrably has, with the evidence for it, so a reader can check the claim
rather than take it. If a sector needs something not in this list, the honest
outcomes are to extend the kernel and say so, or to conclude the platform thesis is
wrong for that sector — CLAUDE.md 2.2 calls that a finding to escalate, not absorb.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


# mechanism -> the concrete thing in the engine that implements it.
KERNEL_MECHANISMS: dict[str, str] = {
    "capability_pair":
        "(asset_class, operation) pairs on a ServicePoint — CLAUDE.md 2.3; "
        "12,740 pairs seeded by migration 0043",
    "exclusive_occupancy":
        "ottoq_stall_bookings EXCLUDE constraint — double-booking is physically "
        "impossible (CLAUDE.md 2.6 'assignment plus verification, always')",
    "parallel_within_point":
        "concurrency within a service point — CLAUDE.md 2.3; "
        "ottoq_operation_catalog.parallel_with_charge",
    "site_power_cap":
        "shared site power cap enforced per tick — ottoq_claim_tick_kw; "
        "peak_site_kw is canonical KPI #3",
    "min_gap_on_point":
        "minimum-gap constraint ON THE SERVICE POINT — CLAUDE.md 2.5, "
        "DCFC cooldown, 18 min in the throughput model",
    "movement_as_operation":
        "inter-point moves are scheduled operations with duration that consume "
        "path resources — CLAUDE.md 2.3",
    "threshold_ladder":
        "multi-signal first-hit-wins recall trigger — RecallDecision (2.7), "
        "recall/recall_decision.py, reduced from ottoq_evaluate_return_need",
    "work_side_refusal":
        "work-side refusal is a first-class event triggering re-solve, never an "
        "error — CLAUDE.md 2.7; recall/ refuse(); C8 refusal scenario",
    "tariff_window":
        "ServiceTariff per (asset_class, operation, operator, window) — "
        "ottoq_service_tariffs",
    "forward_power_schedule":
        "schedule-shaped power publication — CLAUDE.md 2.5 boundary; "
        "adapters/base.py ForwardPowerSchedule (C10 Law 2)",
    "sdr_termination":
        "every completed operation terminates in a ServiceDetailRecord — "
        "CLAUDE.md 2.6, made structural by migration 0043",
}

FINDING_CLASSES = ("DECLARATIVE", "SOLVER_CHANGE", "OUT_OF_SCOPE")
PACK_STATUSES = ("reference", "build", "paper")


class PackValidationError(ValueError):
    """Raised when a pack file does not conform to PACK_SPEC.md."""


@dataclass(frozen=True)
class Operation:
    operation_code: str
    display_name: str
    category: str
    parallel_with_charge: bool = False
    is_movement: bool = False
    energy_bearing: bool = False
    emits_sdr: bool = True
    typical_min: float | None = None
    peak_kw: float | None = None


@dataclass(frozen=True)
class ServicePoint:
    point_type: str
    capabilities: tuple[tuple[str, str], ...]      # (asset_class, operation)
    exclusive: bool = True
    min_gap_min: float | None = None
    count: int = 1


@dataclass(frozen=True)
class Constraint:
    code: str
    description: str
    mechanism: str | None                          # None = author says kernel cannot
    finding_class: str | None = None               # required iff mechanism is None
    note: str = ""


@dataclass(frozen=True)
class Pack:
    pack_id: str
    status: str
    source: str
    asset_classes: tuple[dict[str, Any], ...]
    operations: tuple[Operation, ...]
    service_points: tuple[ServicePoint, ...]
    constraints: tuple[Constraint, ...]

    def operation(self, code: str) -> Operation | None:
        return next((o for o in self.operations if o.operation_code == code), None)


def validate(pack: Pack) -> list[str]:
    """Return a list of PACK_SPEC violations. Empty list == the pack loads."""
    errors: list[str] = []

    if pack.status not in PACK_STATUSES:
        errors.append(f"status {pack.status!r} not one of {PACK_STATUSES}")
    if not pack.source.strip():
        errors.append(
            "source is empty. A pack whose source is invented is not a pack; "
            "it is a guess with a schema (PACK_SPEC §2)."
        )

    class_codes = {a["code"] for a in pack.asset_classes}
    op_codes = {o.operation_code for o in pack.operations}

    if len(op_codes) != len(pack.operations):
        errors.append("duplicate operation_code")

    # SDR rule: only movement may skip the SDR (CLAUDE.md 2.6).
    for o in pack.operations:
        if not o.emits_sdr and not o.is_movement:
            errors.append(
                f"operation {o.operation_code!r} sets emits_sdr=false but is not a "
                f"movement. CLAUDE.md 2.6 requires every completed operation to "
                f"terminate in an SDR; movement is the only exception."
            )

    # Capability pairs must reference declared classes and operations.
    for sp in pack.service_points:
        for cls, op in sp.capabilities:
            if cls not in class_codes:
                errors.append(f"point {sp.point_type!r} capability names undeclared asset class {cls!r}")
            if op not in op_codes:
                errors.append(f"point {sp.point_type!r} capability names undeclared operation {op!r}")

    # Every non-movement operation needs somewhere to happen.
    capable_ops = {op for sp in pack.service_points for _, op in sp.capabilities}
    for o in pack.operations:
        if not o.is_movement and o.operation_code not in capable_ops:
            errors.append(
                f"operation {o.operation_code!r} has no service point declaring it — "
                f"it could never be scheduled (PACK_SPEC §3 invariant 3)."
            )

    # Constraints: mechanism must be registry-known, or null WITH a finding class.
    for c in pack.constraints:
        if c.mechanism is None:
            if c.finding_class not in FINDING_CLASSES:
                errors.append(
                    f"constraint {c.code!r} declares no mechanism, so it must carry a "
                    f"finding_class in {FINDING_CLASSES} — a null mechanism is the "
                    f"FINDING, not an unfilled field (PACK_SPEC §2)."
                )
        elif c.mechanism not in KERNEL_MECHANISMS:
            errors.append(
                f"constraint {c.code!r} names mechanism {c.mechanism!r}, which is not "
                f"in the closed registry. A pack author cannot invent a mechanism — "
                f"that is what makes this a falsification test (PACK_SPEC §1)."
            )
    return errors


def load(doc: dict[str, Any]) -> Pack:
    """Build a Pack from a parsed JSON document. Raises on structural problems."""
    try:
        return Pack(
            pack_id=doc["pack_id"],
            status=doc["status"],
            source=doc["source"],
            asset_classes=tuple(doc["asset_classes"]),
            operations=tuple(Operation(**o) for o in doc["operations"]),
            service_points=tuple(
                ServicePoint(
                    point_type=sp["point_type"],
                    capabilities=tuple(tuple(p) for p in sp["capabilities"]),
                    exclusive=sp.get("exclusive", True),
                    min_gap_min=sp.get("min_gap_min"),
                    count=sp.get("count", 1),
                )
                for sp in doc["service_points"]
            ),
            constraints=tuple(Constraint(**c) for c in doc["constraints"]),
        )
    except (KeyError, TypeError) as exc:
        raise PackValidationError(f"pack does not match PACK_SPEC §2: {exc}") from exc
