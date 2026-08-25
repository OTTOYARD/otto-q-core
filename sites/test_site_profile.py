"""Tests for the SiteProfile and the portable tariff engine.

These lock in the claims the object is meant to make. Two of them are deliberately
regression locks on a KNOWN DEFECT rather than on correct behaviour: Site Alpha's
power cap is not binding, and that must stay visible until the benchmark moves to a
site where it is.
"""

from __future__ import annotations

import pytest

from sites import site_profile as sp
from sites.tariff import (
    DemandComponent,
    TariffError,
    Tier,
    TouWindow,
    load_tariff,
)


# ---- profiles load ---------------------------------------------------------------

def test_every_committed_profile_loads():
    ids = sp.available()
    assert ids, "no site profiles committed"
    for sid in ids:
        s = sp.get(sid)
        assert s.site_id == sid
        assert s.power_cap_kw() > 0


def test_unknown_site_names_what_is_available():
    with pytest.raises(sp.SiteProfileError) as e:
        sp.get("no_such_site")
    assert "site_alpha" in str(e.value)


# ---- the defect this object was built to expose ----------------------------------

def test_site_alpha_power_cap_is_NOT_binding():
    """REGRESSION LOCK ON A KNOWN DEFECT, not on desirable behaviour.

    Site Alpha carries 1,612 kW of installed chargers against a 3,000 kW cap. Every
    charger running flat out simultaneously draws 54% of the cap, so no schedule can
    violate it and a 'zero power-cap violations' result measures arithmetic rather
    than scheduling -- the vacuous claim withdrawn in docs/BENCHMARK_CREDIBILITY.md.
    If this test ever starts failing because the numbers changed, that is good news
    and the test should be retired deliberately, not silently.
    """
    s = sp.get("site_alpha")
    assert s.installed_charger_kw == 1612
    assert s.power_cap_kw() == 3000
    assert s.is_binding() is False
    assert s.oversubscription_ratio() == pytest.approx(0.537, abs=0.005)
    assert s.headroom_report()["within_r4_observed_band"] is False


def test_binding_variant_actually_binds():
    s = sp.get("site_alpha_binding")
    assert s.is_binding() is True
    # R-4 measures normal practice at ~2:1 to ~3.4:1.
    assert 2.0 <= s.oversubscription_ratio() <= 3.4
    assert s.headroom_report()["within_r4_observed_band"] is True


# ---- the two-level power model (R-4) ---------------------------------------------

def test_the_smallest_level_binds_and_is_named():
    s = sp.load_site({
        "site_id": "t", "name": "t",
        "grid": {"service_capacity_kw": 3000, "transformer_kw": 2500,
                 "switchgear_kw": 4000},
        "tariff": _minimal_tariff(),
    })
    assert s.power_cap_kw() == 2500
    assert s.grid.binding_level() == "transformer"


def test_safety_margin_reduces_the_cap():
    s = sp.load_site({
        "site_id": "t", "name": "t",
        "grid": {"service_capacity_kw": 1000, "safety_margin_pct": 10},
        "tariff": _minimal_tariff(),
    })
    assert s.power_cap_kw() == pytest.approx(900.0)


def test_a_site_without_a_service_capacity_is_refused():
    with pytest.raises(sp.SiteProfileError) as e:
        sp.load_site({"site_id": "t", "name": "t", "grid": {},
                      "tariff": _minimal_tariff()})
    assert "service_capacity_kw" in str(e.value)


# ---- storage sizing (the ENERGY-not-power correction) ----------------------------

def test_storage_is_duration_limited_and_says_so():
    s = sp.get("nashville_nes_gsa3_bess")
    assert s.storage.total_power_kw() == 4500          # 3 x 1500 kW
    assert s.storage.usable_kwh() == pytest.approx(7650.0)   # 3 x 3000 x 0.85
    # 7650 / 4500 = 1.70 h. The thesis correction: beyond ~1.7 h, ENERGY sets pack count.
    assert s.storage.duration_h() == pytest.approx(1.70, abs=0.01)
    # firm capacity during a wave, and only during one
    assert s.firm_capacity_kw() == 7500


