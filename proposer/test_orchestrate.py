"""Tests for the deterministic conductor — forecast → signals → intent → propose.

Run:  python3 -m pytest proposer/test_orchestrate.py -q

This is the END-TO-END proof of the magenta layer in a single call: a forecast
dict in, advisory proposals out, with the regime chosen by the forecast and the
whole audit trail attached (signal reasoning → regime → pass order → optima).

The forecast and frame are synthetic but in the exact production contract shape
(the /forecast output dict, and the twin's decision-frame shape read from a live
snapshot). The conductor is tested against those shapes without reading
production data — the same separation discipline as the other proposer tests.
"""

import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "policies"))
sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))

import pytest  # noqa: E402

from orchestrate import OrchestrateError, orchestrate  # noqa: E402
from intent.signals import ForecastContractError       # noqa: E402

#: Every orchestrate() call names the run it belongs to (L-44): no number ships
#: without a run ID, and the conductor is the only place that knows the caller's.
RUN_ID = "test-run-0001"

SITE = {"power_cap_kw_hard": 600, "power_soft_target_kw": 450,
        "dcfc_cooldown_min": 18, "move_duration_min": 4, "path_capacity": 2,
        "cold_start_below_c": 5, "cold_start_penalty_min": 12,
        "onpeak_window_min": [240, 420]}

CLASSES = {
    "waymo": {"battery_kwh": 90, "max_charge_kw": 100,
              "charge_kinds": ["dcfc", "l2"],
              "energy_curve": [{"above_soc_pct": 0, "accept_frac": 1.0},
                               {"above_soc_pct": 70, "accept_frac": 0.6}]},
    "zoox": {"battery_kwh": 110, "max_charge_kw": 150,
             "charge_kinds": ["dcfc"]},
}


def _forecast(mean_daily_arrivals=24.0, per_hour_arrivals=None, load_p90=None,
              per_hour_baseline=None):
    """A synthetic 24h forecast in the /forecast contract shape (flat 1.0/hr
    arrivals, flat 100 kW p90 load — both below any trigger).

    `expected_arrivals` is the nowcast and `baseline_arrivals` the
    climatological expectation for that hour; they default to the same flat
    rate, which is what a pure-climatology forecaster emits. A surge is the
    nowcast standing above the baseline, so a test that wants one raises only
    `per_hour_arrivals`."""
    per_hour_arrivals = per_hour_arrivals or {}
    per_hour_baseline = per_hour_baseline or {}
    load_p90 = load_p90 or {}
    hours_arr, hours_load = [], []
    for hod in range(24):
        arr = per_hour_arrivals.get(hod, 1.0)
        base = per_hour_baseline.get(hod, 1.0)
        kw = load_p90.get(hod, 100.0)
        hours_arr.append({"hour_index": hod, "hour_of_day": hod,
                          "expected_arrivals": arr,
                          "baseline_arrivals": base, "p10": 0, "p50": int(arr),
                          "p90": int(arr) + 1})
        hours_load.append({"hour_index": hod, "hour_of_day": hod,
                           "base_kw": 50.0, "ev_kw_expected": 50.0,
                           "total_kw_p50": kw, "total_kw_p10": kw * 0.5,
                           "total_kw_p90": kw})
    return {
        "arrivals": {"kind": "arrivals", "horizon_hours": 24, "start_hour": 0,
                     "dow": 0, "mean_daily_arrivals": mean_daily_arrivals,
                     "hours": hours_arr, "provenance": {}},
        "load": {"kind": "load", "horizon_hours": 24, "start_hour": 0, "dow": 0,
                 "base_load_kw": 50.0, "ev_daily_sessions": 24.0,
                 "hours": hours_load, "provenance": {}},
    }


def _vehicle(vid, platform="waymo", soc=30):
    #: vehicle_class_code mirrors platform so the CLASSES table below stays
    #: readable; the bridge joins on whichever field `class_key` names (L-41).
    return {"id": vid, "soc": soc, "platform": platform,
            "vehicle_class_code": platform,
            "state": "arrived_at_gate", "target_soc": 90, "inlet_type": "CCS1",
            "inlet_max_kw": 100.0}


def _stall(sid, kind="dcfc", kw=150):
    #: THE PRODUCTION STALL SHAPE, connector fields included. This fixture used
    #: to omit connector_type and supported_inlet_types entirely -- fields
    #: ottoq_build_decision_frame emits and every real stall carries -- so it
    #: could not exercise the inlet rule the bridge now enforces (L-42). Every
    #: charging stall at the flagship depot is connector_type 'Multi' with
    #: supported {CCS1, NACS}; that is what is reproduced here.
    return {"id": sid, "type": kind, "status": "available",
            "connector_max_kw": kw, "connector_type": "Multi",
            "supported_inlet_types": ["CCS1", "NACS"]}


