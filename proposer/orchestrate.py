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

That walk used to stop one link short at each end. It named the number but not
WHICH forecast produced it, and named the pass order but not WHICH doctrine
artifact chose it; and the solver record dropped the OR-Tools version that
model.py states in its own comment is required to reproduce a plan. The
`provenance` block on the result now carries the forecast's own identity
(`forecast_generated_at`, `priors_fingerprint`), the intent artifact's verified
fingerprint and version, and the caller's run id; the solver record carries
`ortools_version`, `det_budget_s` and `wall_limit_s`. Findings L-43 and L-44.
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
from regime import INTENT, resolve_active     # noqa: E402


class OrchestrateError(ValueError):
    """A required input the conductor will not guess around."""


#: propose() arguments orchestrate() binds itself and does NOT accept as its
#: own. Passing one landed in **propose_kwargs and raised a bare "got multiple
#: values for keyword argument" TypeError from inside propose(); the conductor
#: names the conflict instead (finding L-57).
#:
#: `site` is deliberately NOT here: it IS a parameter of orchestrate(), so
#: passing it twice is a Python-level TypeError on the call itself and never
#: reaches this check. Listing it would be a guard over an unreachable path.
_BOUND_BY_CONDUCTOR = ("hour_of_day", "signals")


def orchestrate(forecast: dict, frame: dict, class_table: dict, *, site: dict,
                now_hour: int, run_id: str, regime: bool = True,
                weather_hold: bool = False,
                thresholds: dict | None = None, **propose_kwargs) -> dict:
    """Forecast + frame → advisory proposals under the forecast-derived regime.

    `now_hour` is REQUIRED — it is the whole point: which regime holds at this
    clock hour, given this forecast. `site["power_soft_target_kw"]` is the
    demand-charge-relevant ceiling the grid-peak signal measures against; it is
    required and the conductor refuses to guess it.

    `run_id` is REQUIRED, and it is the company rule rather than a convenience:
    no number ships without a run ID (CLAUDE.md 2.9). A fire record built from
    this result has to be attributable to a run, and the conductor is the only
    place that knows the caller's. It is echoed back verbatim under
    `provenance`, never generated here — a run id this module invented would
    identify nothing.

    `regime` CHOOSES THE COST (finding L-57). True (the default) runs the
    regime's ordered lexicographic chain, whose third lever does not prove
    OPTIMAL and costs ~10-20x the two-pass solve — right for offline planning,
    too slow for a 30-second live tick. False keeps the signal assessment and
    the regime record but hands the proposer the CHEAP two-pass path, so a
    live-tick caller can have the doctrine's reading of the forecast without
    the doctrine's bill. propose() has always defaulted to cheap; the conductor
    hard-wired the expensive path and left no way out, which made an opt-in
    cost an unavoidable one at the only entry point production would use.

    Returns the propose() result augmented with:
      * "signals"     — the signal assessment (fired signals + reasoning +
                        threshold provenance) from intent/signals.py
      * "now_hour"    — the clock hour the regime was resolved for
      * "regime_path" — whether the expensive chain ran
      * "provenance"  — WHICH forecast, WHICH doctrine, WHICH run (see below)

    THE PROVENANCE BLOCK exists because the audit trail this module's header
    promises was one link short at both ends (findings L-43, L-44). It recorded
    the measured value and the threshold it crossed, but not which forecast
    produced the value nor which doctrine artifact ordered the passes — and a
    forecast is identifiable, deliberately: /forecast returns
    `forecast_generated_at` and `priors_fingerprint` because the priors are
    versioned and hashed for exactly this. The intent artifact carries a
    verified fingerprint for the same reason. Both are copied here, with the
    caller's run id, so "why did the engine schedule throughput-first at 07:00"
    walks all the way back. A forecast that carries neither field yields None
    rather than an omission: a missing identity must be visible in the record,
    not absent from it.

    Deterministic, pure, writes nothing. A malformed forecast raises
    ForecastContractError (from the bridge); a missing soft target, a bad
    now_hour, an empty run_id or a conflicting propose kwarg raise
    OrchestrateError.
    """
    if not isinstance(now_hour, int) or not (0 <= now_hour <= 23):
        raise OrchestrateError(f"now_hour must be 0-23, got {now_hour!r}")

    if not isinstance(run_id, str) or not run_id.strip():
        raise OrchestrateError(
            "run_id is required and must be a non-empty string — no number "
            "ships without a run ID, and a fire record built from this result "
            "has to name the run it came from")

    clash = [k for k in _BOUND_BY_CONDUCTOR if k in propose_kwargs]
    if clash:
        raise OrchestrateError(
            f"the conductor binds {clash} itself; passing it through would be "
            f"a TypeError three frames down. Use the conductor's own "
            f"parameters (site=, now_hour=, regime=) instead")

    target = site.get("power_soft_target_kw") if isinstance(site, dict) else None
    if target is None:
        raise OrchestrateError(
            "site['power_soft_target_kw'] is required — it is the "
            "demand-charge-relevant ceiling the grid-peak signal measures "
            "against; the conductor refuses to guess it")

    assessment = forecast_signals(
        forecast, site_power_target_kw=float(target), now_hour=now_hour,
        weather_hold=weather_hold, thresholds=thresholds)

    intent = propose_kwargs.get("intent") or INTENT
    #: Resolved WHATEVER path runs, so the record always names the regime the
    #: doctrine chose for this hour and these signals -- including when the
    #: caller declined to pay for it.
    active = resolve_active(now_hour, assessment.signals, intent=intent)
    result = propose(frame, class_table, site=site,
                     hour_of_day=now_hour if regime else None,
                     signals=assessment.signals,
                     **propose_kwargs)

    result["signals"] = assessment.to_dict()
    result["now_hour"] = now_hour
    result["regime_path"] = bool(regime)
    result["provenance"] = {
        "run_id": run_id,
        #: WHICH forecast. Both keys are what /forecast emits; None means the
        #: caller passed a forecast that cannot be identified, and that is
        #: recorded rather than hidden.
        "forecast_generated_at": forecast.get("forecast_generated_at"),
        "priors_fingerprint": forecast.get("priors_fingerprint"),
        #: WHICH doctrine ordered the passes, and WHICH regime it chose.
        "intent_fingerprint": intent.fingerprint,
        "intent_version": intent.version,
        "regime": active.regime_key,
    }
    return result