# ---- the tariff object: interval is first-class (R-5) ----------------------------

def test_demand_component_without_interval_is_refused():
    """R-5 names interval_min the field most likely to be wrong if omitted."""
    with pytest.raises(TariffError) as e:
        load_tariff({
            "tariff_id": "t", "utility": "u", "schedule_code": "s",
            "energy": [{"rate_per_kwh": 0.05}],
            "demand": [{"label": "d", "rate_per_kw": 10.0}],
        })
    assert "interval_min" in str(e.value)


def test_15_and_30_minute_bases_bill_the_same_curve_differently():
    """The core R-5 claim, made mechanical.

    A short spike is averaged away more by a 30-minute meter than a 15-minute one, so
    a scheduler that assumes Nashville's 30-minute basis understates the peak on every
    Western depot. If this test ever passes trivially (both equal), the interval field
    has stopped doing anything and the object is Nashville-shaped again.
    """
    # 15 minutes at 2000 kW, then flat 200 kW for the rest of the hour.
    curve = [(0.0, 2000.0), (15.0, 200.0), (60.0, 200.0)]
    t15 = _tariff_with(interval=15)
    t30 = _tariff_with(interval=30)
    p15 = t15.bill(curve, month=7)["billed_peaks_kw"]["d"]
    p30 = t30.bill(curve, month=7)["billed_peaks_kw"]["d"]
    assert p15 == pytest.approx(2000.0)      # the whole spike lands in one interval
    assert p30 == pytest.approx(1100.0)      # averaged with the following 15 min
    assert p15 > p30


def test_tier_ladder_prices_nes_the_way_nes_does():
    """$21.40/kW for the first 1,000 kW, $21.78 above -- ONE quantity, two tiers."""
    comp = DemandComponent(
        label="d", basis="NCP", interval_min=30,
        tiers=(Tier(1000.0, 21.40), Tier(None, 21.78)),
    )
    assert comp.price(800) == pytest.approx(800 * 21.40)
    assert comp.price(1000) == pytest.approx(1000 * 21.40)
    assert comp.price(1500) == pytest.approx(1000 * 21.40 + 500 * 21.78)


def test_only_the_last_tier_may_be_unbounded():
    with pytest.raises(TariffError) as e:
        load_tariff({
            "tariff_id": "t", "utility": "u", "schedule_code": "s",
            "energy": [{"rate_per_kwh": 0.05}],
            "demand": [{"label": "d", "interval_min": 30,
                        "tiers": [{"up_to_kw": None, "rate": 1.0},
                                  {"up_to_kw": 100, "rate": 2.0}]}],
        })
    assert "LAST tier" in str(e.value)


# ---- ratchets: Nashville is lenient, Atlanta is not ------------------------------

def test_atlanta_ratchet_holds_the_bill_up_where_nashville_does_not():
    """The scheduling consequence of a 95% vs a 30% floor, in dollars.

    Same peaky curve, same flattened curve, same historical peak. Under NES's 30%
    floor the flattening is realised almost in full. Under Georgia Power's 95% floor
    the floor itself becomes the bill, so flattening THIS month recovers little -- the
    money was lost when the peak was first set. That asymmetry is the argument for a
    forward view, and it falls out of the object rather than being asserted.
    """
    peaky = [(float(m), 2800.0 if m < 240 else 100.0) for m in range(0, 1440, 15)]
    flat = [(float(m), 1400.0 if m < 480 else 100.0) for m in range(0, 1440, 15)]

    nes = sp.get("site_alpha").tariff
    gap = sp.get("atlanta_georgia_power").tariff

    nes_saving = (nes.bill(peaky, month=7, historical_peak_kw=2800)["total"]
                  - nes.bill(flat, month=7, historical_peak_kw=2800)["total"])
    gap_saving = (gap.bill(peaky, month=7, historical_peak_kw=2800)["total"]
                  - gap.bill(flat, month=7, historical_peak_kw=2800)["total"])

    assert nes_saving > 0 and gap_saving > 0
    # Nashville's 30% floor (840 kW) is below the flattened peak, so the drop lands.
    # Atlanta's 95% floor (2,660 kW) is above it, so it does not.
    assert nes.bill(flat, month=7, historical_peak_kw=2800)["billed_peaks_kw"][
        "max demand (summer)"] == pytest.approx(1400.0)
    assert gap.bill(flat, month=7, historical_peak_kw=2800)["billed_peaks_kw"][
        "billing demand"] == pytest.approx(2660.0)