def _frame():
    return {"vehicles": [_vehicle("v-1", soc=25), _vehicle("v-2", soc=40),
                         _vehicle("v-3", soc=30)],
            "stalls": [_stall("s-1"), _stall("s-2"), _stall("s-3", kind="l2", kw=11)],
            "sessions": [], "energy": {}, "bess": []}


# ---- the loop closes: forecast -> regime -> plan -> proposals -------------------

def test_flat_forecast_at_rush_hour_resolves_to_dispatch_rush():
    r = orchestrate(_forecast(), _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=7)
    assert r["solver"]["regime"] == "dispatch_rush"
    assert r["signals"]["signals"] == []        # nothing fired
    assert r["planned"] == 3 and r["abstained"] == 0


def test_arrival_surge_at_rush_hour_resolves_to_demand_surge():
    fc = _forecast(mean_daily_arrivals=24.0,
                   per_hour_arrivals={7: 3.0, 8: 3.0, 9: 3.0})
    r = orchestrate(fc, _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=7)
    assert r["signals"]["signals"] == ["demand_surge"]
    assert r["solver"]["regime"] == "demand_surge"
    assert r["solver"]["pass_modes"] == ["min_tardy", "min_flow"]
    # the audit trail names the number that triggered it
    reason = r["signals"]["reasoning"]["demand_surge"]
    assert reason["triggered"] is True and reason["value"] == 9.0


def test_load_peak_at_rush_hour_resolves_to_grid_peak():
    fc = _forecast(load_p90={7: 450.0, 8: 450.0})   # at the soft target (450)
    r = orchestrate(fc, _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=7)
    assert r["signals"]["signals"] == ["grid_peak_imminent"]
    assert r["solver"]["regime"] == "grid_peak"
    assert r["solver"]["pass_modes"] == ["min_tardy", "min_peak"]


def test_flat_forecast_at_overnight_hour_resolves_to_overnight():
    r = orchestrate(_forecast(), _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=22)
    assert r["solver"]["regime"] == "overnight"


def test_weather_hold_passes_through_to_the_weather_regime():
    r = orchestrate(_forecast(), _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=7,
                    weather_hold=True)
    assert r["signals"]["signals"] == ["weather_hold"]
    assert r["solver"]["regime"] == "weather_event"


def test_every_proposal_is_advisory_and_valid():
    r = orchestrate(_forecast(), _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=7)
    for row in r["proposals"]:
        assert row["source"] == "forward_lex"
        assert row["proposal"]["verb"] == "assign_stall"
        assert "abstain" in row["proposal"]
        assert "dispatch" not in row["proposal"]   # advisory, never a command
        if not row["proposal"]["abstain"]:
            assert {"stall_id", "stall_type", "vehicle_id",
                    "requested_kw"} <= set(row["proposal"])


# ---- determinism and the audit trail -------------------------------------------

def test_conductor_is_deterministic():
    fc = _forecast(mean_daily_arrivals=24.0,
                   per_hour_arrivals={7: 3.0, 8: 3.0, 9: 3.0})
    a = orchestrate(fc, _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=7)
    b = orchestrate(fc, _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=7)
    assert a["proposals"] == b["proposals"]
    assert a["signals"] == b["signals"]
    assert a["solver"]["passes"] == b["solver"]["passes"]


def test_audit_trail_carries_threshold_provenance():
    fc = _forecast(load_p90={7: 450.0})
    r = orchestrate(fc, _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=7)
    reason = r["signals"]["reasoning"]["grid_peak_imminent"]
    assert reason["source"] == ("must-measure-on-twin: the soft target is "
                                "sourced (tariff); the 0.9 approach fraction "
                                "is not")
    assert reason["evidence_label"] == "inference"
    assert r["signals"]["thresholds"]["peak_fraction"] == 0.9


# ---- the TOTAL seam -------------------------------------------------------------

def test_a_missing_soft_target_is_refused_not_guessed():
    site = dict(SITE)
    del site["power_soft_target_kw"]
    try:
        orchestrate(_forecast(), _frame(), CLASSES, site=site, run_id=RUN_ID, now_hour=7)
        raise AssertionError("missing soft target did not raise")
    except OrchestrateError as e:
        assert "power_soft_target_kw" in str(e)


def test_a_malformed_forecast_raises():
    fc = _forecast()
    del fc["arrivals"]
    try:
        orchestrate(fc, _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=7)
        raise AssertionError("malformed forecast did not raise")
    except ForecastContractError:
        pass


