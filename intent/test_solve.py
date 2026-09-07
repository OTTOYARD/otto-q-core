"""Pass-sequencer tests — the honest capability map and its consequences.

Run:  python3 -m pytest intent/test_solve.py -q

These pin the truth about what the solver can do. With three variable passes
(min_tardy, min_peak, min_flow) the regime now GENUINELY reorders the soft
passes — that is the finding these tests lock in, so a regression that silently
flattens the regimes back to one sequence fails loudly.
"""

from intent.intent import load_intent, resolve_intent
from intent.solve import SOLVER_PASS, pass_sequence, shielded, unmodeled

IT = load_intent()
ALL_KEYS = set(IT.objectives)

# The pinned pass sequence per regime, in the order the resolver emits them.
# dispatch_rush / demand_surge lead with throughput (min_flow); grid_peak /
# overnight lead with energy (min_peak); weather_event has no soft pass at all.
EXPECTED_SEQUENCE = {
    "dispatch_rush": ("min_tardy", "min_flow", "min_peak"),
    "demand_surge":  ("min_tardy", "min_flow"),
    "grid_peak":     ("min_tardy", "min_peak"),
    "overnight":     ("min_tardy", "min_peak", "min_flow"),
    "weather_event": ("min_tardy",),
    "steady_state":  ("min_tardy", "min_peak", "min_flow"),
}


# ---------------------------------------------------------------------------
# S1 — THE CAPABILITY MAP IS COMPLETE AND HONEST.
# ---------------------------------------------------------------------------

def test_map_covers_every_declared_objective():
    assert set(SOLVER_PASS) == ALL_KEYS, (
        f"S1 FAIL: SOLVER_PASS keys {set(SOLVER_PASS)} != declared objectives "
        f"{ALL_KEYS} — an objective without a row silently defaults to None")


def test_exactly_three_variable_passes_exist():
    real = {k: v for k, v in SOLVER_PASS.items() if v not in (None, "shield")}
    assert real == {
        "readiness": "min_tardy",
        "throughput": "min_flow",
        "dwell": "min_flow",
        "energy_cost": "min_peak",
        "bess_peak_shave": "min_peak",
    }, f"S1 FAIL: expected exactly the three variable passes, got {real}"


def test_service_completion_is_shield_enforced_not_a_pass():
    assert SOLVER_PASS["service_completion"] == "shield"


# ---------------------------------------------------------------------------
# S2 — THE REGIME REORDERS THE PASSES; THE FLOOR IS ALWAYS FIRST.
# ---------------------------------------------------------------------------

def _active(hour, signals=frozenset()):
    return resolve_intent(IT, hour_of_day=hour, signals=signals)


def test_floors_are_always_first_in_every_resolved_priority():
    for h in range(24):
        for sigs in (frozenset(), frozenset({"grid_peak_imminent"}),
                     frozenset({"weather_hold"}), frozenset({"demand_surge"})):
            active = _active(h, sigs)
            assert active.priority[:2] == ("readiness", "service_completion"), (
                f"S2 FAIL: floors not first in {active.regime_key} at {h} {sigs}: "
                f"{active.priority}")


def test_readiness_floor_is_always_pass_one():
    for h in range(24):
        for sigs in (frozenset(), frozenset({"grid_peak_imminent"}),
                     frozenset({"weather_hold"}), frozenset({"demand_surge"})):
            seq = pass_sequence(_active(h, sigs))
            assert seq and seq[0] == "min_tardy", (
                f"S2 FAIL: readiness floor not pass 1 in {seq}")


def test_each_regime_resolves_to_its_pinned_pass_sequence():
    cases = {
        "dispatch_rush": _active(7),
        "demand_surge":  _active(14, frozenset({"demand_surge"})),
        "grid_peak":     _active(14, frozenset({"grid_peak_imminent"})),
        "overnight":     _active(22),
        "weather_event": _active(14, frozenset({"weather_hold"})),
        "steady_state":  _active(15),
    }
    for key, active in cases.items():
        assert active.regime_key == key, (
            f"S2 FAIL: expected regime {key}, resolved {active.regime_key}")
        assert pass_sequence(active) == EXPECTED_SEQUENCE[key], (
            f"S2 FAIL: {key} -> {pass_sequence(active)}, expected "
            f"{EXPECTED_SEQUENCE[key]}")


def test_the_regime_genuinely_reorders():
    # The whole point: dispatch_rush leads with throughput, grid_peak with energy.
    rush = pass_sequence(_active(7))                       # dispatch_rush
    peak = pass_sequence(_active(14, frozenset({"grid_peak_imminent"})))
    assert rush[1] == "min_flow" and rush[-1] == "min_peak"
    assert peak == ("min_tardy", "min_peak")
    assert rush != peak, "S2 FAIL: regime no longer reorders the passes"


# ---------------------------------------------------------------------------
# S3 — THE GAP IS VISIBLE, NOT SILENT.
# ---------------------------------------------------------------------------

def test_unmodeled_names_the_soft_objectives_without_a_pass():
    active = _active(15)                       # steady_state
    expected = tuple(k for k in active.priority if SOLVER_PASS.get(k) is None)
    assert unmodeled(active) == expected
    assert "deadhead" in unmodeled(active)
    assert "staff" in unmodeled(active)
    assert "degradation" in unmodeled(active)
    assert "staging" in unmodeled(active)
    assert "risk_hedge" in unmodeled(active)
    # service_completion is shield-enforced, NOT "unmodeled"
    assert "service_completion" not in unmodeled(active)
    # throughput/dwell now have a pass — they must NOT be unmodeled
    assert "throughput" not in unmodeled(active)
    assert "dwell" not in unmodeled(active)


def test_shielded_names_service_completion():
    assert shielded(_active(15)) == ("service_completion",)


def test_objectives_partition_cleanly():
    with_pass = {k for k in ALL_KEYS if SOLVER_PASS.get(k) not in (None, "shield")}
    unmod = {k for k in ALL_KEYS if SOLVER_PASS.get(k) is None}
    shld = {k for k in ALL_KEYS if SOLVER_PASS.get(k) == "shield"}
    assert with_pass | unmod | shld == ALL_KEYS
    assert len(with_pass) + len(unmod) + len(shld) == len(ALL_KEYS)
    assert with_pass == {"readiness", "throughput", "dwell",
                         "energy_cost", "bess_peak_shave"}
    assert shld == {"service_completion"}


if __name__ == "__main__":
    for fn in [v for k, v in sorted(globals().items()) if k.startswith("test_")]:
        fn()
        print(f"{fn.__name__} PASS")
    print("ALL SEQUENCER TESTS PASS")
