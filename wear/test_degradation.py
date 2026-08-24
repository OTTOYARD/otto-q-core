"""Tests for the derived wear layer.

The point of most of these is PROVENANCE DISCIPLINE, not numerics: the model must
refuse where R-3 records NOT FOUND, and must flag results that rest on R-3's inferred
f_soc table. A degradation model whose weakest number is indistinguishable from its
strongest is a model that will eventually be quoted as fact.
"""

from __future__ import annotations

import pytest

from wear.degradation import (
    CHEMISTRIES,
    G_RATE_CHARGE,
    G_RATE_DISCHARGE,
    H_TEMP_TABLE,
    LFP,
    NMC,
    ExposureRecord,
    NotFoundError,
    arrhenius,
    assess,
    calendar_fade,
    f_soc,
    plating_risk,
    provenance_report,
    soc_park_saving,
)


# ---- the model refuses where the literature has no answer ------------------------

def test_charge_side_smooth_rate_multiplier_is_refused():
    """R-3 Q4 records this as NOT FOUND and recommends a plating gate instead."""
    assert G_RATE_CHARGE.provenance == "not_found"
    with pytest.raises(NotFoundError) as e:
        G_RATE_CHARGE.require("charge g_rate")
    assert "refuses" in str(e.value)


def test_temperature_multiplier_table_is_refused():
    assert H_TEMP_TABLE.provenance == "not_found"
    with pytest.raises(NotFoundError):
        H_TEMP_TABLE.require("h_temp")


def test_provenance_report_names_what_it_will_not_compute():
    rep = provenance_report()
    assert set(rep["refuses_to_compute"]) == {"charge g_rate (smooth)", "h_temp table"}
    assert "f_soc multipliers" in rep["rests_on_inference"]


def test_discharge_rate_is_a_measured_near_null_not_a_placeholder():
    """1.0 here means "measured to barely matter", which is different from "unknown"."""
    assert G_RATE_DISCHARGE.provenance == "primary"
    assert G_RATE_DISCHARGE.require("discharge") == 1.0


def test_a_coefficient_cannot_carry_an_unknown_provenance():
    from wear.degradation import Coefficient
    with pytest.raises(ValueError):
        Coefficient(1.0, "x", "vibes", "nowhere")


# ---- the plating gate is a regime, not a curve -----------------------------------

def test_plating_gate_returns_regimes():
    assert plating_risk(NMC, temp_c=-5, c_rate=1.0) == "severe"
    assert plating_risk(NMC, temp_c=5, c_rate=1.0) == "elevated"
    assert plating_risk(NMC, temp_c=20, c_rate=1.0) == "none"
    # slow charging in the cold band is not gated -- the threshold is ~0.5C
    assert plating_risk(NMC, temp_c=5, c_rate=0.2) == "none"
    # not charging cannot plate
    assert plating_risk(NMC, temp_c=-30, c_rate=0.0) == "none"


def test_lfp_tipping_point_is_lower_than_nmc():
    """R-3: LFP shows a tipping point at 5-10 C; NMC's cold band reaches ~10 C."""
    assert LFP.plating_temp_c < NMC.plating_temp_c
    assert plating_risk(NMC, temp_c=9, c_rate=1.0) == "elevated"
    assert plating_risk(LFP, temp_c=9, c_rate=1.0) == "none"


# ---- the two levers --------------------------------------------------------------

def test_parking_lower_cuts_calendar_fade_within_R3s_stated_band():
    """R-3 Q2: parking at 50% instead of 90-100% cuts NMC calendar fade ~2-5x."""
    ratio = soc_park_saving(NMC, from_soc_pct=100, to_soc_pct=50)
    assert 2.0 <= ratio <= 5.0
    # LFP's 100% rise is milder, which the tables must preserve
    assert soc_park_saving(LFP, from_soc_pct=100, to_soc_pct=50) < ratio


def test_f_soc_is_flat_below_the_step_and_rises_above_it():
    assert f_soc(NMC, 30) == pytest.approx(f_soc(NMC, 50))
    assert f_soc(NMC, 90) > f_soc(NMC, 50)
    assert f_soc(NMC, 100) > f_soc(NMC, 90)
    # clamped outside the table rather than extrapolated
    assert f_soc(NMC, 5) == f_soc(NMC, 30)
    assert f_soc(NMC, 120) == f_soc(NMC, 100)