def test_a_bad_now_hour_is_refused():
    try:
        orchestrate(_forecast(), _frame(), CLASSES, site=SITE, run_id=RUN_ID, now_hour=24)
        raise AssertionError("bad now_hour did not raise")
    except OrchestrateError:
        pass


if __name__ == "__main__":
    for fn in [v for k, v in sorted(globals().items()) if k.startswith("test_")]:
        fn()
        print(f"{fn.__name__} PASS")
    print("ALL CONDUCTOR TESTS PASS")


# ---------------------------------------------------------------------------
# L-43 / L-44: the audit trail reaches the forecast at one end and the plan's
# reproducibility identity at the other.
# ---------------------------------------------------------------------------

def _identified_forecast(**kw):
    fc = _forecast(**kw)
    #: what /forecast actually emits alongside the numbers
    fc["forecast_generated_at"] = "2026-09-08T12:00:00Z"
    fc["priors_fingerprint"] = "abc123def456"
    return fc


def test_the_trail_names_which_forecast_produced_the_number():
    r = orchestrate(_identified_forecast(), _frame(), CLASSES, site=SITE,
                    run_id="run-42", now_hour=7)
    p = r["provenance"]
    assert p["run_id"] == "run-42"
    assert p["forecast_generated_at"] == "2026-09-08T12:00:00Z"
    assert p["priors_fingerprint"] == "abc123def456"


def test_the_trail_names_which_doctrine_ordered_the_passes():
    import regime as regime_mod
    r = orchestrate(_identified_forecast(), _frame(), CLASSES, site=SITE,
                    run_id="run-42", now_hour=7)
    p = r["provenance"]
    assert p["intent_fingerprint"] == regime_mod.INTENT.fingerprint
    assert p["intent_version"] == regime_mod.INTENT.version
    assert p["regime"] == r["solver"]["regime"] == "dispatch_rush"


def test_an_unidentifiable_forecast_records_the_gap_rather_than_hiding_it():
    r = orchestrate(_forecast(), _frame(), CLASSES, site=SITE,
                    run_id="run-42", now_hour=7)
    p = r["provenance"]
    assert "forecast_generated_at" in p and p["forecast_generated_at"] is None
    assert "priors_fingerprint" in p and p["priors_fingerprint"] is None


@pytest.mark.parametrize("bad", ["", "   ", None, 7])
def test_a_run_without_an_id_is_refused(bad):
    with pytest.raises(OrchestrateError, match="run_id"):
        orchestrate(_forecast(), _frame(), CLASSES, site=SITE,
                    run_id=bad, now_hour=7)


def test_the_solver_record_carries_what_reproducing_the_plan_requires():
    """model.py records ortools_version because the schedule moves with it.

    Measured across 9.11 and 9.15 in that module's own comment: identical
    objective values, four different committed plans. A fire record without the
    version cannot reproduce the plan it describes.
    """
    import ortools
    for regime in (True, False):
        s = orchestrate(_identified_forecast(), _frame(), CLASSES, site=SITE,
                        run_id="run-42", now_hour=7, regime=regime)["solver"]
        assert s["ortools_version"] == ortools.__version__
        assert s["det_budget_s"] is not None
        assert "wall_limit_s" in s


# ---------------------------------------------------------------------------
# L-57: the expensive path is opt-in at the conductor too.
# ---------------------------------------------------------------------------

def test_the_cheap_path_can_be_asked_for_and_still_names_the_regime():
    r = orchestrate(_identified_forecast(), _frame(), CLASSES, site=SITE,
                    run_id="run-42", now_hour=7, regime=False)
    assert r["regime_path"] is False
    #: the doctrine's choice is still recorded -- resolving it is pure and free
    assert r["provenance"]["regime"] == "dispatch_rush"
    #: ...but the three-pass chain did NOT run: this is the two-pass contract
    assert "pass_modes" not in r["solver"]
    assert r["solver"]["pass1_status"] and r["solver"]["pass2_status"]


def test_the_expensive_path_is_still_the_default():
    r = orchestrate(_identified_forecast(), _frame(), CLASSES, site=SITE,
                    run_id="run-42", now_hour=7)
    assert r["regime_path"] is True
    assert r["solver"]["pass_modes"] == ["min_tardy", "min_flow", "min_peak"]


@pytest.mark.parametrize("key", ["hour_of_day", "signals"])
def test_a_kwarg_the_conductor_binds_is_named_not_a_bare_typeerror(key):
    """The two propose() arguments the conductor binds and does not accept.

    `site` is not among them: it IS an orchestrate() parameter, so passing it
    twice is a TypeError on the call itself, which no guard here can intercept.
    """
    with pytest.raises(OrchestrateError, match=key):
        orchestrate(_forecast(), _frame(), CLASSES, site=SITE,
                    run_id="run-42", now_hour=7, **{key: 1})
