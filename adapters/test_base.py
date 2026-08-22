"""C10 — proof that the two laws bite at import time, not just in prose.

Each test constructs a violating adapter and asserts the class statement itself
raises. If these pass, "adapters translate, never decide" is a property of the
codebase rather than a claim in a document.
"""

from __future__ import annotations

from dataclasses import dataclass

import pytest

from adapters.base import (
    Adapter,
    AdapterLawViolation,
    AssetFact,
    ForwardPowerSchedule,
    PowerPeriod,
    ServiceIntent,
    assert_translation_only,
)


# --- the shape that is allowed ------------------------------------------------

class WellBehavedAdapter(Adapter):
    protocol_name = "example"
    protocol_version = "0"

    def inbound(self, message: dict) -> tuple[AssetFact, ...]:
        return (AssetFact(asset_ref=message["id"], observed_at=message["ts"]),)

    def outbound(self, intent: ServiceIntent) -> dict:
        return {"asset": intent.asset_ref, "op": intent.operation_code}


def test_a_translating_adapter_is_accepted():
    assert_translation_only(WellBehavedAdapter)
    a = WellBehavedAdapter()
    facts = a.inbound({"id": "robot-7", "ts": "2026-08-22T22:00:00Z"})
    assert facts[0].asset_ref == "robot-7"


# --- LAW 1 --------------------------------------------------------------------

def test_law1_rejects_a_decision_verb_method():
    with pytest.raises(AdapterLawViolation, match="LAW 1"):
        class Decider(Adapter):                     # noqa: unused
            protocol_name = "bad"
            protocol_version = "0"

            def assign_stall(self, fact):           # the violation
                return "stall-3"


def test_law1_rejects_decision_verb_prefixes_too():
    # `choose_bay` must fail as surely as `choose`.
    for bad_name in ("choose_bay", "optimize_route", "prioritise_asset", "book_slot"):
        with pytest.raises(AdapterLawViolation, match="LAW 1"):
            type(f"Bad_{bad_name}", (Adapter,), {bad_name: lambda self: None})


def test_law1_allows_translation_verbs_that_merely_contain_a_verb_substring():
    # `describe` starts with "desc", not a decision verb; `to_order_message` is a
    # translation. Neither may be caught by an over-eager matcher.
    class Fine(Adapter):
        protocol_name = "ok"
        protocol_version = "0"

        def describe(self):
            return "x"

        def to_order_message(self, intent):
            return {}

    assert Fine.protocol_name == "ok"


def test_law1_rejects_inbound_that_returns_a_decision():
    with pytest.raises(AdapterLawViolation, match="LAW 1"):
        class SmugglesIntent(Adapter):              # noqa: unused
            protocol_name = "bad"
            protocol_version = "0"

            def inbound(self, message) -> tuple[ServiceIntent, ...]:
                return ()


# --- LAW 2 --------------------------------------------------------------------

def test_law2_rejects_a_setpoint_field():
    with pytest.raises(AdapterLawViolation, match="LAW 2"):
        class Commands(Adapter):                    # noqa: unused
            protocol_name = "bad"
            protocol_version = "0"

            @dataclass(frozen=True)
            class Payload:
                setpoint_kw: float                  # the violation


def test_law2_rejects_other_device_command_shapes():
    for bad_field in ("target_kw", "instantaneous_kw", "duty_cycle", "current_a"):
        with pytest.raises(AdapterLawViolation, match="LAW 2"):
            payload = type("P", (), {"__annotations__": {bad_field: float}})
            payload = __import__("dataclasses").dataclass(frozen=True)(payload)
            type("BadAdapter", (Adapter,), {"Payload": payload})


def test_law2_rejects_a_non_schedule_power_output_type():
    with pytest.raises(AdapterLawViolation, match="LAW 2"):
        class WrongPower(Adapter):                  # noqa: unused
            protocol_name = "bad"
            protocol_version = "0"
            power_output_type = float


def test_law2_a_zero_duration_schedule_is_a_setpoint_in_costume():
    with pytest.raises(AdapterLawViolation, match="LAW 2"):
        ForwardPowerSchedule(
            start_at="2026-08-22T22:00:00Z",
            duration_s=0,
            periods=(PowerPeriod(0, 50.0),),
        )


def test_law2_an_empty_schedule_is_rejected():
    with pytest.raises(AdapterLawViolation, match="LAW 2"):
        ForwardPowerSchedule(start_at="2026-08-22T22:00:00Z", duration_s=3600, periods=())


def test_law2_a_real_forward_schedule_is_accepted():
    s = ForwardPowerSchedule(
        start_at="2026-08-22T22:00:00Z",
        duration_s=3600,
        periods=(PowerPeriod(0, 3000.0), PowerPeriod(1800, 1500.0)),
    )
    assert s.periods[1].limit_kw == 1500.0
    assert not hasattr(s, "setpoint_kw")


# --- the enforcement cannot be opted out of -----------------------------------

def test_a_class_that_does_not_inherit_adapter_is_not_trusted():
    class Freelancer:                               # never inherits Adapter
        def assign_stall(self):
            return "stall-3"

    with pytest.raises(AdapterLawViolation, match="does not inherit Adapter"):
        assert_translation_only(Freelancer)


def test_the_adapter_protocol_has_exactly_two_directions():
    # A third direction is how site state leaks in; if this ever grows, Law 1 is
    # one refactor away from being unenforceable.
    from adapters.base import TranslatingAdapter
    # Callables are the directions; bare annotations (protocol_name/version) are
    # identity, not a direction, and live in __annotations__ rather than vars().
    directions = {
        n for n, v in vars(TranslatingAdapter).items()
        if not n.startswith("_") and callable(v)
    }
    assert directions == {"inbound", "outbound"}, directions
    assert set(TranslatingAdapter.__annotations__) == {
        "protocol_name", "protocol_version"
    }, TranslatingAdapter.__annotations__
