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

  * demand_surge        <- arrivals forecast. Expected (nowcast) arrivals over
                           the next window >= surge_multiplier x the SAME
                           window's climatological baseline. Comparing against
                           a flat daily mean instead made the signal
                           structurally unreachable; see the derivation at the
                           computation. (A "hot window" — throughput-first.)
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

import math
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
#:
#: `operator-override` is not a grounding, it is the ABSENCE of one, and it
#: exists because the reasoning dict used to publish an overridden number under
#: the HOUSE's evidence label and source (finding L-17). The whole stated point
#: of this module is that every raised signal walks to its number and that
#: number walks to its grounding; after an override the walk landed on the
#: wrong grounding, stamping an operator's arbitrary coefficient
#: "must-measure-on-twin: no published AV-depot surge threshold" as though the
#: house had inferred it. A caller's number is now labelled as a caller's.
EVIDENCE_LABELS = ("primary", "review", "standards", "trade-press", "inference",
                   "operator-override")

OVERRIDE_LABEL = "operator-override"

#: Threshold kinds, which are DOMAINS and not decoration (finding L-16). The
#: override path checked the threshold NAME and then applied float(v) with no
#: range check at all, so a caller could hand it numbers that make a signal
#: fire unconditionally: surge_window_hours=0 makes the window empty, so
#: expected=0.0 and baseline=0.0 and "0.0 >= 2.0*0.0" reports a demand surge;
#: a negative window behaves identically (range(-2) is empty); a multiplier or
#: fraction of 0 puts the threshold at or below zero, which any load clears.
#: A float window like 3.9 was silently truncated by int().
WINDOW_KIND = "window"      # integral hours, 1..24
RATIO_KIND = "ratio"        # finite and strictly positive

MAX_WINDOW_HOURS = 24


@dataclass(frozen=True)
class Threshold:
    default: float
    units: str
    evidence_label: str      # one of EVIDENCE_LABELS
    source: str              # citation, or the honest "must-measure-on-twin"
    rationale: str
    kind: str = RATIO_KIND   # WINDOW_KIND or RATIO_KIND -- the override domain


