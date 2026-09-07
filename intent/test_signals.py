"""Tests for the signal bridge — forecast -> regime signals.

Run:  python3 -m pytest intent/test_signals.py -q

The forecast dict used here is a SYNTHETIC forecast in the exact contract shape
the /forecast endpoint returns (arrivals + load sections, each with an `hours`
list keyed by hour_of_day). The bridge is tested against the SHAPE without
reading production data — the same separation discipline as the proposer tests.
Every assertion below is about (a) the signal math, (b) the honest threshold
provenance, (c) the TOTAL seam (a malformed forecast raises, never silently
defaults), and (d) the end-to-end loop into resolve_intent.
"""

from intent.intent import load_intent, resolve_intent
from intent.signals import (
    EVIDENCE_LABELS,
    SIGNAL_THRESHOLDS,
    ForecastContractError,
    forecast_signals,
)


def _forecast(mean_daily_arrivals=24.0, per_hour_arrivals=None,
              load_p90=None, horizon_hours=24):
    """A synthetic 24h forecast in the /forecast contract shape.

    Default: flat 1.0 arrival/hour (mean 24/day) and flat 100 kW p90 load —
    both below any default trigger, so each test opts IN to the signal it
    exercises.
    """
    per_hour_arrivals = per_hour_arrivals or {}
    load_p90 = load_p90 or {}
    hours_arr, hours_load = [], []
    for hod in range(horizon_hours):
        arr = per_hour_arrivals.get(hod, 1.0)
        kw = load_p90.get(hod, 100.0)
        hours_arr.append({"hour_index": hod, "hour_of_day": hod,
                          "expected_arrivals": arr, "p10": 0,
                          "p50": int(arr), "p90": int(arr) + 1})
        hours_load.append({"hour_index": hod, "hour_of_day": hod,
                           "base_kw": 50.0, "ev_kw_expected": 50.0,
                           "total_kw_p50": kw, "total_kw_p10": kw * 0.5,
                           "total_kw_p90": kw})
    return {
        "arrivals": {"kind": "arrivals", "horizon_hours": horizon_hours,
                     "start_hour": 0, "dow": 0,
                     "mean_daily_arrivals": mean_daily_arrivals,
                     "hours": hours_arr, "provenance": {}},
        "load": {"kind": "load", "horizon_hours": horizon_hours,
                 "start_hour": 0, "dow": 0, "base_load_kw": 50.0,
                 "ev_daily_sessions": 24.0, "hours": hours_load,
                 "provenance": {}},
    }


# ---- the signal math -------------------------------------------------------------

def test_demand_surge_triggers_when_arrivals_double_the_mean():
    # mean 24/day -> 1.0/hr; 3 arrivals/hr in the next 3 hours -> 9 vs threshold 6
    fc = _forecast(mean_daily_arrivals=24.0,
                   per_hour_arrivals={0: 3.0, 1: 3.0, 2: 3.0})
    a = forecast_signals(fc, site_power_target_kw=700, now_hour=0)
    assert "demand_surge" in a.signals
    assert a.reasoning["demand_surge"]["value"] == 9.0
    assert a.reasoning["demand_surge"]["threshold"] == 6.0


def test_demand_surge_stays_quiet_at_the_mean():
    a = forecast_signals(_forecast(mean_daily_arrivals=24.0),
                         site_power_target_kw=700, now_hour=0)
    assert "demand_surge" not in a.signals


def test_grid_peak_triggers_when_p90_approaches_the_soft_target():
    fc = _forecast(load_p90={0: 700.0, 1: 700.0})   # p90 at the soft target
    a = forecast_signals(fc, site_power_target_kw=700, now_hour=0)
    assert "grid_peak_imminent" in a.signals        # 700 >= 0.9*700
    assert a.reasoning["grid_peak_imminent"]["threshold"] == 630.0


def test_grid_peak_stays_quiet_below_the_approach_fraction():
    a = forecast_signals(_forecast(load_p90={0: 600.0}),
                         site_power_target_kw=700, now_hour=0)
    assert "grid_peak_imminent" not in a.signals    # 600 < 630


def test_weather_hold_is_passed_through_not_derived():
    assert "weather_hold" in forecast_signals(
        _forecast(), site_power_target_kw=700, now_hour=0,
        weather_hold=True).signals
    assert "weather_hold" not in forecast_signals(
        _forecast(), site_power_target_kw=700, now_hour=0).signals


def test_bridge_is_deterministic():
    fc = _forecast(per_hour_arrivals={0: 3.0, 1: 3.0, 2: 3.0})
    a = forecast_signals(fc, site_power_target_kw=700, now_hour=0)
    b = forecast_signals(fc, site_power_target_kw=700, now_hour=0)
    assert a == b and a.signals == b.signals and a.reasoning == b.reasoning


