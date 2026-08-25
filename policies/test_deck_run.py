"""Validation of the committed deck artifact.

Deliberately does NOT re-run the solve (wall-limited, minutes-long, not
byte-stable across machines -- the artifact's own reproducibility note). It
asserts instead that everything DERIVED from the committed curves regenerates
exactly, and that the numbers obey the model's own invariants.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from deck_run import ARTIFACT, derive  # noqa: E402


@pytest.fixture(scope="module")
def art():
    return json.loads(ARTIFACT.read_text())


def test_derived_numbers_regenerate_from_the_committed_curves(art):
    """Bills, BESS equivalence and deltas are pure functions of the curves."""
    fresh = derive(art["columns"])
    assert fresh == art["derived"]


def test_no_column_beats_the_provable_bound(art):
    for name, col in art["derived"].items():
        if name == "delta":
            continue
        assert col["peak_site_kw"] >= art["peak_lower_bound_kw"], name


def test_the_comparison_is_pure_infrastructure(art):
    """Both columns meet every deadline at this scale, so the delta is peak,
    interconnect, battery and dollars -- nothing is bought with lateness."""
    assert art["derived"]["unmanaged"]["total_tardy_min"] == 0
    assert art["derived"]["otto_q_shaped"]["total_tardy_min"] == 0


def test_the_headline_claim_is_supported(art):
    """'Half the infrastructure' must be conservative, never generous."""
    d = art["derived"]["delta"]
    assert d["peak_ratio"] >= 2.0
    a = art["derived"]["unmanaged"]["required_interconnect_kw"]
    b = art["derived"]["otto_q_shaped"]["required_interconnect_kw"]
    assert a >= 2 * b


def test_bess_equivalence_is_feasible_and_zero_for_shaped(art):
    ba = art["derived"]["unmanaged"]["bess_to_match_shaped"]
    assert ba["stored_kwh_at_96pct_rte"] > 0
    assert ba["recharge_fits_in_window"] is True
    assert art["derived"]["otto_q_shaped"]["bess_to_match_shaped"][
        "stored_kwh_at_96pct_rte"] == 0.0


def test_methodology_names_its_baseline_and_its_limits(art):
    m = " ".join(art["methodology"])
    assert "Mobility House" in m          # the third-party unmanaged anchor
    assert "not a bill forecast" in m
    assert "Common random numbers" in m
