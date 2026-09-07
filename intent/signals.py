"""The signal bridge — turn the demand-side forecast into regime signals.

The forecast (ottoq-intelligence, FR-2) predicts the demand-side world: when
vehicles return and how much load they pull. The intent's regimes respond to
qualitative events — demand_surge, grid_peak_imminent, weather_hold — that the
resolver turns into a pass order. This module is the seam between the two: it
reads a forecast's QUANTITATIVE output and raises the QUALITATIVE signals.

DOCTRINE (why this lives here and not in the forecast repo):

  * The forecast must stay a pure demand-side predictor, ignorant of OTTO-Q
    operating doctrine. "A surge is 2x the fleet's mean return rate" is doctrine,
    not world physics, so it belongs with the intent, not with the forecast.
  * The forecast output is DECLARED DATA — an argument, never read from a file or
    database (the same separation discipline as the decision frame). This module
    validates the contract and refuses to guess around a malformed forecast.

THE THREE SIGNALS, and what derives each:

  * demand_surge        <- arrivals forecast. Expected arrivals over the next
                           window >= surge_multiplier x the fleet's mean hourly
                           return rate. (A "hot window" — throughput-first.)
  * grid_peak_imminent  <- load forecast + the site's soft power target. The
                           p90 load (conservative tail) over the next window
                           reaching peak_fraction of the soft target means the
                           demand charge is at risk. (Flatten the bill.)
  * weather_hold        <- NOT derivable from the statistical forecast (it has
                           no live-weather event model). Passed through from an
                           external input; the bridge never invents it.

HONESTY ABOUT THRESHOLDS (the founder's rule: no invented numbers):

  The MECHANISM of each signal is grounded — the soft power target is the
  demand-charge-relevant ceiling (sourced tariff, R-5/R-6), and the arrival
  baseline is the fleet's declared scale. The exact NUMERIC thresholds
  (surge_multiplier, peak_fraction, window lengths) have NO published value for
  an AV depot, so every one carries evidence_label="inference" and
  source="must-measure-on-twin" — a defensible engineering default, flagged for
  calibration, never dressed up as a sourced coefficient.

NOT YET WIRED, stated so it is not hidden: the soc_return forecast's
fleet_energy_need_kwh ("how tight is tonight") is not consumed by any signal
yet. It is the natural future input to a demand_surge or a grid_peak refinement,
but no signal is defined against it today, and inventing one would be guessing.
"""

from __future__ import annotations

from dataclasses import dataclass, field


class ForecastContractError(ValueError):
    """The forecast did not carry a field the bridge requires — named, never
    absorbed (the AGENTS.md total-function rule: a seam must not silently
    default around a missing input)."""


# ---------------------------------------------------------------------------
# Threshold provenance — every number names its grounding or its absence
# ---------------------------------------------------------------------------

#: The house evidence labels, so a reviewer sees the same vocabulary here as in
#: the intent artifact and the research dossiers.
EVIDENCE_LABELS = ("primary", "review", "standards", "trade-press", "inference")


@dataclass(frozen=True)
class Threshold:
    default: float
    units: str
    evidence_label: str      # one of EVIDENCE_LABELS
    source: str              # citation, or the honest "must-measure-on-twin"
    rationale: str


#: The signal thresholds. Every numeric default is an inference that must be
#: measured on the twin before it is quoted as a product number — none is a
#: published AV-depot value, and none pretends to be.
SIGNAL_THRESHOLDS: dict[str, Threshold] = {
    "surge_multiplier": Threshold(
        2.0, "ratio", "inference",
        "must-measure-on-twin: no published AV-depot surge threshold",
        "a demand surge is expected arrivals >= 2x the fleet's mean hourly "
        "return rate — a defensible 'hot window' default"),
    "surge_window_hours": Threshold(
        3, "hours", "inference",
        "must-measure-on-twin: look-ahead is an operating choice",
        "a surge is actionable within ~3 hours (time to reposition and prepare)"),
    "peak_fraction": Threshold(
        0.9, "ratio", "inference",
        "must-measure-on-twin: the soft target is sourced (tariff); the 0.9 "
        "approach fraction is not",
        "grid peak imminent when the p90 load reaches 90% of the site's soft "
        "power target — the demand-charge-relevant ceiling"),
    "peak_window_hours": Threshold(
        6, "hours", "inference",
        "must-measure-on-twin: look-ahead is an operating choice",
        "look-ahead for demand-charge risk"),
}


@dataclass(frozen=True)
class SignalAssessment:
    signals: frozenset[str]
    reasoning: dict = field(default_factory=dict)
    thresholds: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "signals": sorted(self.signals),
            "reasoning": self.reasoning,
            "thresholds": self.thresholds,
        }


# ---------------------------------------------------------------------------
# Forecast contract validation (TOTAL seam)
# ---------------------------------------------------------------------------

def _require(forecast: dict, key: str) -> dict:
    if not isinstance(forecast, dict) or key not in forecast:
        raise ForecastContractError(
            f"forecast is missing required key {key!r} — the bridge refuses to "
            "guess around a malformed forecast")
    val = forecast[key]
    if not isinstance(val, dict):
        raise ForecastContractError(f"forecast[{key!r}] is not an object")
    return val


def _hour_map(section: dict, key: str) -> dict[int, dict]:
    """hour_of_day -> first forecast hour entry. First-occurrence wins for a
    horizon longer than 24h; a 24h cycle is the expected shape."""
    hours = section.get("hours")
    if not isinstance(hours, list) or not hours:
        raise ForecastContractError(
            f"forecast[{section.get('kind', '?')!r}] has no 'hours' list — "
            "nothing to derive a signal from")
    out: dict[int, dict] = {}
    for h in hours:
        if not isinstance(h, dict) or "hour_of_day" not in h:
            raise ForecastContractError("a forecast hour entry is malformed "
                                        "(missing hour_of_day)")
        out.setdefault(int(h["hour_of_day"]), h)
    return out


