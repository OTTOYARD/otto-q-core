"""Pass-sequencer tests — the honest capability map and its consequences.

Run:  python3 -m pytest intent/test_solve.py -q

These pin the HONEST truth about what the solver can do today, not an
aspiration: with two variable objective terms, every regime resolves to the
same pass sequence. The test that matters most is the one that FAILS if someone
adds a third solver pass and forgets to reflect it here — and the one that
keeps the "gap is visible" property alive.
"""

from intent.intent import load_intent, resolve_intent
from intent.solve import SOLVER_PASS, pass_sequence, shielded, unmodeled

IT = load_intent()
ALL_KEYS = set(IT.objectives)


# ---------------------------------------------------------------------------
# S1 — THE CAPABILITY MAP IS COMPLETE AND HONEST.
# ---------------------------------------------------------------------------

def test_map_covers_every_declared_objective():
    assert set(SOLVER_PASS) == ALL_KEYS, (
        f"S1 FAIL: SOLVER_PASS keys {set(SOLVER_PASS)} != declared objectives "
        f"{ALL_KEYS} — an objective without a row silently defaults to None")


def test_only_two_variable_passes_exist():
    real = {k: v for k, v in SOLVER_PASS.items() if v not in (None, "shield")}
    assert real == {"readiness": "min_tardy",
                    "energy_cost": "min_peak",
                    "bess_peak_shave": "min_peak"}, (
        f"S1 FAIL: expected exactly readiness->min_tardy and energy/bess->min_peak "
        f"as the only variable passes, got {real}")


def test_service_completion_is_shield_enforced_not_a_pass():
    assert SOLVER_PASS["service_completion"] == "shield"


# ---------------------------------------------------------------------------
# S2 — PASS SEQUENCE IS THE HONEST (TWO-PASS) RESULT FOR EVERY REGIME.
# ---------------------------------------------------------------------------

def test_pass_sequence_starts_with_the_readiness_floor():
    # The floor is structural: min_tardy always first. min_peak follows only when
    # the regime prioritizes energy — demand_surge and weather_event do not, and
    # correctly resolve to the readiness floor alone. That is honest, not a bug.
    for h in range(24):
        for sigs in (frozenset(), frozenset({"grid_peak_imminent"}),
                     frozenset({"weather_hold"}), frozenset({"demand_surge"})):
            active = resolve_intent(IT, hour_of_day=h, signals=sigs)
            seq = pass_sequence(active)
            assert seq and seq[0] == "min_tardy", (
                f"S2 FAIL: readiness floor not first in {active.regime_key} "
                f"at {h} {sigs}: {seq}")
            assert seq in (("min_tardy",), ("min_tardy", "min_peak")), (
                f"S2 FAIL: unexpected pass sequence {seq}")
            if "min_peak" in seq:
                assert ("energy_cost" in active.priority
                        or "bess_peak_shave" in active.priority), (
                    f"S2 FAIL: min_peak without an energy objective in "
                    f"{active.regime_key}")


def test_energy_pass_appears_only_when_regime_prioritizes_energy():
    rush = resolve_intent(IT, hour_of_day=7)                       # dispatch_rush
    assert "min_peak" in pass_sequence(rush)                       # has energy_cost
    surge = resolve_intent(IT, hour_of_day=14,
                           signals=frozenset({"demand_surge"}))    # no energy
    assert pass_sequence(surge) == ("min_tardy",)
    weather = resolve_intent(IT, hour_of_day=14,
                             signals=frozenset({"weather_hold"}))  # no energy
    assert pass_sequence(weather) == ("min_tardy",)


def test_floors_are_always_first_in_the_resolved_priority():
    for h in range(24):
        for sigs in (frozenset(), frozenset({"grid_peak_imminent"}),
                     frozenset({"weather_hold"})):
            active = resolve_intent(IT, hour_of_day=h, signals=sigs)
            assert active.priority[:2] == ("readiness", "service_completion"), (
                f"S2 FAIL: floors not first in {active.regime_key} at {h}: "
                f"{active.priority}")


# ---------------------------------------------------------------------------
# S3 — THE GAP IS VISIBLE, NOT SILENT.
# ---------------------------------------------------------------------------

def test_unmodeled_names_the_soft_objectives_without_a_pass():
    active = resolve_intent(IT, hour_of_day=15)   # steady_state
    # every soft objective except energy/bess has no pass; shields aren't unmodeled
    expected = tuple(k for k in active.priority
                     if SOLVER_PASS.get(k) is None)
    assert unmodeled(active) == expected
    assert "throughput" in unmodeled(active)
    assert "staff" in unmodeled(active)
    assert "degradation" in unmodeled(active)
    # service_completion is shield-enforced, NOT "unmodeled"
    assert "service_completion" not in unmodeled(active)


def test_shielded_names_service_completion():
    active = resolve_intent(IT, hour_of_day=15)
    assert shielded(active) == ("service_completion",)


def test_objectives_partition_cleanly():
    # The SOLVER_PASS map is the ground truth for the partition: every objective
    # is exactly one of (has a pass, unmodeled, shield-enforced).
    with_pass = {k for k in ALL_KEYS if SOLVER_PASS.get(k) not in (None, "shield")}
    unmod = {k for k in ALL_KEYS if SOLVER_PASS.get(k) is None}
    shld = {k for k in ALL_KEYS if SOLVER_PASS.get(k) == "shield"}
    assert with_pass | unmod | shld == ALL_KEYS
    assert len(with_pass) + len(unmod) + len(shld) == len(ALL_KEYS)
    assert with_pass == {"readiness", "energy_cost", "bess_peak_shave"}
    assert shld == {"service_completion"}


if __name__ == "__main__":
    for fn in [v for k, v in sorted(globals().items()) if k.startswith("test_")]:
        fn()
        print(f"{fn.__name__} PASS")
    print("ALL SEQUENCER TESTS PASS")
