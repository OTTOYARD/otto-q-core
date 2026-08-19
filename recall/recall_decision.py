"""C9 — the Recall Decision primitive (CLAUDE.md 2.7, verbatim).

The single interface between OTTO-Q and every work-side system — the one place
this kernel touches revenue rather than cost. The kernel never learns what
sector it is in: AssetState/WorkSideSignals/SiteForecast are sector-free.

    interface RecallDecision {
      decide(asset: AssetState, work: WorkSideSignals, site: SiteForecast)
        : { recall_time; target_site; service_bundle: Operation[]; target_ready_time }
    }

Two implementations ship:

  * NaiveThresholdRecall — DELIBERATELY NAIVE, and documented as such. It is a
    faithful reduction of the live rung ladder in
    public.ottoq_evaluate_return_need (captured md5 0c463ada… in
    db/fn_current/): fixed thresholds, evaluated top-down, first hit wins.
    It contains no forecasting, no optimization, no learning. It exists so the
    interface is real on day one and so every smarter successor has a baseline
    to beat ON THE SAME LEDGER.
  * FixedWindowRecall — a deliberately trivial second implementation whose only
    job is to PROVE config-swappability: the call site (`run_recall_cycle`)
    is byte-identical for both. It is not a policy anyone should run.

Every decide() emits exactly one recall event record — inputs snapshot,
decision, implementation name — shaped for the runs machinery: the
`recall_issued` / `recall_refused` event types registered by migration 0045 §4,
run-scoped by sim_run_id like every other twin event. No decision is silent.

Work-side refusal is a FIRST-CLASS EVENT, never an error: `refuse()` records
`recall_refused` and invokes the re-solve hook (rolling re-solve with
previous-feasible retention — the site is never without a schedule). The C8
`work_side_recall_refusal` scenario exercises exactly this path: refused assets
return late and re-enter the queue with immediate urgency.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field, asdict
from typing import Callable, Protocol


# ---------------------------------------------------------------------------
# The three inputs and the one output — sector-free, verbatim from 2.7
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class AssetState:
    asset_id: str
    soc_pct: float                      # SoC/fuel
    reserve_soc_pct: float              # effective reserve (SLA/policy resolved)
    deploy_floor_pct: float
    worst_fault_rank: int = 99          # 0 = safety-critical … 99 = none
    open_fault_count: int = 0
    km_since_pm: float = 0.0
    hours_since_calibration: float = 0.0
    soil_index: float = 0.0
    payload: str | None = None
    comms_age_min: float | None = None  # None = fresh
    home_site: str = ""


@dataclass(frozen=True)
class WorkSideSignals:
    mission_active: bool
    mission_min_remaining: float = 0.0
    demand_forecast: float = 0.5        # 0..1 relative demand pressure
    release_windows: tuple = ()         # ((from_min, to_min), …) sim-minutes


@dataclass(frozen=True)
class SiteForecast:
    sim_min_now: int
    eta_min: float                      # asset -> site travel estimate
    free_capable_points: int
    inbound_assets: int
    price_window_active: bool = False   # cheap-energy window open now
    congestion_wait_min: float = 0.0


@dataclass(frozen=True)
class RecallOutcome:
    recall: bool
    recall_time: int | None             # sim-minute to turn for the site
    target_site: str | None
    service_bundle: tuple               # Operation names, kernel vocabulary
    target_ready_time: int | None
    trigger: str | None                 # rung name (ladder vocabulary)
    urgency: str                        # critical|urgent|routine|scheduled|none
    deferrable: bool | None = None


class RecallDecision(Protocol):
    """The 2.7 interface. Implementations are pure functions of their inputs
    and their frozen config — no hidden state, no randomness."""
    name: str

    def decide(self, asset: AssetState, work: WorkSideSignals,
               site: SiteForecast) -> RecallOutcome: ...


# ---------------------------------------------------------------------------
# The event record — every decision lands in the runs machinery
# ---------------------------------------------------------------------------

@dataclass
class RecallEventLog:
    """Collects ottoq_events-shaped rows (event types registered in 0045 §4:
    recall_issued / recall_refused). In production these insert into
    ottoq_events keyed by sim_run_id; offline they are the committed record."""
    sim_run_id: str
    records: list = field(default_factory=list)

    def emit(self, event_type: str, implementation: str, asset: AssetState,
             work: WorkSideSignals, site: SiteForecast, outcome: RecallOutcome,
             extra: dict | None = None):
        assert event_type in ("recall_issued", "recall_refused")
        payload = {
            "implementation": implementation,
            "inputs": {"asset": asdict(asset), "work": asdict(work),
                       "site": asdict(site)},
            "decision": asdict(outcome),
            **(extra or {}),
        }
        rec = {"event_type": event_type, "sim_run_id": self.sim_run_id,
               "entity_id": asset.asset_id, "sim_min": site.sim_min_now,
               "payload": payload}
        rec["content_hash"] = hashlib.sha256(
            json.dumps(rec, sort_keys=True).encode()).hexdigest()[:16]
        self.records.append(rec)
        return rec


# ---------------------------------------------------------------------------
# Implementation 1 — NAIVE, and saying so
# ---------------------------------------------------------------------------

NAIVE_DEFAULTS = {
    # names and defaults mirror ottoq_policy_get reads in the live function
    "p99_burn_pct_per_min": 0.25,
    "reserve_margin_pct": 15.0,
    "dtc_debt_threshold": 3,
    "comms_stale_min": 90.0,        # comms_stale_ticks(3) * horizon(30)
    "sensor_soil_threshold": 0.35,
    "wash_soil_threshold": 0.50,
    "pm_interval_km": 8000.0,
    "calib_interval_h": 250.0,
    "horizon_min": 30.0,
    "service_min_estimate": 45.0,   # ready-time padding, deliberately crude
}


class NaiveThresholdRecall:
    """The rung ladder of public.ottoq_evaluate_return_need as fixed
    thresholds, top-down, first hit wins. NAIVE BY DESIGN — no forecasting,
    no cost model, no site optimization; `site` is consulted only for ETA and
    the contention gate, exactly as the live function does. Successors replace
    this class behind the same interface; call sites do not change."""

    def __init__(self, config: dict | None = None):
        self.cfg = {**NAIVE_DEFAULTS, **(config or {})}
        self.name = "naive_threshold_v1"

    def decide(self, asset, work, site) -> RecallOutcome:
        c = self.cfg
        now = site.sim_min_now

        def out(trigger, urgency, deferrable, lead_min, bundle):
            return RecallOutcome(
                recall=True, recall_time=now + lead_min, target_site=asset.home_site,
                service_bundle=tuple(bundle), trigger=trigger, urgency=urgency,
                deferrable=deferrable,
                target_ready_time=int(now + lead_min + site.eta_min
                                      + c["service_min_estimate"]))

        burn_guard = c["p99_burn_pct_per_min"] * (site.eta_min + c["horizon_min"])
        bundle_charge = ["dc_fast_charge" if asset.soc_pct < 55 else "l2_charge"]

        if asset.soc_pct <= asset.reserve_soc_pct + burn_guard:          # rung 0
            return out("critical_reserve", "critical", False, 0, bundle_charge)
        if asset.worst_fault_rank == 0:                                  # rung 1
            return out("fault_safety_critical", "critical", False, 0,
                       ["inspection"] + bundle_charge)
        if asset.worst_fault_rank == 1 or asset.open_fault_count >= c["dtc_debt_threshold"]:
            return out("fault_major", "urgent", False, 0, ["inspection"])  # rung 2
        if asset.soc_pct <= asset.reserve_soc_pct + c["reserve_margin_pct"]:
            return out("low_soc_reserve", "urgent", False, 0, bundle_charge)  # rung 3
        if asset.comms_age_min is not None and asset.comms_age_min >= c["comms_stale_min"]:
            return out("comms_stale", "urgent", False, 0, ["inspection"])  # rung 8
        # routine rungs sit behind the contention gate, as live
        if site.congestion_wait_min <= 30.0:
            if asset.km_since_pm >= c["pm_interval_km"] \
               or asset.hours_since_calibration >= c["calib_interval_h"]:
                b = ["inspection"] + (["adas_calibration"]
                                      if asset.hours_since_calibration >= c["calib_interval_h"] else [])
                return out("service_interval_due", "routine", True, 60, b)  # rung 4
            if asset.soil_index >= c["sensor_soil_threshold"]:
                return out("sensor_soil", "routine", True, 30,
                           ["sensor_clean"] + bundle_charge)                # rung 5
            if asset.soil_index >= c["wash_soil_threshold"]:
                return out("wash_cadence", "routine", True, 60, ["exterior_wash"])  # rung 7
        return RecallOutcome(recall=False, recall_time=None, target_site=None,
                             service_bundle=(), target_ready_time=None,
                             trigger=None, urgency="none")


# ---------------------------------------------------------------------------
# Implementation 2 — the swap proof, nothing more
# ---------------------------------------------------------------------------

class FixedWindowRecall:
    """Recalls everything inside a fixed window, nothing outside it. Exists
    only to prove the interface is config-swappable with zero call-site
    changes. Do not run it in anger."""

    def __init__(self, config: dict | None = None):
        cfg = config or {}
        self.window = (cfg.get("from_min", 960), cfg.get("to_min", 1440))
        self.name = "fixed_window_dummy"

    def decide(self, asset, work, site) -> RecallOutcome:
        w0, w1 = self.window
        if w0 <= site.sim_min_now < w1:
            return RecallOutcome(
                recall=True, recall_time=site.sim_min_now,
                target_site=asset.home_site, service_bundle=("l2_charge",),
                target_ready_time=int(site.sim_min_now + site.eta_min + 480),
                trigger="fixed_window", urgency="scheduled", deferrable=True)
        return RecallOutcome(recall=False, recall_time=None, target_site=None,
                             service_bundle=(), target_ready_time=None,
                             trigger=None, urgency="none")


IMPLEMENTATIONS = {
    "naive_threshold_v1": NaiveThresholdRecall,
    "fixed_window_dummy": FixedWindowRecall,
}


def make_recall(config: dict) -> RecallDecision:
    """The swap point: `{"implementation": <name>, …impl config}`. Changing
    the implementation is a CONFIG change; no call site is edited."""
    impl = config.get("implementation", "naive_threshold_v1")
    return IMPLEMENTATIONS[impl]({k: v for k, v in config.items()
                                  if k != "implementation"})


# ---------------------------------------------------------------------------
# The call site (used identically for every implementation) + refusal path
# ---------------------------------------------------------------------------

def run_recall_cycle(impl: RecallDecision, log: RecallEventLog,
                     asset: AssetState, work: WorkSideSignals,
                     site: SiteForecast,
                     work_side_accepts: Callable[[RecallOutcome], bool],
                     resolve: Callable[[str, dict], None]) -> RecallOutcome:
    """One recall evaluation, implementation-agnostic. Emits exactly one event
    per issued recall; a work-side refusal (mission overrun) is a first-class
    `recall_refused` event that triggers re-solve — never an exception."""
    outcome = impl.decide(asset, work, site)
    if not outcome.recall:
        return outcome
    if work_side_accepts(outcome):
        log.emit("recall_issued", impl.name, asset, work, site, outcome)
        return outcome
    log.emit("recall_refused", impl.name, asset, work, site, outcome,
             extra={"refusal_reason": "work-side hold (mission overrun)"})
    resolve("recall_refused", {"asset_id": asset.asset_id,
                               "retry_after_min": work.mission_min_remaining})
    return RecallOutcome(recall=False, recall_time=None, target_site=None,
                         service_bundle=(), target_ready_time=None,
                         trigger="work_side_refusal", urgency="none")