# ---- TOU demand, and the honest refusal on coincident peak -----------------------

def test_tou_demand_component_prices_only_its_own_window():
    t = sp.get("phoenix_aps_e35").tariff
    # 3000 kW inside the modelled on-peak window (16:00-19:00), 500 kW outside it.
    curve = [(float(m), 3000.0 if 960 <= m < 1140 else 500.0)
             for m in range(0, 1440, 15)]
    peaks = t.bill(curve, month=7)["billed_peaks_kw"]
    assert peaks["on-peak demand"] == pytest.approx(3000.0)
    assert peaks["off-peak demand"] == pytest.approx(500.0)


def test_coincident_peak_refuses_to_guess():
    t = load_tariff({
        "tariff_id": "t", "utility": "u", "schedule_code": "s",
        "energy": [{"rate_per_kwh": 0.05}],
        "demand": [{"label": "cp", "basis": "CP", "interval_min": 30,
                    "rate_per_kw": 10.0}],
    })
    with pytest.raises(TariffError) as e:
        t.bill([(0.0, 100.0), (60.0, 100.0)], month=7)
    assert "cannot be inferred" in str(e.value)


def test_tariff_naming_an_undefined_window_is_refused():
    with pytest.raises(TariffError) as e:
        load_tariff({
            "tariff_id": "t", "utility": "u", "schedule_code": "s",
            "energy": [{"rate_per_kwh": 0.05}],
            "demand": [{"label": "d", "basis": "TOU", "tou_window": "on",
                        "interval_min": 15, "rate_per_kw": 10.0}],
        })
    assert "does not define" in str(e.value)


def test_a_tariff_that_cannot_price_every_hour_is_refused():
    with pytest.raises(TariffError):
        load_tariff({"tariff_id": "t", "utility": "u", "schedule_code": "s",
                     "energy": []})


def test_wrapping_tou_window_covers_midnight():
    w = TouWindow("off", ((1140, 960),))
    assert w.contains(1200) and w.contains(30) and not w.contains(1000)


# ---- helpers ---------------------------------------------------------------------

def _minimal_tariff() -> dict:
    return {"tariff_id": "t", "utility": "u", "schedule_code": "s",
            "energy": [{"rate_per_kwh": 0.05}]}


def _tariff_with(interval: int):
    return load_tariff({
        "tariff_id": f"t{interval}", "utility": "u", "schedule_code": "s",
        "energy": [{"rate_per_kwh": 0.05}],
        "demand": [{"label": "d", "interval_min": interval, "rate_per_kw": 10.0}],
    })


# ---- R-6 corrections: primary windows, hours-use blocks, the daily shape ---------

def test_phoenix_window_is_the_primary_tariffs_not_the_old_assumption():
    """R-6 read the APS E-35 PDF: on-peak 11:00-21:00 WEEKDAYS, year-round. The
    repo's original 16:00-19:00 assumption was wrong by a factor of 3.3 in window
    length -- exactly what the labeled assumption existed to catch."""
    t = sp.get("phoenix_aps_e35").tariff
    on = t.window("on")
    assert on.ranges == ((660, 1260),)
    assert on.days == "weekdays"


