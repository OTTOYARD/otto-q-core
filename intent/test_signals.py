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

import os
from pathlib import Path

import pytest

from intent.intent import load_intent, resolve_intent
from intent.signals import (
    EVIDENCE_LABELS,
    SIGNAL_THRESHOLDS,
    ForecastContractError,
    forecast_signals,
)


def _forecast(mean_daily_arrivals=24.0, per_hour_arrivals=None,
              load_p90=None, horizon_hours=24, per_hour_baseline=None):
    """A synthetic 24h forecast in the /forecast contract shape.

    Default: flat 1.0 arrival/hour (mean 24/day) and flat 100 kW p90 load —
    both below any default trigger, so each test opts IN to the signal it
    exercises.

    `expected_arrivals` is the NOWCAST and `baseline_arrivals` the
    CLIMATOLOGICAL expectation for that hour. They default to the same flat
    rate, which is what a pure-climatology forecaster emits: no deviation, no
    surge. A test that wants a surge raises the nowcast above the baseline.
    """
    per_hour_arrivals = per_hour_arrivals or {}
    per_hour_baseline = per_hour_baseline or {}
    load_p90 = load_p90 or {}
    hours_arr, hours_load = [], []
    for hod in range(horizon_hours):
        arr = per_hour_arrivals.get(hod, 1.0)
        base = per_hour_baseline.get(hod, 1.0)
        kw = load_p90.get(hod, 100.0)
        hours_arr.append({"hour_index": hod, "hour_of_day": hod,
                          "expected_arrivals": arr,
                          "baseline_arrivals": base, "p10": 0,
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

def test_demand_surge_triggers_when_arrivals_double_their_own_baseline():
    # baseline 1.0/hr; nowcast 3.0/hr over the next 3 hours -> 9 vs threshold 6
    fc = _forecast(per_hour_arrivals={0: 3.0, 1: 3.0, 2: 3.0})
    a = forecast_signals(fc, site_power_target_kw=700, now_hour=0)
    assert "demand_surge" in a.signals
    assert a.reasoning["demand_surge"]["value"] == 9.0
    assert a.reasoning["demand_surge"]["baseline"] == 3.0
    assert a.reasoning["demand_surge"]["threshold"] == 6.0


def test_demand_surge_stays_quiet_when_the_nowcast_matches_its_climatology():
    a = forecast_signals(_forecast(), site_power_target_kw=700, now_hour=0)
    assert "demand_surge" not in a.signals


#: The shipped NYC-TLC hourly shape (priors_snapshot.json, profiles.nyc_tlc.
#: hourly_arrival_rate), normalized to mean 1.0. Hard-coded here rather than
#: imported: intent/ is kernel and must not reach into the intelligence service.
_TLC_SHAPE = {0: 0.7734, 1: 0.5013, 2: 0.3297, 3: 0.2111, 4: 0.1493, 5: 0.1505,
              6: 0.3198, 7: 0.6058, 8: 0.8701, 9: 0.9770, 10: 1.0681,
              11: 1.1766, 12: 1.2811, 13: 1.3458, 14: 1.4413, 15: 1.4666,
              16: 1.4836, 17: 1.6070, 18: 1.6962, 19: 1.4545, 20: 1.2887,
              21: 1.3761, 22: 1.3381, 23: 1.0884}
_TLC_MAX_DOW = 1.1980   # profiles.nyc_tlc.dow_demand_multiplier, day 5


def test_a_flat_daily_mean_baseline_cannot_reach_the_surge_threshold():
    """The arithmetic that made demand_surge structurally unreachable, pinned.

    The old baseline was `(mean_daily / 24) * window` — a FLAT hourly rate —
    while the forecast it consumes is strongly diurnal. The shape's own busiest
    3-hour run therefore bounds the achievable ratio, and that bound is below
    the 2.0 threshold: no site, no hour, no day of week could ever surge. The
    ratio is scale-invariant, so no fleet_size or turns_per_day setting saved
    it either.

    If someone reverts the baseline to the flat mean, this test says why it
    cannot work rather than leaving a dead regime in the pack.
    """
    W = int(SIGNAL_THRESHOLDS["surge_window_hours"].default)
    best = max(sum(_TLC_SHAPE[(start + i) % 24] for i in range(W))
               for start in range(24))
    ceiling = (best / W) * _TLC_MAX_DOW
    assert round(ceiling, 4) == 1.9115
    assert ceiling < SIGNAL_THRESHOLDS["surge_multiplier"].default, (
        f"the diurnal shape's own peak is {ceiling:.4f}x the flat daily mean, "
        f"below the {SIGNAL_THRESHOLDS['surge_multiplier'].default} threshold")


def test_the_diurnal_peak_is_not_a_surge_and_the_quiet_hours_can_still_be_one():
    """The signal now means DEVIATION, not TIME OF DAY.

    Rush hour matching its own climatology is not a surge — dispatch_rush is the
    regime for that. And 4am at three times its (tiny) expectation IS a surge,
    which the flat-mean version could never see because 4am is far below the
    daily average no matter what actually shows up.
    """
    mean_hourly = 5.0
    tlc = {h: mean_hourly * _TLC_SHAPE[h] for h in range(24)}

    # 18:00, the shape's peak, exactly as forecast -> not a surge
    at_peak = forecast_signals(
        _forecast(per_hour_arrivals=tlc, per_hour_baseline=tlc),
        site_power_target_kw=700, now_hour=18)
    assert "demand_surge" not in at_peak.signals

    # 04:00, the shape's trough, at 3x its expectation -> a surge
    hot_dawn = dict(tlc)
    for h in (4, 5, 6):
        hot_dawn[h] = tlc[h] * 3.0
    at_dawn = forecast_signals(
        _forecast(per_hour_arrivals=hot_dawn, per_hour_baseline=tlc),
        site_power_target_kw=700, now_hour=4)
    assert "demand_surge" in at_dawn.signals


def test_a_forecast_without_a_climatology_is_refused_not_guessed():
    """The bridge will not substitute a flat daily mean for the baseline — that
    substitution is the defect. Same posture as the missing-count refusal."""
    fc = _forecast()
    for h in fc["arrivals"]["hours"]:
        h.pop("baseline_arrivals")
    with pytest.raises(ForecastContractError, match="baseline_arrivals"):
        forecast_signals(fc, site_power_target_kw=700, now_hour=0)


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


def test_the_resolved_decision_is_identical_across_processes_and_hash_seeds():
    """The single-process determinism test cannot see the hazard it is named for.

    Two calls in ONE interpreter share a PYTHONHASHSEED, so frozenset and dict
    iteration order are already fixed; they share a warm import graph; and they
    run milliseconds apart, so an hour-boundary clock read cannot differ between
    them. It passes under exactly the conditions the doctrine warns about.

    What must be stable is the DECISION, not the internal ordering of a set: the
    active regime and the ordered objective list the optimizer acts on. Asserting
    on `sorted(signals)` would normalize away the very hash-order dependence
    worth catching, and asserting on the set's raw iteration order would fail
    spuriously, since that legitimately differs by seed. So this runs the whole
    path -- forecast -> signals -> resolve_intent -> ordered objectives -- in two
    subprocesses under two hash seeds and compares the bytes of the outcome.

    A regime resolver that iterated a frozenset instead of the artifact's
    declaration order would pass every other test in this file and fail here.
    """
    import json as _json
    import subprocess
    import sys as _sys
    import tempfile

    prog = (
        "import json,sys;"
        "sys.path.insert(0, %r);"
        "from intent.signals import forecast_signals;"
        "from intent.intent import load_intent, resolve_intent;"
        "fc=json.load(open(%r));"
        "a=forecast_signals(fc, site_power_target_kw=700, now_hour=7);"
        "act=resolve_intent(load_intent(), hour_of_day=7, signals=a.signals);"
        "print(json.dumps({'regime': act.regime_key,"
        " 'objectives': list(act.objectives)}, sort_keys=True))"
    )

    #: both a surge AND a grid peak, so more than one signal-gated regime
    #: matches and PRECEDENCE actually has to decide -- the case where an
    #: order-dependent resolver would diverge.
    fc = _forecast(per_hour_arrivals={7: 3.0, 8: 3.0, 9: 3.0},
                   load_p90={7: 700.0})
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        _json.dump(fc, fh)
        fixture = fh.name

    root = str(Path(__file__).resolve().parent.parent)
    outs = []
    for seed in ("0", "12345"):
        env = dict(os.environ, PYTHONHASHSEED=seed)
        r = subprocess.run([_sys.executable, "-c", prog % (root, fixture)],
                           capture_output=True, text=True, env=env, timeout=120)
        assert r.returncode == 0, (
            f"subprocess failed under PYTHONHASHSEED={seed}: {r.stderr[-500:]}")
        outs.append(r.stdout)

    assert outs[0] == outs[1], (
        f"the resolved decision differs by hash seed:\n  seed 0     {outs[0]!r}"
        f"\n  seed 12345 {outs[1]!r}\nsomething on the signal->regime path "
        f"depends on hash iteration order, so two machines can disagree about "
        f"which regime is active and in what order the optimizer sees its "
        f"objectives")

    #: byte-equality of nothing is not evidence: the fixture must actually have
    #: forced a contested resolution.
    decided = _json.loads(outs[0])
    assert decided["regime"], "no regime resolved; the fixture proves nothing"
    assert len(decided["objectives"]) > 1


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
