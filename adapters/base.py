"""C10 — the adapter boundary. Two laws, enforced at import time.

CLAUDE.md 2.2 says sector-specific code lives ONLY inside adapters, and C10 says
the two laws must be "encoded in interface types so violation is a compile error."
Python has no compile step, so the strongest honest equivalent is used and named
as such: the laws are enforced by `__init_subclass__`, which runs when the class
statement executes. A violating adapter therefore fails at IMPORT, before any
instance exists and before any translation runs — the same practical guarantee a
compile error gives (you cannot ship it), reached by a different mechanism. It is
called import-time enforcement in this file and in ADAPTERS.md, never "compile
error", because the distinction is real.

    LAW 1 — ADAPTERS TRANSLATE, NEVER DECIDE.
    An adapter converts foreign words into kernel facts and kernel decisions into
    foreign words. It never chooses a stall, a time, an order, or a priority. The
    decide path disposes (CLAUDE.md 2.5, "agents propose, solver disposes"); an
    adapter is not even a proposer. Enforced three ways: the Protocol exposes
    exactly two directions and neither is handed site state; decision-verb method
    names are rejected; and inbound methods may not return kernel decisions.

    LAW 2 — POWER PUBLICATION IS SCHEDULE-SHAPED, NEVER REAL-TIME.
    Production interfaces publish forward demand schedules to site controllers and
    vendor EMS; OTTO-Q never issues a real-time setpoint to a physical inverter
    (CLAUDE.md 2.5, "Power publication boundary"). Enforced by construction: the
    ONLY power-bearing outbound type in this module is ForwardPowerSchedule, which
    has no instantaneous field, and any adapter-declared dataclass carrying a
    setpoint-shaped field name is rejected at import.

Why the laws are worth enforcing mechanically rather than by review: both are
easy to violate accidentally and expensive to violate silently. An adapter that
quietly picks a stall turns a sector pack into sector logic in the kernel, which
CLAUDE.md 2.2 calls a platform-thesis finding. An adapter that emits a setpoint
turns a planning system into a control system, with the liability that implies.
"""

from __future__ import annotations

import inspect
from dataclasses import dataclass, fields, is_dataclass
from typing import Any, Protocol, runtime_checkable


class AdapterLawViolation(TypeError):
    """Raised at class-creation time when an adapter breaks Law 1 or Law 2."""


# ---------------------------------------------------------------------------
# The vocabulary. Deliberately small: an adapter that needs a richer vocabulary
# is usually an adapter that is about to start deciding.
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class AssetFact:
    """INBOUND. Something the foreign system asserts is true about an asset.

    A fact, never a request. `soc_pct` is what the robot reports; it is not a
    claim that the robot should be charged. The kernel decides what facts mean.
    """
    asset_ref: str                      # foreign identity, verbatim
    observed_at: str                    # ISO8601, foreign clock, unconverted
    soc_pct: float | None = None
    faulted: bool | None = None
    blocked: bool | None = None
    position_ref: str | None = None     # foreign node/stall id, verbatim
    payload_ref: str | None = None
    extra: tuple[tuple[str, str], ...] = ()   # unmapped foreign fields, kept verbatim


@dataclass(frozen=True)
class ServiceIntent:
    """OUTBOUND. A kernel decision, awaiting translation into foreign words.

    The adapter receives this already decided. Every field is an instruction the
    kernel has already committed to; the adapter's only freedom is how to phrase
    it in the foreign protocol.
    """
    asset_ref: str
    operation_code: str                 # from ottoq_operation_catalog
    service_point_ref: str
    not_before: str                     # ISO8601
    not_after: str                      # ISO8601
    reason: str = ""


@dataclass(frozen=True)
class PowerPeriod:
    """One step of a forward schedule. A ceiling over an interval — not a target.

    `limit_kw` is the most the site may draw during the period. It is advisory to
    a controller that owns the actual hardware. There is deliberately no field for
    "draw exactly this much now": see Law 2.
    """
    start_offset_s: int                 # seconds from schedule start
    limit_kw: float


@dataclass(frozen=True)
class ForwardPowerSchedule:
    """OUTBOUND, and the ONLY power-bearing type this module defines.

    Shaped after a smart-charging profile (CLAUDE.md 2.6, ServiceProfile) and
    extended to non-energy resources. It always starts in the future and always
    has a duration: a schedule with neither is a setpoint wearing a costume.
    """
    start_at: str                       # ISO8601
    duration_s: int
    periods: tuple[PowerPeriod, ...]

    def __post_init__(self) -> None:
        if self.duration_s <= 0:
            raise AdapterLawViolation(
                "LAW 2: a forward schedule must have a positive duration; "
                "a zero-duration schedule is an instantaneous command."
            )
        if not self.periods:
            raise AdapterLawViolation(
                "LAW 2: a forward schedule must have at least one period."
            )


# ---------------------------------------------------------------------------
# The enforcement
# ---------------------------------------------------------------------------

