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


# ---- the same formulation at scale: the 24h KPI-gate scenario --------------------

@pytest.fixture(scope="module")
def comp24():
    from forward import forward_comparison_24h
    return forward_comparison_24h()


def test_forward_holds_both_axes_at_scale(comp24):
    """16 assets, 30-hour horizon, overlapping waves -- the edge must survive scale."""
    rows = comp24["policies"]
    f = rows["forward"]
    assert f["total_tardy_min"] == 0
    for name in ("fifo", "greedy", "otto_q_asis", "cpsat"):
        assert f["monthly_total"] <= rows[name]["monthly_total"], name


def test_lexicographic_beats_the_weighted_objective_at_scale(comp24):
    """The reason forward is lexicographic and not a weighted soup, measured.

    At 24h the weighted default trades tardiness for its unit-less penalty terms and
    misses deadlines; the lexicographic solve holds zero AND lands a lower bill. If
    the weighted objective ever matches it on both axes, the weights have effectively
    become the lexicographic order and this test should be revisited.
    """
    rows = comp24["policies"]
    assert rows["cpsat"]["total_tardy_min"] > 0
    assert rows["forward"]["total_tardy_min"] == 0
    assert rows["forward"]["monthly_total"] < rows["cpsat"]["monthly_total"]


def test_24h_peak_respects_its_own_bound(comp24):
    assert comp24["policies"]["forward"]["peak_site_kw"] >= comp24["peak_lower_bound_kw"]


def test_24h_artifact_matches_committed(comp24):
    import json
    blob = json.dumps(comp24, indent=1, sort_keys=True) + "\n"
    assert blob == (HERE / "forward_24h_seed424242.json").read_text()


def test_billed_curve_conserves_every_charged_kwh():
    """The invariant that makes tail truncation impossible to ship.

    A curve cut short of the horizon silently drops the charges in the tail and
    understates the bill, and no ranking test would notice -- every policy would be
    understated together. The truncation-proof check is conservation: the energy
    under the billed curve must equal the energy of the charge segments themselves,
    for the scenario with the long horizon, to sampling tolerance. A first draft of
    this test instead asserted "there is load after minute 1440" -- which happened
    to be false for FIFO on this scenario (its last charge ends at minute 1219) and
    would have gone stale the moment the scenario shifted; conservation cannot.
    """
    import sys as _sys
    _sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))
    from cost import site_load_curve
    from harness import run_policy_traced
    from model import load_scenario
    from assignment_policy import FifoPolicy
    sc = load_scenario(HERE.parent / "solvers" / "cpsat" / "scenario_24h.json")
    _, state = run_policy_traced(sc, FifoPolicy())

    seg_kwh = sum(s["kw"] * s["minutes"] / 60.0
                  for segs in state.segments.values() for s in segs)
    full = site_load_curve(state, end_min=sc["horizon_min"], step_min=1)
    curve_kwh = sum(kw / 60.0 for _, kw in full[:-1])
    assert curve_kwh == pytest.approx(seg_kwh, rel=0.01)

    # and the day-truncated default really does lose energy if anything ran late --
    # equality here simply means this scenario's charges all fit inside the day
    day = site_load_curve(state, end_min=1440, step_min=1)
    day_kwh = sum(kw / 60.0 for _, kw in day[:-1])
    assert day_kwh <= curve_kwh + 1e-6


# ---- the multimodal hero-shot backend: vertiport over depot ----------------------

@pytest.fixture(scope="module")
def mm():
    from forward import multimodal_comparison
    return multimodal_comparison()


def test_multimodal_forward_runs_the_morning_rush(mm):
    """The wedge itself: on an oversubscribed multimodal site, the joint solve is
    the only policy that turns the commuter peak around on time WITHIN the
    physical service capacity."""
    f = mm["policies"]["forward"]
    assert f["total_tardy_min"] == 0
    assert f["physically_runnable"] is True
    assert f["peak_site_kw"] <= mm["service_capacity_kw"]


def test_multimodal_myopic_policies_cannot_physically_run(mm):
    """fifo and greedy exceed the 800 kW service in the rush -- in the real world
    a tripped main or a brownout mid-turnaround, not a worse score.

    Scope of the claim, stated so it is never overquoted: MYOPIC PER-ASSET
    policies with no site-level view exceed the service. It does not say no
    other algorithm could stay under -- staying under while meeting deadlines
    requires seeing every modality's demand at once, and a policy that does so
    has become a site-level coordinator, which is the product. If a future
    myopic policy passes this, that is worth understanding, not suppressing.
    """
    for name in ("fifo", "greedy"):
        r = mm["policies"][name]
        assert r["physically_runnable"] is False, name
        assert r["exceeds_service_kw"] > 0, name


def test_multimodal_no_asset_books_an_incapable_point():
    """Capability is data and it binds every policy: aircraft never book car
    chargers, cars never book pads, drones only their pads."""
    import sys as _sys
    _sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))
    from assignment_policy import FifoPolicy, GreedyPolicy
    from forward import ForwardOrchestratorPolicy
    from harness import run_policy_traced
    from model import load_scenario

    sc_path = HERE.parent / "solvers" / "cpsat" / "scenario_vertiport.json"
    for cls in (FifoPolicy, GreedyPolicy, ForwardOrchestratorPolicy):
        sc = load_scenario(sc_path)
        _, state = run_policy_traced(sc, cls())
        kinds = {p["id"]: p["kind"] for p in sc["service_points"]}
        by_aid = {a.aid: a for a in sc["assets"]}
        for aid, pid, _, _ in state.bookings:
            allowed = tuple(sc["asset_classes"][by_aid[aid].cls].get(
                "charge_kinds", ("dcfc", "l2")))
            assert kinds[pid] in allowed, \
                f"{cls.__name__}: {aid} booked {pid} ({kinds[pid]}), allowed {allowed}"


def test_multimodal_artifact_is_deterministic_and_committed(mm):
    import json
    from forward import multimodal_comparison
    assert mm["multimodal_sha256"] == multimodal_comparison()["multimodal_sha256"]
    blob = json.dumps(mm, indent=1, sort_keys=True) + "\n"
    assert blob == (HERE / "multimodal_seed424242.json").read_text()


def test_multimodal_exclusions_carry_their_reasons(mm):
    assert "otto_q_asis" in mm["excluded"]
    assert "capability" in mm["excluded"]["otto_q_asis"]
    assert any("R-7" in a for a in mm["assumptions"])


def test_the_solver_knows_no_vertiport_vocabulary():
    """Kernel purity, asserted at the source level: the words that make this a
    vertiport (pad_charge, swap_dock, drone_pad, evtol, drone) appear in the
    SCENARIO and nowhere in the solver. If one leaks into model.py, a sector
    has entered the kernel and CLAUDE.md 2.2 calls that an escalation."""
    src = (HERE.parent / "solvers" / "cpsat" / "model.py").read_text()
    for word in ("pad_charge", "swap_dock", "drone_pad", "evtol", "vertiport"):
        assert word not in src, f"sector word {word!r} leaked into the kernel"
