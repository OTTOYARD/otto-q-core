"""Tests for onboard() in sizing mode.

The claims under test are physical, so most of these are arithmetic identities rather
than golden values: if the model drifts from the physics these stop holding.
"""

from __future__ import annotations

import math

import pytest

from onboarding.sizer import (
    FleetClass,
    FleetSpec,
    evaluate,
    load_fleet,
    service_points_needed,
    size,
    unservable_classes,
    to_site_profile,
)
from sites import site_profile as sp


def _fleet(**kw) -> FleetSpec:
    base = dict(
        fleet_id="t", service_window_h=8.0, base_load_kw=0.0,
        classes=(FleetClass("c", count=10, battery_kwh=100, max_charge_kw=100,
                            arrive_soc_pct=20, target_soc_pct=80,
                            taper_efficiency=1.0),),
    )
    base.update(kw)
    return FleetSpec(**base)


# ---- the physics -----------------------------------------------------------------

def test_energy_is_soc_delta_times_battery_times_count():
    f = _fleet()
    # 60% of 100 kWh = 60 kWh per asset, 10 assets = 600 kWh
    assert f.energy_per_day_kwh() == pytest.approx(600.0)


def test_flat_load_floor_is_energy_over_window_plus_base():
    f = _fleet(base_load_kw=50.0)
    # 600 kWh / 8 h = 75 kW, plus 50 kW base
    assert f.flat_load_floor_kw() == pytest.approx(125.0)


def test_unmanaged_peak_is_everything_at_once():
    f = _fleet(base_load_kw=50.0)
    assert f.unmanaged_peak_kw() == pytest.approx(10 * 100 + 50)


def test_the_floor_is_always_evaluated_even_if_the_caller_steps_over_it():
    """A sweep that misses the floor silently recommends buying more service."""
    f = _fleet()
    t = sp.get("site_alpha").tariff
    r = size(f, t, grid_options_kw=[10.0, 1000.0])   # deliberately straddles 75 kW
    assert any(c.grid_kw == pytest.approx(f.flat_load_floor_kw()) for c in r.candidates)
    assert r.recommended.grid_kw == pytest.approx(f.flat_load_floor_kw())


def test_at_or_above_the_floor_no_storage_is_needed():
    f = _fleet()
    t = sp.get("site_alpha").tariff
    c = evaluate(f, f.flat_load_floor_kw(), t)
    assert c.feasible
    assert c.storage_energy_kwh == 0.0
    assert c.billed_peak_kw == pytest.approx(f.flat_load_floor_kw())


# ---- the trap the model exists to catch ------------------------------------------

def test_storage_recharge_counts_toward_the_billed_peak():
    """Shaving the window and then recharging hard MOVES the peak, it does not remove it.

    This is the single most expensive mistake available in a battery-buffered design,
    and a sizing tool that ignored recharge would recommend it confidently.
    """
    f = _fleet(base_load_kw=200.0)          # floor = 75 + 200 = 275 kW
    t = sp.get("site_alpha").tariff
    c = evaluate(f, 220.0, t)               # ask for a service below the floor
    assert c.storage_energy_kwh > 0
    assert c.recharge_kw > 0
    # base load alone already exceeds the requested service once recharge is added
    assert c.billed_peak_kw > 220.0
    assert c.feasible is False
    assert "recharge sets the billed peak" in c.infeasible_reason


def test_a_window_covering_the_whole_day_cannot_recharge_storage():
    f = _fleet(service_window_h=24.0)
    t = sp.get("site_alpha").tariff
    c = evaluate(f, f.flat_load_floor_kw() * 0.5, t)
    assert c.feasible is False
    assert "never recharge" in c.infeasible_reason


def test_storage_energy_accounts_for_round_trip_losses():
    f = _fleet()                              # floor 75 kW, window 8 h
    t = sp.get("site_alpha").tariff
    c = evaluate(f, 55.0, t, round_trip_efficiency=0.5)
    # deficit 20 kW x 8 h = 160 kWh delivered; at 50% RTE that needs 320 kWh stored
    assert c.deficit_kwh == pytest.approx(160.0)
    assert c.storage_energy_kwh == pytest.approx(320.0)


# ---- point counts ----------------------------------------------------------------

def test_points_scale_with_charge_hours():
    # 10 assets x 0.6 h = 6 point-hours over an 8 h window -> one point suffices
    assert service_points_needed(_fleet())["c"] == 1
    # double the energy per asset and the point-hours no longer fit on one point
    heavy = _fleet(classes=(FleetClass("c", count=10, battery_kwh=200,
                                       max_charge_kw=100, arrive_soc_pct=20,
                                       target_soc_pct=80, taper_efficiency=1.0),))
    assert service_points_needed(heavy)["c"] == 2


