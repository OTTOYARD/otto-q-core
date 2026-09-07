"""The deterministic conductor — forecast → signals → intent → propose.

FR-4 in ottoq-intelligence/README.md lists /orchestrate as a "Nemotron conductor
(NIM)" — an LLM in the loop. This module is the DETERMINISTIC realization of
that role: no LLM, no GPU, no tokens, no network. It chains the demand-side
forecast through the signal bridge (intent/signals.py) into the commander's
intent (intent/intent.py), and hands the resolved regime to the proposer
(forward_proposer.py), which runs the regime's ordered lexicographic passes and
returns advisory proposals.

DOCTRINE (the four-line funnel): model proposes → optimizer disposes → shield
guarantees → loop learns. This module is the TOP of the funnel and the first
line's "model": it turns (forecast, decision frame) into advisory proposals.
It writes nothing and returns no commands — the deterministic core still
disposes every row.

The forecast enters as a DECLARED DATA argument (the /forecast output dict),
never read from a file or fetched over HTTP here — the same separation
discipline as the decision frame (CLAUDE.md 2.5). In production, an edge
function fetches the forecast and passes it in; the conductor stays pure and
testable against that contract.

THE AUDIT TRAIL: the result carries the signal assessment (which signal fired,
against what threshold, with what provenance) alongside the proposer's regime
record (which regime, which pass order, which optima), so an auditor can walk
"why did the engine schedule throughput-first at 07:00?" back to the forecast
number that triggered it.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))
sys.path.insert(0, str(HERE.parent / "policies"))

from forward_proposer import propose          # noqa: E402
from intent.signals import forecast_signals   # noqa: E402


class OrchestrateError(ValueError):
    """A required input the conductor will not guess around."""


def orchestrate(forecast: dict, frame: dict, class_table: dict, *, site: dict,
                now_hour: int, weather_hold: bool = False,
                thresholds: dict | None = None, **propose_kwargs) -> dict:
    """Forecast + frame → advisory proposals under the forecast-derived regime.

    `now_hour` is REQUIRED — it is the whole point: which regime holds at this
    clock hour, given this forecast. `site["power_soft_target_kw"]` is the
    demand-charge-relevant ceiling the grid-peak signal measures against; it is
    required and the conductor refuses to guess it.

    Returns the propose() result augmented with:
      * "signals"     — the signal assessment (fired signals + reasoning +
                        threshold provenance) from intent/signals.py
      * "now_hour"    — the clock hour the regime was resolved for

    Deterministic, pure, writes nothing. A malformed forecast raises
    ForecastContractError (from the bridge); a missing soft target raises
    OrchestrateError.
    """
    if not isinstance(now_hour, int) or not (0 <= now_hour <= 23):
        raise OrchestrateError(f"now_hour must be 0-23, got {now_hour!r}")

    target = site.get("power_soft_target_kw") if isinstance(site, dict) else None
    if target is None:
        raise OrchestrateError(
            "site['power_soft_target_kw'] is required — it is the "
            "demand-charge-relevant ceiling the grid-peak signal measures "
            "against; the conductor refuses to guess it")

    assessment = forecast_signals(
        forecast, site_power_target_kw=float(target), now_hour=now_hour,
        weather_hold=weather_hold, thresholds=thresholds)

    result = propose(frame, class_table, site=site,
                     hour_of_day=now_hour, signals=assessment.signals,
                     **propose_kwargs)

    result["signals"] = assessment.to_dict()
    result["now_hour"] = now_hour
    return result