def test_arrhenius_is_normalised_to_25C():
    assert arrhenius(NMC, 25) == pytest.approx(1.0)
    assert arrhenius(NMC, 40) > 1.0        # hotter ages faster
    assert arrhenius(NMC, 10) < 1.0
    # LFP's lower activation energy makes it less temperature-sensitive
    assert arrhenius(LFP, 40) < arrhenius(NMC, 40)


def test_calendar_fade_follows_sqrt_time_by_default():
    a = calendar_fade(NMC, soc_pct=50, temp_c=25, hours=100)
    b = calendar_fade(NMC, soc_pct=50, temp_c=25, hours=400)
    assert b / a == pytest.approx(2.0)                 # sqrt(4x) = 2x
    # R-3 Q3 notes the most-cited empirical fits use 0.75, so it is a parameter
    c = calendar_fade(NMC, soc_pct=50, temp_c=25, hours=400, time_exponent=0.75)
    assert c > b


def test_calendar_fade_rejects_negative_time():
    with pytest.raises(ValueError):
        calendar_fade(NMC, soc_pct=50, temp_c=25, hours=-1)


# ---- derived from captured exposure ----------------------------------------------

def _rec(**kw) -> ExposureRecord:
    base = dict(asset_id="v1", chemistry="NMC", battery_kwh=100.0,
                soc_start_pct=20.0, soc_end_pct=80.0, energy_delivered_kwh=60.0,
                peak_power_kw=100.0, ambient_temp_c=20.0, duration_h=1.0)
    base.update(kw)
    return ExposureRecord(**base)


def test_equivalent_full_cycles_accumulate_from_throughput():
    out = assess([_rec(), _rec()])
    assert out[0].equivalent_full_cycles == pytest.approx(1.2)   # 2 x 60/100


def test_cold_fast_sessions_are_counted_as_regime_events():
    out = assess([_rec(ambient_temp_c=-5), _rec(ambient_temp_c=5), _rec()])
    assert out[0].severe_plating_events == 1
    assert out[0].plating_events == 1
    assert any("REGIME" in n for n in out[0].notes)


def test_calendar_results_are_flagged_as_resting_on_inference():
    """The weakest number in the model must not look like the strongest."""
    out = assess([_rec()], parked_hours=100.0, parked_soc_pct=90.0)
    assert out[0].calendar_fade_rel > 0
    assert out[0].inference_flags
    assert "INFERENCE" in out[0].inference_flags[0]
    assert out[0].as_row()["rests_on_inference"] is True


def test_no_parked_period_means_no_calendar_claim_and_no_flag():
    out = assess([_rec()])
    assert out[0].calendar_fade_rel == 0.0
    assert out[0].inference_flags == []


def test_parked_soc_defaults_to_what_the_asset_actually_sat_at():
    hi = assess([_rec(soc_end_pct=100.0)], parked_hours=100.0)[0].calendar_fade_rel
    lo = assess([_rec(soc_end_pct=50.0)], parked_hours=100.0)[0].calendar_fade_rel
    assert hi > lo


def test_an_unknown_chemistry_is_refused_by_name():
    with pytest.raises(ValueError) as e:
        assess([_rec(chemistry="NiMH")])
    assert "NiMH" in str(e.value) and "NMC" in str(e.value)


def test_assessments_are_per_asset():
    out = assess([_rec(asset_id="a"), _rec(asset_id="b"), _rec(asset_id="b")])
    assert [a.asset_id for a in out] == ["a", "b"]
    assert out[1].equivalent_full_cycles > out[0].equivalent_full_cycles


def test_c_rate_comes_from_power_over_capacity():
    assert _rec(peak_power_kw=150.0, battery_kwh=100.0).c_rate() == pytest.approx(1.5)
    assert _rec(battery_kwh=0.0).c_rate() == 0.0


def test_every_chemistry_carries_a_sourced_activation_energy():
    for name, chem in CHEMISTRIES.items():
        assert chem.activation_energy.provenance == "primary", name
        assert "doi" in chem.activation_energy.source, name