def test_an_asset_whose_session_exceeds_the_window_needs_its_own_point():
    f = _fleet(service_window_h=0.5,
               classes=(FleetClass("c", count=7, battery_kwh=100, max_charge_kw=100,
                                   arrive_soc_pct=20, target_soc_pct=80,
                                   taper_efficiency=1.0),))
    # each session is 0.6 h > the 0.5 h window. Every asset needs its own point --
    # and never MORE than one each, which is the bug this locks out.
    assert service_points_needed(f)["c"] == 7
    # and no point count actually fixes it, so it is reported as unservable
    assert "c" in unservable_classes(f)


def test_taper_lengthens_sessions_and_so_needs_more_points():
    fast = _fleet()
    slow = _fleet(classes=(FleetClass("c", count=10, battery_kwh=100, max_charge_kw=100,
                                      arrive_soc_pct=20, target_soc_pct=80,
                                      taper_efficiency=0.5),))
    assert service_points_needed(slow)["c"] > service_points_needed(fast)["c"]


# ---- the tariff actually changes the answer --------------------------------------

def test_the_same_fleet_costs_different_amounts_in_different_metros():
    """If this ever equalises, the tariff has stopped reaching the sizing decision."""
    f = _fleet(base_load_kw=100.0)
    costs = {
        sid: size(f, sp.get(sid).tariff).recommended.annual_cost_usd
        for sid in ("site_alpha", "atlanta_georgia_power", "phoenix_aps_e35")
    }
    assert len(set(round(v) for v in costs.values())) == 3
    # An overnight window sits in Phoenix's cheap off-peak demand band, so a TOU
    # tariff should beat Nashville's flat $21.40/kW for this load shape.
    assert costs["phoenix_aps_e35"] < costs["site_alpha"]


# ---- the loop closes: sizing emits a SiteProfile ---------------------------------

def test_sizing_emits_a_runnable_site_profile():
    f = _fleet(base_load_kw=100.0)
    t_doc = _tariff_doc()
    r = size(f, sp.get("site_alpha").tariff)
    site = to_site_profile(f, r, t_doc, site_id="emitted", name="Emitted")
    assert site.site_id == "emitted"
    assert site.power_cap_kw() == pytest.approx(round(r.recommended.grid_kw))
    # the emitted profile is a real SiteProfile and answers the same questions
    assert "oversubscription_ratio" in site.headroom_report()


def test_emitted_profile_carries_storage_in_whole_units_when_storage_is_needed():
    f = _fleet(base_load_kw=0.0)
    t = sp.get("site_alpha").tariff
    r = size(f, t, grid_options_kw=[f.flat_load_floor_kw() * 0.8])
    if r.recommended and r.recommended.storage_energy_kwh > 0:
        site = to_site_profile(f, r, _tariff_doc(), site_id="e2", name="E2")
        assert site.storage is not None
        assert site.storage.units >= 1
        assert float(site.storage.units).is_integer()


def test_emitting_without_a_feasible_candidate_raises():
    f = _fleet(service_window_h=24.0)
    t = sp.get("site_alpha").tariff
    r = size(f, t, grid_options_kw=[1.0])
    if r.recommended is None:
        with pytest.raises(ValueError):
            to_site_profile(f, r, _tariff_doc(), site_id="x", name="X")


# ---- loading ---------------------------------------------------------------------

def test_load_fleet_round_trips():
    f = load_fleet({
        "fleet_id": "f", "service_window_h": 6, "base_load_kw": 10,
        "classes": [{"asset_class": "a", "count": 3, "battery_kwh": 50,
                     "max_charge_kw": 25}],
    })
    assert f.fleet_id == "f" and f.classes[0].count == 3
    assert f.classes[0].taper_efficiency == 0.80     # documented default


def test_capital_cost_is_declared_absent_not_invented():
    f = _fleet()
    r = size(f, sp.get("site_alpha").tariff)
    assert any("CAPITAL COST IS NOT INCLUDED" in n for n in r.notes)


def _tariff_doc() -> dict:
    return {
        "tariff_id": "nes_gsa3", "utility": "NES", "schedule_code": "GSA-3",
        "energy": [{"rate_per_kwh": 0.04785}],
        "demand": [{"label": "max demand", "interval_min": 30,
                    "tiers": [{"up_to_kw": 1000, "rate": 21.40},
                              {"up_to_kw": None, "rate": 21.78}]}],
        "ratchet": {"percent": 30, "lookback_months": 12},
    }