def test_atlanta_hours_use_blocks_price_the_primary_table():
    """PLL-18 verbatim: 18.943 c first 3,000 kWh ... 1.101 c beyond 600 hours-use."""
    hub = sp.get("atlanta_georgia_power").tariff.hours_use_blocks
    assert hub is not None
    # 100 kW billing demand, 10,000 kWh -> hours-use 100, all within 200h x demand
    cost = hub.energy_cost(10_000, 100.0)
    assert cost == pytest.approx(3000 * 0.189430 + 7000 * 0.171794)
    # high load factor pushes energy into the ~1-2c tail: 100 kW, 50,000 kWh = 500h
    lo = hub.energy_cost(50_000, 100.0)
    within = hub.energy_cost(20_000, 100.0)          # exactly 200h
    tail = lo - within
    # 20,000 kWh sits in the 200-400h block, 10,000 in the 400-600h block
    assert tail == pytest.approx(20_000 * 0.019458 + 10_000 * 0.014671)


def test_atlanta_min_bill_is_a_floor_not_a_charge_on_top():
    """R-6: $13.63/kW is the minimum-bill floor. A low-load-factor customer pays
    the floor; a high-load-factor customer pays the blocks."""
    t = sp.get("atlanta_georgia_power").tariff
    # tiny energy, big demand -> floor binds
    spiky = [(0.0, 500.0), (30.0, 0.0), (1440.0, 0.0)]
    b = t.bill(spiky, month=7, days=30, historical_peak_kw=0.0)
    assert b["floor_binding"] is True
    assert b["total"] == pytest.approx(b["min_bill_floor"] + b["fixed_cost"])
    # sustained load -> blocks exceed the floor
    flat = [(float(m), 400.0) for m in range(0, 1440, 60)] + [(1440.0, 400.0)]
    b2 = t.bill(flat, month=7, days=30, historical_peak_kw=0.0)
    assert b2["floor_binding"] is False
    assert b2["energy_cost"] > b2["min_bill_floor"]


def test_atlanta_high_load_factor_is_rewarded_per_kwh():
    """The whole point of declining hours-use blocks: more hours at the same
    demand -> cheaper average energy. If this inverts, the block order broke."""
    t = sp.get("atlanta_georgia_power").tariff
    lo_lf = [(float(m), 400.0 if m < 240 else 0.0) for m in range(0, 1440, 15)] + [(1440.0, 0.0)]
    hi_lf = [(float(m), 400.0 if m < 960 else 0.0) for m in range(0, 1440, 15)] + [(1440.0, 0.0)]
    b_lo = t.bill(lo_lf, month=7, days=30, historical_peak_kw=0.0)
    b_hi = t.bill(hi_lf, month=7, days=30, historical_peak_kw=0.0)
    per_kwh_lo = b_lo["energy_cost"] / (400 * 4 * 30)
    per_kwh_hi = b_hi["energy_cost"] / (400 * 16 * 30)
    assert per_kwh_hi < per_kwh_lo


def test_las_vegas_daily_demand_and_seasonal_split():
    """LGS-2 from primary figures (R-6 corrected R-5's third-party $2.68 to
    $13.43): summer on-peak demand is billed only in summer, winter demand is
    $1.65, facilities year-round -- the same curve bills very differently by month."""
    t = sp.get("las_vegas_nv_lgs2").tariff
    curve = [(float(m), 1000.0 if 901 <= m < 1260 else 200.0)
             for m in range(0, 1440, 15)] + [(1440.0, 200.0)]
    summer = t.bill(curve, month=7, days=30, historical_peak_kw=1000)
    winter = t.bill(curve, month=1, days=30, historical_peak_kw=1000)
    assert "summer on-peak demand" in summer["billed_peaks_kw"]
    assert "summer on-peak demand" not in winter["billed_peaks_kw"]
    assert summer["demand_cost"] > winter["demand_cost"]