def test_window_wraps_midnight():
    # surge at 23:00 spans 23, 0, 1 (wrapped); mean 24/day -> baseline 6
    fc = _forecast(mean_daily_arrivals=24.0,
                   per_hour_arrivals={23: 3.0, 0: 3.0, 1: 3.0})
    a = forecast_signals(fc, site_power_target_kw=700, now_hour=23)
    assert "demand_surge" in a.signals
    assert a.reasoning["demand_surge"]["value"] == 9.0


def test_threshold_override_is_honored():
    fc = _forecast(mean_daily_arrivals=24.0)         # flat 1.0/hr -> sum 3
    assert "demand_surge" not in forecast_signals(
        fc, site_power_target_kw=700, now_hour=0).signals
    # lower the multiplier to 1.0 -> threshold 3.0 -> a flat window now surges
    a = forecast_signals(fc, site_power_target_kw=700, now_hour=0,
                         thresholds={"surge_multiplier": 1.0})
    assert "demand_surge" in a.signals
    assert a.thresholds["surge_multiplier"] == 1.0


# ---- the TOTAL seam: malformed input raises, never silently defaults ------------

def test_a_missing_section_raises():
    fc = _forecast()
    del fc["arrivals"]
    try:
        forecast_signals(fc, site_power_target_kw=700, now_hour=0)
        raise AssertionError("missing arrivals did not raise")
    except ForecastContractError as e:
        assert "arrivals" in str(e)


def test_an_empty_hours_list_raises():
    fc = _forecast()
    fc["load"]["hours"] = []
    try:
        forecast_signals(fc, site_power_target_kw=700, now_hour=0)
        raise AssertionError("empty load hours did not raise")
    except ForecastContractError:
        pass


def test_a_missing_value_field_raises_instead_of_treating_it_as_zero():
    fc = _forecast(load_p90={0: 900.0})              # a real peak
    del fc["load"]["hours"][0]["total_kw_p90"]       # but the field is gone
    try:
        forecast_signals(fc, site_power_target_kw=700, now_hour=0)
        raise AssertionError("missing total_kw_p90 was silently zeroed")
    except ForecastContractError as e:
        assert "total_kw_p90" in str(e)


def test_a_window_past_coverage_raises():
    fc = _forecast(horizon_hours=12)                 # hours 0..11 only
    try:
        forecast_signals(fc, site_power_target_kw=700, now_hour=22)
        raise AssertionError("out-of-coverage window did not raise")
    except ForecastContractError:
        pass


def test_an_unknown_threshold_override_raises():
    try:
        forecast_signals(_forecast(), site_power_target_kw=700, now_hour=0,
                         thresholds={"bogus": 1.0})
        raise AssertionError("unknown threshold did not raise")
    except ValueError as e:
        assert "bogus" in str(e)


def test_now_hour_is_bounds_checked():
    import pytest
    for bad in (-1, 24, "7"):
        with pytest.raises(ValueError):
            forecast_signals(_forecast(), site_power_target_kw=700,
                             now_hour=bad)


# ---- threshold provenance: no invented numbers --------------------------------

def test_every_threshold_names_its_grounding_or_absence():
    assert set(SIGNAL_THRESHOLDS) == {
        "surge_multiplier", "surge_window_hours", "peak_fraction",
        "peak_window_hours"}
    for name, t in SIGNAL_THRESHOLDS.items():
        assert t.evidence_label in EVIDENCE_LABELS, name
        assert t.source, f"{name} has no source"
        assert "must-measure" in t.source or t.evidence_label != "inference", \
            f"{name} inference without a must-measure flag"


# ---- the loop closes: forecast -> signals -> regime --------------------------

def test_bridge_signals_feed_resolve_intent_end_to_end():
    it = load_intent()
    # a hot window at 07:00 (dispatch_rush hours) must resolve to demand_surge,
    # not dispatch_rush — the precedence fix + the bridge working together.
    fc = _forecast(mean_daily_arrivals=24.0,
                   per_hour_arrivals={7: 3.0, 8: 3.0, 9: 3.0})
    a = forecast_signals(fc, site_power_target_kw=700, now_hour=7)
    assert "demand_surge" in a.signals
    active = resolve_intent(it, hour_of_day=7, signals=a.signals)
    assert active.regime_key == "demand_surge"

    # a load peak at 07:00 resolves to grid_peak
    fc2 = _forecast(load_p90={7: 700.0, 8: 700.0})
    b = forecast_signals(fc2, site_power_target_kw=700, now_hour=7)
    assert "grid_peak_imminent" in b.signals
    assert resolve_intent(it, hour_of_day=7,
                          signals=b.signals).regime_key == "grid_peak"

    # no signal at 07:00 -> the normal clock regime
    c = forecast_signals(_forecast(), site_power_target_kw=700, now_hour=7)
    assert c.signals == frozenset()
    assert resolve_intent(it, hour_of_day=7,
                          signals=c.signals).regime_key == "dispatch_rush"


if __name__ == "__main__":
    for fn in [v for k, v in sorted(globals().items()) if k.startswith("test_")]:
        fn()
        print(f"{fn.__name__} PASS")
    print("ALL SIGNAL BRIDGE TESTS PASS")
