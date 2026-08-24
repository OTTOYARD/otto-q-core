"""Tests for the forward orchestrator and the foresight storage dispatch."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from forward import dispatch_storage, forward_comparison  # noqa: E402
from sites.site_profile import Storage                    # noqa: E402

SC = HERE.parent / "solvers" / "cpsat" / "scenario_canonical.json"


@pytest.fixture(scope="module")
def comp():
    return forward_comparison(SC)


# ---- the product claim, as an assertion ------------------------------------------

def test_forward_holds_both_axes_at_once(comp):
    """Zero missed deadlines at a bill below every myopic policy -- the claim itself."""
    rows = comp["policies"]
    f = rows["forward"]
    assert f["total_tardy_min"] == 0
    for name in ("fifo", "greedy", "otto_q_asis", "cpsat"):
        assert f["monthly_total"] <= rows[name]["monthly_total"], name


def test_forward_peak_respects_the_provable_bound(comp):
    """The bound is the floor; landing under it would mean the bound or the curve is wrong."""
    assert comp["policies"]["forward"]["peak_site_kw"] >= comp["peak_lower_bound_kw"]


def test_forward_is_deterministic():
    a = forward_comparison(SC)
    b = forward_comparison(SC)
    assert a["forward_sha256"] == b["forward_sha256"]


def test_forward_artifact_matches_committed(comp):
    import json
    blob = json.dumps(comp, indent=1, sort_keys=True) + "\n"
    assert blob == (HERE / "forward_seed424242.json").read_text()


def test_forward_is_absent_from_the_frozen_comparison():
    """comparison_seed424242.json is byte-asserted; forward must never leak into it."""
    import json
    committed = json.loads((HERE / "comparison_seed424242.json").read_text())
    assert all(r["policy"] != "forward" for r in committed["runs"])


# ---- storage dispatch ------------------------------------------------------------

def _storage(**kw) -> Storage:
    base = dict(power_kw=100.0, energy_kwh=400.0, round_trip_efficiency=1.0,
                soc_min_pct=0.0, soc_max_pct=100.0, units=1)
    base.update(kw)
    return Storage(**base)


def _square_curve(kw=200.0, on=(0, 120), end=1440.0):
    pts = [(float(m), kw if on[0] <= m < on[1] else 0.0) for m in range(0, int(end), 15)]
    pts.append((end, 0.0))
    return pts


def test_dispatch_holds_the_grid_at_the_computed_ceiling():
    d = dispatch_storage(_square_curve(), _storage())
    assert d["supported"]
    # 200 kW for 2 h = 400 kWh; battery holds 100 kW of it while energy lasts.
    assert d["grid_peak_kw"] == pytest.approx(100.0, abs=0.5)
    assert max(kw for _, kw in d["grid_curve"]) <= d["grid_peak_kw"] + 0.5


def test_dispatch_is_power_limited_when_the_spike_exceeds_the_battery():
    d = dispatch_storage(_square_curve(kw=500.0), _storage(power_kw=100.0))
    # the battery can shave at most its own power off the top
    assert d["grid_peak_kw"] >= 400.0 - 0.5


def test_dispatch_is_energy_limited_when_the_wave_is_long():
    # 200 kW for 8 h = 1600 kWh demanded above zero; only 400 kWh usable
    d = dispatch_storage(_square_curve(on=(0, 480)), _storage())
    deficit_h = 8.0
    # energy cap: shave depth d_kw * 8 h <= 400 kWh -> at most 50 kW of shaving
    assert d["grid_peak_kw"] >= 150.0 - 0.5


def test_recharge_stays_under_the_ceiling_and_pays_losses():
    d = dispatch_storage(_square_curve(), _storage(round_trip_efficiency=0.5))
    assert d["supported"]
    # 100 kW shaved for 2 h = 200 kWh delivered; at 50% RTE the meter pays 400 kWh
    assert d["recharge_kwh"] == pytest.approx(d["deficit_kwh"] / 0.5, rel=0.01)
    assert max(kw for _, kw in d["grid_curve"]) <= d["grid_peak_kw"] + 0.5


def test_a_day_with_no_slack_cannot_recharge():
    """A curve pinned at the ceiling all day leaves nowhere to put the recharge."""
    flat = [(float(m), 200.0) for m in range(0, 1440, 15)] + [(1440.0, 200.0)]
    d = dispatch_storage(flat, _storage())
    # feasible only at the original peak (zero shaving) -- which needs no recharge
    assert d["grid_peak_kw"] == pytest.approx(200.0, abs=0.5)


def test_storage_row_is_reported_with_its_context(comp):
    fs = comp["forward_with_storage"]
    assert fs["supported"]
    assert fs["grid_peak_kw"] < comp["policies"]["forward"]["peak_site_kw"]
    # recharge energy exceeds delivered energy -- losses are paid at the meter
    assert fs["recharge_kwh"] > fs["deficit_kwh"]
