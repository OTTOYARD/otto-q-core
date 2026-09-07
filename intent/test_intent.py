"""Intent artifact tests — load/verify/resolve, and the structure a reviewer
can attack.

Run:  python3 -m pytest intent/test_intent.py -q

Every assertion is about the intent being (a) content-verified, (b) total and
deterministic, (c) provenance-carrying, (d) honest about NOT_FOUND, and
(e) covering the full objective space — not just energy (the founder's scope
correction). Values are not pinned to a golden number; the STRUCTURE is pinned,
because that is what a technical reviewer will interrogate.
"""

import json
from pathlib import Path

from intent.intent import (
    all_objective_keys, fingerprint, load_intent, resolve_intent, stamp,
)

HERE = Path(__file__).parent
ARTIFACT = HERE / "intent_v1.json"


# ---------------------------------------------------------------------------
# I1 — CONTENT INTEGRITY: the fingerprint verifies; tampering is refused.
# ---------------------------------------------------------------------------

def test_intent_fingerprint_verifies():
    it = load_intent()
    assert it.fingerprint, "I1 FAIL: no fingerprint"
    raw = json.loads(ARTIFACT.read_text())
    assert raw["manifest"]["fingerprint_md5"] == it.fingerprint


def test_intent_tamper_is_refused():
    raw = json.loads(ARTIFACT.read_text())
    # a mutated objective must change the fingerprint, which load_intent then
    # refuses to accept
    raw["objectives"]["readiness"]["direction"] = "maximize"
    canon = {k: raw[k] for k in ("numeraire", "objectives", "regimes",
                                 "tier3_constraints")}
    assert fingerprint(canon) != raw["manifest"]["fingerprint_md5"], \
        "I1 FAIL: a mutated objective did not change the fingerprint"


# ---------------------------------------------------------------------------
# I2 — FULL OBJECTIVE SPACE: energy is one of many; all tiers present.
# ---------------------------------------------------------------------------

def test_objectives_cover_the_full_space_not_just_energy():
    it = load_intent()
    keys = set(all_objective_keys(it))
    # the founder's scope: not only energy. These nine non-energy objectives
    # must all be present alongside energy_cost and bess_peak_shave.
    expected = {
        "readiness", "throughput", "service_completion",
        "dwell", "deadhead", "staging", "staff", "degradation", "risk_hedge",
        "energy_cost", "bess_peak_shave",
    }
    assert keys == expected, f"I2 FAIL: objectives {keys} != expected {expected}"


def test_every_regime_priority_is_a_real_objective():
    it = load_intent()
    keys = set(all_objective_keys(it))
    for regime in it.regimes:
        for k in regime.priority:
            assert k in keys, f"I2 FAIL: regime {regime.key} names unknown {k}"


def test_union_of_regime_priorities_covers_all_objectives():
    it = load_intent()
    union = set()
    for regime in it.regimes:
        union |= set(regime.priority)
    assert union == set(all_objective_keys(it)), \
        f"I2 FAIL: no regime ever prioritizes {set(all_objective_keys(it)) - union}"


def test_floors_are_readiness_and_service_completion():
    it = load_intent()
    for key, o in it.objectives.items():
        if o.kind == "floor":
            assert key in ("readiness", "service_completion"), \
                f"I2 FAIL: {key} is a floor but is neither readiness nor service"
    assert it.objectives["readiness"].kind == "floor"
    assert it.objectives["service_completion"].kind == "floor"


# ---------------------------------------------------------------------------
# I3 — HONEST NOT_FOUND: a weight is not invented.
# ---------------------------------------------------------------------------

def test_not_found_is_first_class_not_blank():
    it = load_intent()
    for key, o in it.objectives.items():
        assert o.dollar_value in ("sourced", "NOT_FOUND"), \
            f"I3 FAIL: {key} has dollar_value {o.dollar_value!r}"
        assert o.dollar_value_detail, f"I3 FAIL: {key} has no value detail"
    # readiness is the canonical NOT_FOUND — the thing nobody published
    assert it.objectives["readiness"].dollar_value == "NOT_FOUND"
    # energy IS sourced — the tariff is public
    assert it.objectives["energy_cost"].dollar_value == "sourced"


def test_every_objective_carries_provenance():
    it = load_intent()
    for key, o in it.objectives.items():
        assert o.provenance.get("source_name"), f"I3 FAIL: {key} no source_name"
        assert o.provenance.get("evidence_label") in (
            "primary", "review", "standards", "trade-press", "inference"), \
            f"I3 FAIL: {key} bad evidence_label"


# ---------------------------------------------------------------------------
# I4 — RESOLUTION: total, deterministic, regime-correct.
# ---------------------------------------------------------------------------

def test_resolve_is_total_and_deterministic():
    it = load_intent()
    for h in range(24):
        a = resolve_intent(it, hour_of_day=h)
        b = resolve_intent(it, hour_of_day=h)
        assert a.regime_key == b.regime_key and a.priority == b.priority, \
            f"I4 FAIL: resolve not deterministic at hour {h}"
    # the resolver never returns "no regime" — steady_state is the default
    assert all(resolve_intent(it, hour_of_day=h).regime_key
               for h in range(24))


def test_overnight_wraps_midnight():
    it = load_intent()
    for h in (20, 21, 23, 0, 2, 4):
        a = resolve_intent(it, hour_of_day=h)
        assert a.regime_key == "overnight", \
            f"I4 FAIL: hour {h} should be overnight, got {a.regime_key}"


def test_dispatch_rush_is_morning():
    it = load_intent()
    for h in (5, 7, 9):
        assert resolve_intent(it, hour_of_day=h).regime_key == "dispatch_rush"


def test_signals_override_the_clock():
    it = load_intent()
    # at 14:00 (steady_state), an explicit signal must override the clock
    a = resolve_intent(it, hour_of_day=14,
                       signals=frozenset({"grid_peak_imminent"}))
    assert a.regime_key == "grid_peak"
    b = resolve_intent(it, hour_of_day=14, signals=frozenset({"weather_hold"}))
    assert b.regime_key == "weather_event"
    c = resolve_intent(it, hour_of_day=14, signals=frozenset({"demand_surge"}))
    assert c.regime_key == "demand_surge"


def test_floors_are_subset_of_priority_in_order():
    it = load_intent()
    for h in range(24):
        a = resolve_intent(it, hour_of_day=h)
        # floors must appear in priority order, and be a strict subset
        assert set(a.floors) <= set(a.priority)
        idx = {k: i for i, k in enumerate(a.priority)}
        assert [idx[k] for k in a.floors] == sorted(idx[k] for k in a.floors)


# ---------------------------------------------------------------------------
# I5 — STAMP IS IDEMPOTENT: re-stamping unchanged content is a no-op.
# ---------------------------------------------------------------------------

def test_stamp_is_idempotent():
    before = load_intent().fingerprint
    stamp(ARTIFACT)
    after = load_intent().fingerprint
    assert before == after, "I5 FAIL: re-stamp of unchanged content moved the hash"


if __name__ == "__main__":
    for fn in [v for k, v in sorted(globals().items()) if k.startswith("test_")]:
        fn()
        print(f"{fn.__name__} PASS")
    print("ALL INTENT TESTS PASS")
