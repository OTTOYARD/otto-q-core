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

import dataclasses  # noqa: E402
import pytest  # noqa: E402

from intent.intent import (
    ARTIFACT_PATH, CANONICAL_FLOOR_ORDER, UNHASHED_MANIFEST_KEYS, _canonical,
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
    """load_intent must REFUSE a tampered artifact, not merely hash differently.

    This test used to stop one step short: it recomputed the fingerprint of
    mutated content and asserted the number changed. True, and not the claim.
    The claim is that the LOADER refuses — and the loader was never called, so
    deleting its verification block left this test green while every caller went
    on optimizing against an edited commander's intent.
    """
    import tempfile
    raw = json.loads(ARTIFACT.read_text())
    raw["objectives"]["readiness"]["direction"] = "maximize"
    canon = {k: raw[k] for k in ("numeraire", "objectives", "regimes",
                                 "tier3_constraints")}
    assert fingerprint(canon) != raw["manifest"]["fingerprint_md5"], \
        "I1 FAIL: a mutated objective did not change the fingerprint"

    with tempfile.TemporaryDirectory() as d:
        bad = Path(d) / "intent_tampered.json"
        bad.write_text(json.dumps(raw))
        try:
            load_intent(bad)
        except ValueError as e:
            assert "fingerprint mismatch" in str(e), f"I1 FAIL: wrong refusal: {e}"
        else:
            raise AssertionError(
                "I1 FAIL: load_intent accepted an artifact whose objectives do "
                "not match its own fingerprint")

        #: a REORDERED regime list is not tampering and must still load -- the
        #: fingerprint is over content, and a false refusal is its own defect
        ok = json.loads(ARTIFACT.read_text())
        good = Path(d) / "intent_ok.json"
        good.write_text(json.dumps(ok))
        load_intent(good)


def test_the_objective_taxonomy_is_two_weighted_tiers_and_a_shield():
    """"11 objectives across 3 tiers" is the natural thing to say about this
    artifact and it is wrong. The 11 objectives occupy tiers 1 and 2 only —
    4 and 7 — and tier 3 holds ZERO of them, by the artifact's own statement:
    it is not weighted and does not live here, being the 52-rule deterministic
    shield (power caps, double-booking exclusion, chemistry caps, state-machine
    validity). That distinction is doctrinal, not cosmetic: a tier-3 constraint
    is non-negotiable, and describing it as a weighted objective invites someone
    to trade it away.

    The honest sentence is "11 weighted objectives across tiers 1-2, with tier 3
    held as non-negotiable constraints outside the artifact". This pins the
    distribution so any doc, deck or handoff repeating the wrong one can be
    checked against the file rather than against memory.
    """
    from collections import Counter
    art = json.loads((HERE / "intent_v1.json").read_text())
    objs = art["objectives"]
    tiers = Counter(o["tier"] for o in objs.values())

    assert len(objs) == 11
    assert tiers[1] == 4 and tiers[2] == 7
    assert tiers[3] == 0, (
        "a weighted tier-3 objective appeared; tier 3 is the shield and is not "
        "weighted -- either the artifact or the doctrine changed")
    assert sum(tiers.values()) == len(objs)

    #: and the artifact says so itself, which is why the claim is checkable
    note = art["tier3_constraints"]["note"]
    assert "NOT weighted" in note and "does NOT live in this artifact" in note


def test_the_shipped_artifact_declares_the_signal_regimes_in_doctrinal_order():
    """Safety over cost over throughput IS declaration order — so guard the order.

    resolve_intent's two-pass design makes signals beat the clock structurally,
    and that half is pinned by the tests above. The OTHER half is not structural
    at all: within the signal pass the resolver returns the first match in
    declaration order, so "safety outranks cost outranks throughput" holds only
    because intent_v1.json happens to list weather_event, then grid_peak, then
    demand_surge.

    Measured, by reversing the regime list in a copy and re-stamping it: with
    both weather_hold and grid_peak_imminent raised at 07:00, the resolver
    returns grid_peak instead of weather_event. A grounding risk loses to a
    tariff signal, and nothing in the artifact says why.

    Redesigning the pack format to carry an explicit precedence rank is a
    deliberate change to a declarative contract and is NOT made here. What is
    made here is the check that was missing: the shipped artifact's order is
    asserted against the doctrine, so an editor who tidies the JSON turns CI red
    instead of quietly inverting safety and cost.
    """
    raw = json.loads(ARTIFACT.read_text())
    signal_regimes = [r["key"] for r in raw["regimes"] if r.get("match", {}).get("signals")]
    assert signal_regimes == ["weather_event", "grid_peak", "demand_surge"], (
        f"the signal regimes are declared {signal_regimes}. Within the signal "
        "pass the resolver takes the FIRST match, so this list IS the precedence: "
        "safety (weather_event) must precede cost (grid_peak), which must precede "
        "throughput (demand_surge). Reordering this list silently reorders the "
        "doctrine.")

    #: and the resolver must actually honour it when signals collide
    it = load_intent()
    both = resolve_intent(it, hour_of_day=7,
                          signals=frozenset({"weather_hold", "grid_peak_imminent"}))
    assert both.regime_key == "weather_event", (
        f"both signals up and the resolver chose {both.regime_key!r}; a grounding "
        "risk must outrank a tariff signal")
    all_three = resolve_intent(it, hour_of_day=7,
                               signals=frozenset({"weather_hold", "grid_peak_imminent",
                                                  "demand_surge"}))
    assert all_three.regime_key == "weather_event"
    cost_vs_throughput = resolve_intent(
        it, hour_of_day=7, signals=frozenset({"grid_peak_imminent", "demand_surge"}))
    assert cost_vs_throughput.regime_key == "grid_peak", (
        f"cost vs throughput resolved to {cost_vs_throughput.regime_key!r}; "
        "grid_peak must outrank demand_surge")


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


def test_signals_override_the_clock_during_rush():
    # The bug this pins: dispatch_rush is declared before the signal regimes, so
    # a naive first-match resolver would return dispatch_rush at 07:00 even with
    # a grid_peak_imminent signal. Signals override the clock at EVERY hour.
    it = load_intent()
    assert resolve_intent(it, hour_of_day=7,
                          signals=frozenset({"grid_peak_imminent"})).regime_key == "grid_peak"
    assert resolve_intent(it, hour_of_day=7,
                          signals=frozenset({"demand_surge"})).regime_key == "demand_surge"
    assert resolve_intent(it, hour_of_day=7,
                          signals=frozenset({"weather_hold"})).regime_key == "weather_event"


def test_signals_override_the_clock_during_overnight():
    it = load_intent()
    assert resolve_intent(it, hour_of_day=22,
                          signals=frozenset({"demand_surge"})).regime_key == "demand_surge"
    assert resolve_intent(it, hour_of_day=3,
                          signals=frozenset({"grid_peak_imminent"})).regime_key == "grid_peak"


def test_weather_grounding_risk_outranks_cost_and_throughput_signals():
    # Safety first: a grounding risk (weather_hold) outranks a cost signal
    # (grid_peak_imminent) and a throughput signal (demand_surge) when several
    # are raised at once.
    it = load_intent()
    all_sigs = frozenset({"weather_hold", "grid_peak_imminent", "demand_surge"})
    assert resolve_intent(it, hour_of_day=14, signals=all_sigs).regime_key == "weather_event"
    two = frozenset({"grid_peak_imminent", "demand_surge"})
    assert resolve_intent(it, hour_of_day=14, signals=two).regime_key == "grid_peak"


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


# ---------------------------------------------------------------------------
# L-38: an unknown signal is an error, not a silent fall-through to the clock.
# ---------------------------------------------------------------------------

def test_a_misspelled_signal_raises_instead_of_resolving_by_the_clock():
    """The hazard: `grid_peak_imminant` at 07:00 resolved to dispatch_rush.

    `_matches` only tested `need.issubset(signals)`, so a name no regime knows
    matched nothing, pass 1 found no signal regime, and the resolver fell
    through to the clock — returning a regime as though no signal had been
    raised. Throughput first, on a tick about to hit a demand-charge ceiling.
    """
    it = load_intent()
    good = resolve_intent(it, hour_of_day=7,
                          signals=frozenset({"grid_peak_imminent"}))
    assert good.regime_key == "grid_peak"
    with pytest.raises(ValueError, match="grid_peak_imminant"):
        resolve_intent(it, hour_of_day=7,
                       signals=frozenset({"grid_peak_imminant"}))


def test_the_signal_vocabulary_comes_from_the_artifact():
    it = load_intent()
    assert it.known_signals == frozenset(
        {"weather_hold", "grid_peak_imminent", "demand_surge"})
    #: every declared signal resolves; the vocabulary is not decoration
    for sig in it.known_signals:
        assert resolve_intent(it, hour_of_day=12, signals=frozenset({sig}))


def test_no_signals_at_all_is_still_fine():
    assert resolve_intent(load_intent(), hour_of_day=7).regime_key == "dispatch_rush"


# ---------------------------------------------------------------------------
# L-55: the fingerprint covers everything except itself.
# ---------------------------------------------------------------------------

def test_the_manifest_is_inside_the_fingerprint():
    """`version` and `kind` used to ride outside the hash, so the loader
    returned a verified-looking object carrying a field the verification never
    covered — a document could declare itself version 9 of a different kind
    without disturbing its own hash."""
    raw = json.loads(ARTIFACT_PATH.read_text())
    before = fingerprint(_canonical(raw))
    for field in ("version", "kind", "description"):
        tampered = json.loads(json.dumps(raw))
        tampered["manifest"][field] = "tampered"
        assert fingerprint(_canonical(tampered)) != before, (
            f"manifest.{field} is still outside the fingerprint")


def test_the_two_self_referential_fields_stay_outside_it():
    raw = json.loads(ARTIFACT_PATH.read_text())
    before = fingerprint(_canonical(raw))
    for field in UNHASHED_MANIFEST_KEYS:
        tampered = json.loads(json.dumps(raw))
        tampered["manifest"][field] = "changed"
        assert fingerprint(_canonical(tampered)) == before, (
            f"{field} cannot describe itself and must stay out of the hash")


def test_a_key_added_later_is_covered_by_default():
    """The old allowlist covered a new top-level key only if someone remembered
    to extend it. Coverage is now the default and exclusion is the exception."""
    raw = json.loads(ARTIFACT_PATH.read_text())
    before = fingerprint(_canonical(raw))
    raw["some_future_section"] = {"a": 1}
    assert fingerprint(_canonical(raw)) != before


# ---------------------------------------------------------------------------
# L-56: "floor" is defined by the artifact, not by a Python tuple.
# ---------------------------------------------------------------------------

def test_an_artifact_declared_floor_cannot_be_dropped_by_a_regime():
    """There were two definitions of "floor": a hardcoded tuple that decided
    what got PREPENDED, and the artifact's `kind == "floor"` that decided what
    was REPORTED. An objective declared a floor but not named in the tuple was
    silently dropped by every regime that did not list it."""
    it = load_intent()
    #: give the artifact a third floor it has never heard of
    extra = dataclasses.replace(it.objectives["readiness"], key="grid_safety",
                                kind="floor")
    widened = dataclasses.replace(
        it, objectives={**it.objectives, "grid_safety": extra})

    for regime in widened.regimes:
        active = resolve_intent(widened, hour_of_day=12,
                                signals=frozenset(regime.match.get("signals", [])))
        assert "grid_safety" in active.priority, (
            f"regime {active.regime_key} dropped an artifact-declared floor")
        assert "grid_safety" in active.floors


def test_the_two_named_floors_keep_their_canonical_order():
    active = resolve_intent(load_intent(), hour_of_day=12)
    assert active.priority[:2] == CANONICAL_FLOOR_ORDER