# Verbs that mean "I chose". An adapter method may not be named any of these,
# nor start with one: `decide`, `decide_stall`, `choose_bay` all fail.
_DECISION_VERBS = frozenset({
    "decide", "assign", "schedule", "allocate", "choose", "select", "pick",
    "optimize", "optimise", "rank", "prioritize", "prioritise", "solve",
    "plan", "dispatch", "reserve", "book", "arbitrate",
})

# Field names that mean "do this now to this device".
_SETPOINT_FIELDS = frozenset({
    "setpoint", "setpoint_kw", "target_kw", "command_kw", "instantaneous_kw",
    "power_now_kw", "output_kw", "current_a", "voltage_v", "duty_cycle",
})


def _violates_decision_verb(name: str) -> bool:
    if name.startswith("_"):
        return False
    head = name.split("_", 1)[0].lower()
    return head in _DECISION_VERBS


class Adapter:
    """Base class every adapter must inherit. Enforcement lives in __init_subclass__.

    Subclasses implement `inbound()` and `outbound()` and nothing decision-shaped.
    Inheriting is not optional: it is the only thing that makes the laws bite.
    """

    #: Set by a subclass ONLY if it publishes power. Must be ForwardPowerSchedule.
    power_output_type: type | None = None

    def __init_subclass__(cls, **kwargs: Any) -> None:
        super().__init_subclass__(**kwargs)

        # --- LAW 1: no decision-shaped surface ---------------------------------
        for name, member in vars(cls).items():
            if not callable(member) and not isinstance(member, (staticmethod, classmethod)):
                continue
            if _violates_decision_verb(name):
                raise AdapterLawViolation(
                    f"LAW 1 (adapters translate, never decide): {cls.__name__}.{name}() "
                    f"is named for a decision. An adapter converts words; it does not "
                    f"choose stalls, times, orders or priorities — the decide path "
                    f"disposes (CLAUDE.md 2.5). Rename it to say what it TRANSLATES, "
                    f"or move the choice into the kernel where it can be audited."
                )

        # --- LAW 1, second edge: inbound may not carry decisions ---------------
        inbound = vars(cls).get("inbound")
        if inbound is not None and callable(inbound):
            ann = getattr(inbound, "__annotations__", {})
            ret = ann.get("return")
            if ret is not None and "ServiceIntent" in str(ret):
                raise AdapterLawViolation(
                    f"LAW 1: {cls.__name__}.inbound() returns a ServiceIntent. Inbound "
                    f"is the direction in which the foreign world reports FACTS. A "
                    f"ServiceIntent is a decision the kernel has already made; "
                    f"manufacturing one here lets the adapter schedule by the back door."
                )

        # --- LAW 2: no setpoint-shaped payloads --------------------------------
        for name, member in vars(cls).items():
            if isinstance(member, type) and is_dataclass(member):
                for f in fields(member):
                    if f.name.lower() in _SETPOINT_FIELDS:
                        raise AdapterLawViolation(
                            f"LAW 2 (power publication is schedule-shaped, never "
                            f"real-time): {cls.__name__}.{member.__name__}.{f.name} is a "
                            f"setpoint. OTTO-Q publishes forward demand schedules to "
                            f"site controllers and vendor EMS; it never commands a "
                            f"physical inverter (CLAUDE.md 2.5). Emit a "
                            f"ForwardPowerSchedule instead."
                        )

        declared = getattr(cls, "power_output_type", None)
        if declared is not None and declared is not ForwardPowerSchedule:
            raise AdapterLawViolation(
                f"LAW 2: {cls.__name__}.power_output_type is {declared!r}. The only "
                f"power-bearing outbound type is ForwardPowerSchedule."
            )


@runtime_checkable
class TranslatingAdapter(Protocol):
    """The whole adapter surface: two directions, no third.

    There is no `state()`, no `tick()`, no handle to the site. An adapter that
    cannot see site state cannot schedule against it — the cheapest way to keep
    Law 1 true is to withhold the inputs a decision would need.
    """

    protocol_name: str
    protocol_version: str

    def inbound(self, message: Any) -> tuple[AssetFact, ...]:
        """Foreign message → kernel facts. Never returns a decision."""
        ...

    def outbound(self, intent: ServiceIntent) -> Any:
        """Kernel decision → foreign message. Never makes the decision."""
        ...


def assert_translation_only(adapter_cls: type) -> None:
    """Belt-and-braces check usable from a test or a conformance run.

    __init_subclass__ already rejects the violations this finds; this exists so a
    harness can assert the property about a class it did not define, and so the
    failure is legible in a test report rather than only at import.
    """
    if not issubclass(adapter_cls, Adapter):
        raise AdapterLawViolation(
            f"{adapter_cls.__name__} does not inherit Adapter, so neither law is "
            f"enforced against it. Inheriting is what makes the boundary real."
        )
    for name, member in inspect.getmembers(adapter_cls, callable):
        if _violates_decision_verb(name):
            raise AdapterLawViolation(
                f"LAW 1: {adapter_cls.__name__}.{name}() is decision-shaped."
            )