def _window(hour_map: dict[int, dict], now_hour: int, window: int
            ) -> list[dict]:
    """The `window` forecast hours starting at now_hour, wrapping midnight."""
    out = []
    for i in range(window):
        hod = (now_hour + i) % 24
        if hod not in hour_map:
            raise ForecastContractError(
                f"forecast does not cover hour_of_day {hod} — it must cover "
                f"now_hour {now_hour} through the next {window} hours")
        out.append(hour_map[hod])
    return out


# ---------------------------------------------------------------------------
# The bridge
# ---------------------------------------------------------------------------

def forecast_signals(forecast: dict, *, site_power_target_kw: float,
                     now_hour: int, weather_hold: bool = False,
                     thresholds: dict | None = None) -> SignalAssessment:
    """Forecast -> regime signals. Pure, deterministic, contract-validating.

    `forecast` is the /forecast output dict (arrivals + load sections, each with
    an `hours` list). `site_power_target_kw` is the site's declared soft power
    target (the demand-charge-relevant ceiling). `now_hour` is the current hour
    of day (0-23). `weather_hold` is an EXTERNAL input — the bridge never
    derives it from the statistical forecast.

    `thresholds` optionally overrides the default SIGNAL_THRESHOLDS by name
    (e.g. {"surge_multiplier": 1.5}); unknown names are rejected, not ignored.

    Returns a SignalAssessment whose `.signals` frozenset feeds resolve_intent,
    and whose `.reasoning` carries, per derived signal, the measured value, the
    threshold it was compared against, and the threshold's provenance — so an
    auditor can walk every raised signal to its number and that number to its
    grounding.
    """
    if not isinstance(now_hour, int) or not (0 <= now_hour <= 23):
        raise ValueError(f"now_hour must be 0-23, got {now_hour!r}")
    eff = {k: v.default for k, v in SIGNAL_THRESHOLDS.items()}
    if thresholds:
        for k, v in thresholds.items():
            if k not in SIGNAL_THRESHOLDS:
                raise ValueError(f"unknown threshold {k!r} — valid: "
                                 f"{sorted(SIGNAL_THRESHOLDS)}")
            eff[k] = float(v)

    arrivals = _require(forecast, "arrivals")
    load = _require(forecast, "load")

    amap = _hour_map(arrivals, "arrivals")
    lmap = _hour_map(load, "load")

    # ---- demand_surge ------------------------------------------------------
    mean_daily = float(arrivals.get("mean_daily_arrivals") or 0.0)
    if mean_daily <= 0:
        raise ForecastContractError("arrivals.mean_daily_arrivals is missing "
                                    "or non-positive — no baseline to compare a "
                                    "surge against")
    surge_w = int(eff["surge_window_hours"])
    surge_m = float(eff["surge_multiplier"])
    _vals = []
    for h in _window(amap, now_hour, surge_w):
        if "expected_arrivals" not in h:
            raise ForecastContractError(
                "an arrivals hour is missing expected_arrivals — the bridge "
                "refuses to treat a missing count as zero (that would hide a "
                "surge)")
        _vals.append(float(h["expected_arrivals"]))
    expected = sum(_vals)
    baseline = (mean_daily / 24.0) * surge_w
    surge_hit = expected >= surge_m * baseline
    reasoning = {
        "demand_surge": {
            "triggered": surge_hit,
            "metric": "expected_arrivals over window",
            "value": round(expected, 3),
            "threshold": round(surge_m * baseline, 3),
            "units": "vehicles",
            "window_hours": surge_w,
            "evidence_label": SIGNAL_THRESHOLDS["surge_multiplier"].evidence_label,
            "source": SIGNAL_THRESHOLDS["surge_multiplier"].source,
        },
    }

    # ---- grid_peak_imminent ------------------------------------------------
    peak_w = int(eff["peak_window_hours"])
    peak_f = float(eff["peak_fraction"])
    _p90 = []
    for h in _window(lmap, now_hour, peak_w):
        if "total_kw_p90" not in h:
            raise ForecastContractError(
                "a load hour is missing total_kw_p90 — the bridge refuses to "
                "treat a missing load as zero (that would hide a peak)")
        _p90.append(float(h["total_kw_p90"]))
    peak = max(_p90) if _p90 else 0.0
    peak_hit = peak >= peak_f * site_power_target_kw
    reasoning["grid_peak_imminent"] = {
        "triggered": peak_hit,
        "metric": "max p90 site load over window",
        "value": round(peak, 2),
        "threshold": round(peak_f * site_power_target_kw, 2),
        "units": "kW",
        "window_hours": peak_w,
        "site_power_target_kw": site_power_target_kw,
        "evidence_label": SIGNAL_THRESHOLDS["peak_fraction"].evidence_label,
        "source": SIGNAL_THRESHOLDS["peak_fraction"].source,
    }

    # ---- weather_hold (external passthrough) --------------------------------
    reasoning["weather_hold"] = {
        "triggered": bool(weather_hold),
        "metric": "external weather feed",
        "note": "not derivable from the statistical forecast; passed through "
                "from an external input",
    }

    signals = frozenset(
        sig for sig, r in reasoning.items() if r["triggered"])
    return SignalAssessment(
        signals=signals, reasoning=reasoning,
        thresholds={k: round(v, 3) for k, v in eff.items()},
    )