#: The signal thresholds. Every numeric default is an inference that must be
#: measured on the twin before it is quoted as a product number — none is a
#: published AV-depot value, and none pretends to be.
SIGNAL_THRESHOLDS: dict[str, Threshold] = {
    "surge_multiplier": Threshold(
        2.0, "ratio", "inference",
        "must-measure-on-twin: no published AV-depot surge threshold",
        "a demand surge is expected arrivals >= 2x the SAME window's "
        "climatological baseline — a defensible 'hot window' default. Against "
        "a flat daily mean this threshold is unreachable: the diurnal shape's "
        "own busiest window is 1.91x that mean"),
    "surge_window_hours": Threshold(
        3, "hours", "inference",
        "must-measure-on-twin: look-ahead is an operating choice",
        "a surge is actionable within ~3 hours (time to reposition and prepare)",
        kind=WINDOW_KIND),
    "peak_fraction": Threshold(
        0.9, "ratio", "inference",
        "must-measure-on-twin: the soft target is sourced (tariff); the 0.9 "
        "approach fraction is not",
        "grid peak imminent when the p90 load reaches 90% of the site's soft "
        "power target — the demand-charge-relevant ceiling"),
    "peak_window_hours": Threshold(
        6, "hours", "inference",
        "must-measure-on-twin: look-ahead is an operating choice",
        "look-ahead for demand-charge risk",
        kind=WINDOW_KIND),
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


#: THE VALUE DOMAIN OF THE TOTAL SEAM (findings L-14 and L-46).
#:
#: The seam validated the PRESENCE of every field it consumes and never their
#: VALUE, and `float(x)` is a wide gate. NaN passed, and every downstream
#: comparison with NaN is False, so a NaN forecast SILENTLY SUPPRESSED the
#: signal -- the exact failure two comments in this module claim to prevent
#: ("refuses to treat a missing count as zero (that would hide a surge)"). NaN
#: hides it just as completely and without an exception. A negative count
#: passed and was summed as arrivals. A string that parses ('900') was coerced
#: without complaint, so a JSON contract drift from number to string was
#: invisible; a string that does not parse escaped as a bare ValueError and
#: None as a bare TypeError, both past the documented "a malformed forecast
#: raises ForecastContractError" that callers catch on.
def _number(field_name: str, value, *, section: str) -> float:
    """A forecast quantity, or ForecastContractError naming what was wrong."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ForecastContractError(
            f"forecast[{section!r}].{field_name} is {value!r} ({type(value).__name__}), "
            f"not a number — the bridge refuses to coerce it; a contract that "
            f"drifted from number to string must be visible, not absorbed")
    v = float(value)
    if not math.isfinite(v):
        raise ForecastContractError(
            f"forecast[{section!r}].{field_name} is not finite ({value!r}) — every "
            f"comparison against NaN is False, so accepting it would silently "
            f"SUPPRESS the signal rather than raise it")
    if v < 0:
        raise ForecastContractError(
            f"forecast[{section!r}].{field_name} is negative ({value!r}) — arrivals "
            f"and kW are non-negative quantities")
    return v


def _hour_map(section: dict, key: str) -> dict[int, dict]:
    """hour_of_day -> first forecast hour entry. First-occurrence wins for a
    horizon longer than 24h; a 24h cycle is the expected shape.

    Errors name `key`, the section the CALLER asked for, and not
    `section['kind']` (finding L-48): the argument was passed by both call
    sites and then discarded, so a section malformed in the way that drops its
    own 'kind' produced an error naming no section at all. A malformed input
    does not get to identify itself.
    """
    hours = section.get("hours")
    if not isinstance(hours, list) or not hours:
        raise ForecastContractError(
            f"forecast[{key!r}] has no 'hours' list — "
            "nothing to derive a signal from")
    out: dict[int, dict] = {}
    for h in hours:
        if not isinstance(h, dict) or "hour_of_day" not in h:
            raise ForecastContractError(
                f"a forecast[{key!r}] hour entry is malformed (missing hour_of_day)")
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


def _validated_override(name: str, value, spec: "Threshold") -> float:
    """A caller's threshold, inside the domain the threshold's kind declares.

    Windows are HOURS and must be integral: `int(3.9)` is 3, and a lookahead
    silently shortened by a tenth of an hour is the kind of drift that shows up
    later as an unexplained signal. Ratios must be finite and strictly
    positive, because a threshold at or below zero is cleared by every value.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"threshold {name!r} must be a number, got {value!r}")
    v = float(value)
    if not math.isfinite(v):
        raise ValueError(f"threshold {name!r} must be finite, got {value!r}")
    if spec.kind == WINDOW_KIND:
        if not v.is_integer():
            raise ValueError(
                f"threshold {name!r} is a window in whole hours; {value!r} "
                f"would be truncated to {int(v)} rather than honoured")
        if not (1 <= v <= MAX_WINDOW_HOURS):
            raise ValueError(
                f"threshold {name!r} must be 1..{MAX_WINDOW_HOURS} hours, got "
                f"{value!r} — an empty or negative window makes its signal "
                f"compare zero against zero and fire unconditionally")
        return v
    if v <= 0:
        raise ValueError(
            f"threshold {name!r} must be > 0, got {value!r} — a threshold at "
            f"or below zero is cleared by every value")
    return v


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
    #: bool is an int in Python, so the module's strictest guard read
    #: now_hour=True as hour 1 and now_hour=False as hour 0 (finding L-47).
    if isinstance(now_hour, bool) or not isinstance(now_hour, int) \
            or not (0 <= now_hour <= 23):
        raise ValueError(f"now_hour must be 0-23, got {now_hour!r}")

    #: THE ONE CALLER-SUPPLIED PHYSICAL QUANTITY, and it had no validation at
    #: all (finding L-15) while now_hour and the threshold names both did.
    #: `peak >= peak_fraction * 0` is `peak >= 0.0`, true for any load, so a
    #: target of 0 latched grid_peak_imminent on permanently -- and the
    #: reasoning dict then reported "threshold": 0.0 to the operator as if that
    #: were a real demand-charge ceiling. A negative target is worse; NaN gives
    #: permanent silence.
    if isinstance(site_power_target_kw, bool) \
            or not isinstance(site_power_target_kw, (int, float)) \
            or not math.isfinite(site_power_target_kw) \
            or site_power_target_kw <= 0:
        raise ValueError(
            f"site_power_target_kw must be a finite positive number, got "
            f"{site_power_target_kw!r} — it is the demand-charge ceiling every "
            f"grid-peak comparison is measured against, and a non-positive one "
            f"makes the signal fire unconditionally")

    eff = {k: v.default for k, v in SIGNAL_THRESHOLDS.items()}
    #: name -> (evidence_label, source) ACTUALLY IN FORCE, which is the house's
    #: provenance until a caller overrides the number (finding L-17).
    prov = {k: (v.evidence_label, v.source) for k, v in SIGNAL_THRESHOLDS.items()}
    if thresholds:
        for k, v in thresholds.items():
            spec = SIGNAL_THRESHOLDS.get(k)
            if spec is None:
                raise ValueError(f"unknown threshold {k!r} — valid: "
                                 f"{sorted(SIGNAL_THRESHOLDS)}")
            eff[k] = _validated_override(k, v, spec)
            prov[k] = (OVERRIDE_LABEL,
                       f"caller-supplied; not the SIGNAL_THRESHOLDS default "
                       f"(was {spec.default})")

    arrivals = _require(forecast, "arrivals")
    load = _require(forecast, "load")

    amap = _hour_map(arrivals, "arrivals")
    lmap = _hour_map(load, "load")

    # ---- demand_surge ------------------------------------------------------
    #: THE BASELINE IS THE WINDOW'S OWN CLIMATOLOGY, NOT A FLAT DAILY MEAN.
    #:
    #: The first version compared the window against `(mean_daily / 24) * W` — a
    #: FLAT hourly rate — while the arrivals forecast it consumes is strongly
    #: diurnal (`mean_hourly * hourly_shape[hod] * dow_mult`, a real NYC-TLC
    #: shape normalized to mean 1.0). That asks "is this window above the daily
    #: flat average?", a question the shape already answers for every hour, and
    #: it is bounded by the shape itself: the busiest 3-hour run in the shipped
    #: prior (hours 16,17,18) sums to 4.7868 against a flat 3.0, a ratio of
    #: 1.5956, and the largest day-of-week multiplier is 1.1980. The product is
    #: 1.9115 — below the 2.0 default. `demand_surge` could therefore NEVER
    #: fire, at any site, any hour, any day of week. The ratio is scale-
    #: invariant, so no fleet size or turns-per-day setting rescued it.
    #:
    #: A surge is arrivals ABOVE WHAT WAS EXPECTED FOR THIS WINDOW, which needs
    #: two numbers: the nowcast (`expected_arrivals`) and the climatological
    #: expectation (`baseline_arrivals`). The bridge requires both rather than
    #: reconstructing the second from a daily mean, exactly as it refuses a
    #: missing count instead of reading it as zero. A pure-climatology
    #: forecaster sets them equal and correctly never surges; a forecast that
    #: carries live observation or a perturbation raises one above the other,
    #: and that is the signal.
    surge_w = int(eff["surge_window_hours"])
    surge_m = float(eff["surge_multiplier"])
    _vals, _base = [], []
    for h in _window(amap, now_hour, surge_w):
        if "expected_arrivals" not in h:
            raise ForecastContractError(
                "an arrivals hour is missing expected_arrivals — the bridge "
                "refuses to treat a missing count as zero (that would hide a "
                "surge)")
        if "baseline_arrivals" not in h:
            raise ForecastContractError(
                "an arrivals hour is missing baseline_arrivals — a surge is a "
                "deviation from what this hour was expected to bring, and the "
                "bridge refuses to substitute a flat daily mean for the "
                "climatology (doing so made demand_surge unreachable: the "
                "diurnal shape's own peak is only 1.91x the flat mean, under "
                "the 2.0 threshold)")
        _vals.append(_number("expected_arrivals", h["expected_arrivals"],
                             section="arrivals"))
        _base.append(_number("baseline_arrivals", h["baseline_arrivals"],
                             section="arrivals"))
    expected = sum(_vals)
    baseline = sum(_base)
    if baseline <= 0:
        raise ForecastContractError("arrivals baseline over the window is "
                                    "non-positive — no climatology to compare a "
                                    "surge against")
    #: bool(_vals) and baseline > 0 are BELT AND BRACES over the window-domain
    #: check above: an empty window would compare 0.0 >= 2.0*0.0 and report a
    #: surge, and the `if _p90 else 0.0` guard on the peak side shows the
    #: asymmetry was unintended rather than a convention (finding L-16).
    surge_hit = bool(_vals) and baseline > 0 and expected >= surge_m * baseline
    reasoning = {
        "demand_surge": {
            "triggered": surge_hit,
            "metric": "expected_arrivals vs baseline_arrivals over window",
            "value": round(expected, 3),
            "baseline": round(baseline, 3),
            "threshold": round(surge_m * baseline, 3),
            "units": "vehicles",
            "window_hours": surge_w,
            "evidence_label": prov["surge_multiplier"][0],
            "source": prov["surge_multiplier"][1],
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
        _p90.append(_number("total_kw_p90", h["total_kw_p90"], section="load"))
    peak = max(_p90) if _p90 else 0.0
    peak_hit = bool(_p90) and peak >= peak_f * site_power_target_kw
    reasoning["grid_peak_imminent"] = {
        "triggered": peak_hit,
        "metric": "max p90 site load over window",
        "value": round(peak, 2),
        "threshold": round(peak_f * site_power_target_kw, 2),
        "units": "kW",
        "window_hours": peak_w,
        "site_power_target_kw": site_power_target_kw,
        "evidence_label": prov["peak_fraction"][0],
        "source": prov["peak_fraction"][1],
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
