"""onboard() in SIZING mode — the same model inverted. KERNEL.

Scheduling asks: given this depot, how do I serve this fleet?
Onboarding asks:  given this fleet, what depot do I need?

The two directions share one object. A `SiteProfile` is the INPUT to scheduling and
the OUTPUT of sizing, so a sized depot is immediately runnable: hand the emitted
profile to conformance.harness.run_all() and the same invariants that police a real
site police the proposed one. Nothing here is a parallel model of a depot.

WHAT THIS IS, STATED PLAINLY. This is a sizing HEURISTIC with exact physics and
exact billing, not a solver. It computes:

  - the energy the fleet needs delivered in its service window       (exact)
  - the FLAT-LOAD FLOOR, below which no scheduler can go without storage  (exact)
  - charge-hours and therefore the number of service points needed   (exact, given taper)
  - the storage energy and power required to hold the grid beneath the floor (exact)
  - the recharge that storage then needs, and what it adds to the billed peak (exact)
  - the operating cost of each candidate at the site's real tariff   (exact, sourced)

It does NOT search over layouts, sequence individual assets, or model queueing. Those
are the scheduler's job and the sizer defers to it: every candidate it emits is a
SiteProfile the scheduler can be run against for confirmation.

THE FLAT-LOAD FLOOR IS THE CENTRAL QUANTITY and it is worth naming because it bounds
every claim we can make. If a fleet needs E kWh delivered inside a W-hour window, then
E/W kW is the smallest possible average draw. A perfect scheduler achieves it; nothing
beats it. So:

  - Selling "we shave your peak" above E/W is selling real scheduling work.
  - Selling it below E/W is selling physics that does not exist -- you need storage,
    a longer window, or a smaller fleet.

That boundary is what keeps a sizing pitch honest, and it is computed here rather than
asserted.

WHAT IS DELIBERATELY NOT COSTED. Capital cost of chargers and storage is an INPUT, not
a number this module invents. Research answer R-4 supplies interconnection/service-
upgrade ranges ($2.5-2.9M front-of-meter for MHD truck facilities; $17.5k/station at
small sites; 6-24+ months) and those are surfaced as a labelled RANGE where a grid
upgrade is implied. Per-kWh storage capex has no defensible figure in our merged
research, so passing one is the caller's decision and its absence is reported rather
than papered over.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

from sites.site_profile import SiteProfile, load_site
from sites.tariff import Tariff

HOURS_PER_DAY = 24.0


@dataclass(frozen=True)
class FleetClass:
    """One class of asset in the fleet being onboarded.

    Field names match ottoq_vehicle_classes, which CLAUDE.md 2.3 names as the asset
    profile and which is already sector-agnostic. Nothing here says "vehicle".
    """

    asset_class: str
    count: int
    battery_kwh: float
    max_charge_kw: float
    #: Mean state of charge on arrival and the state it must reach, in percent.
    arrive_soc_pct: float = 20.0
    target_soc_pct: float = 90.0
    #: Fraction of nameplate actually accepted across the session, after taper. The
    #: piecewise curve above ~70% SoC is why this is not 1.0 (CLAUDE.md 2.5).
    taper_efficiency: float = 0.80
    #: Turnarounds per asset per day. Opportunity-charged fleets exceed 1.
    cycles_per_day: float = 1.0

    def energy_per_cycle_kwh(self) -> float:
        return self.battery_kwh * (self.target_soc_pct - self.arrive_soc_pct) / 100.0

    def energy_per_day_kwh(self) -> float:
        return self.energy_per_cycle_kwh() * self.count * self.cycles_per_day

    def effective_kw(self) -> float:
        return self.max_charge_kw * self.taper_efficiency

    def charge_hours_per_day(self) -> float:
        """Total point-hours this class consumes per day."""
        return self.energy_per_day_kwh() / self.effective_kw()


@dataclass(frozen=True)
class FleetSpec:
    fleet_id: str
    classes: tuple[FleetClass, ...]
    #: Hours available to serve the fleet -- the overnight window, typically.
    service_window_h: float = 8.0
    #: Non-fleet site load (lighting, HVAC, offices) present at all times.
    base_load_kw: float = 0.0

    def energy_per_day_kwh(self) -> float:
        return sum(c.energy_per_day_kwh() for c in self.classes)

    def flat_load_floor_kw(self) -> float:
        """E/W: the smallest average draw physics permits. Nothing beats this."""
        return self.energy_per_day_kwh() / self.service_window_h + self.base_load_kw

    def unmanaged_peak_kw(self) -> float:
        """Every asset plugged in at once at full rate -- the no-scheduler case.

        This is what a utility sizes for absent demonstrated load management (R-4:
        EPRI notes utilities may size on "the assumption that all vehicles are
        charging at the same time"). It is the number oversubscription is measured
        against, and the number our product exists to avoid paying for.
        """
        return sum(c.count * c.max_charge_kw for c in self.classes) + self.base_load_kw


@dataclass
class SizingCandidate:
    """One (grid, storage) option, with its physics and its bill."""

    grid_kw: float
    storage_power_kw: float
    storage_energy_kwh: float
    #: kWh storage must deliver during the window to hold the grid at grid_kw.
    deficit_kwh: float
    #: Power drawn to recharge storage outside the window.
    recharge_kw: float
    #: The peak the utility actually bills, window and recharge considered.
    billed_peak_kw: float
    feasible: bool
    infeasible_reason: str = ""
    monthly_cost_usd: float | None = None
    annual_cost_usd: float | None = None
    bill_detail: dict[str, Any] | None = None

    def as_row(self) -> dict[str, Any]:
        return {
            "grid_kw": round(self.grid_kw),
            "storage_power_kw": round(self.storage_power_kw),
            "storage_energy_kwh": round(self.storage_energy_kwh),
            "billed_peak_kw": round(self.billed_peak_kw),
            "feasible": self.feasible,
            "annual_cost_usd": (round(self.annual_cost_usd)
                                if self.annual_cost_usd is not None else None),
            "reason": self.infeasible_reason,
        }


@dataclass
class SizingResult:
    fleet_id: str
    energy_per_day_kwh: float
    flat_load_floor_kw: float
    unmanaged_peak_kw: float
    service_points_needed: dict[str, int]
    #: Classes that cannot be served in this window at ANY point count.
    unservable: dict[str, str] = field(default_factory=dict)
    candidates: list[SizingCandidate] = field(default_factory=list)
    recommended: SizingCandidate | None = None
    notes: list[str] = field(default_factory=list)

    def summary(self) -> dict[str, Any]:
        return {
            "fleet_id": self.fleet_id,
            "energy_per_day_kwh": round(self.energy_per_day_kwh),
            "flat_load_floor_kw": round(self.flat_load_floor_kw),
            "unmanaged_peak_kw": round(self.unmanaged_peak_kw),
            "managed_vs_unmanaged_ratio": round(
                self.unmanaged_peak_kw / self.flat_load_floor_kw, 2
            ) if self.flat_load_floor_kw else None,
            "service_points_needed": self.service_points_needed,
            "unservable": self.unservable,
            "recommended": self.recommended.as_row() if self.recommended else None,
            "candidates": [c.as_row() for c in self.candidates],
            "notes": self.notes,
        }


def service_points_needed(fleet: FleetSpec) -> dict[str, int]:
    """Points per class so every asset is served inside the window.

    Point-hours needed divided by window hours, rounded up -- but NEVER MORE POINTS
    THAN ASSETS. An earlier version could return 9 points for 7 assets, which is
    arithmetically what the division says and physically nonsense: an asset occupies
    one point at a time, so `count` is a hard ceiling. Found by its own test.

    When a single session is longer than the whole window, no number of points fixes
    it -- every asset needs its own point AND still will not finish. That is a window
    problem, not a point-count problem, and `unservable_classes()` reports it rather
    than letting the point count silently absorb an infeasibility.
    """
    out: dict[str, int] = {}
    for c in fleet.classes:
        by_hours = math.ceil(c.charge_hours_per_day() / fleet.service_window_h)
        session_h = c.energy_per_cycle_kwh() / c.effective_kw()
        by_duration = c.count if session_h > fleet.service_window_h else 1
        out[c.asset_class] = min(c.count, max(1, by_hours, by_duration))
    return out


def unservable_classes(fleet: FleetSpec) -> dict[str, str]:
    """Classes whose single session cannot fit the window at any point count.

    Adding points cannot help: an asset charges on one point at a time, so if one
    session exceeds the window the class needs a longer window, a faster point, or a
    smaller SoC delta. Reported explicitly because a point count that quietly rounded
    up would look like a solved problem.
    """
    out: dict[str, str] = {}
    for c in fleet.classes:
        session_h = c.energy_per_cycle_kwh() / c.effective_kw()
        if session_h > fleet.service_window_h + 1e-9:
            out[c.asset_class] = (
                f"one session is {session_h:.2f} h but the window is "
                f"{fleet.service_window_h:.2f} h; no point count fixes this"
            )
    return out


def _day_curve(grid_kw: float, recharge_kw: float, fleet: FleetSpec,
               window_start_min: int = 1320) -> list[tuple[float, float]]:
    """A 24-hour load curve for a candidate, at 15-minute resolution.

    Inside the window the site draws `grid_kw` (the flattened managed load). Outside
    it, base load plus whatever storage recharge is happening. Recharge is spread
    across the whole non-window period, which is the cheapest shape and therefore the
    fair one to cost -- a worse recharge schedule can only make the bill higher.
    """
    win_min = int(fleet.service_window_h * 60)
    pts: list[tuple[float, float]] = []
    for m in range(0, 1440, 15):
        offset = (m - window_start_min) % 1440
        in_window = offset < win_min
        kw = grid_kw if in_window else fleet.base_load_kw + recharge_kw
        pts.append((float(m), kw))
    pts.append((1440.0, fleet.base_load_kw + recharge_kw))
    return pts


def evaluate(fleet: FleetSpec, grid_kw: float, tariff: Tariff, *,
             month: int = 7, historical_peak_kw: float | None = None,
             round_trip_efficiency: float = 0.96) -> SizingCandidate:
    """Physics and cost for one candidate grid size."""
    floor = fleet.flat_load_floor_kw()
    window_h = fleet.service_window_h
    off_window_h = HOURS_PER_DAY - window_h

    if grid_kw >= floor:
        cand = SizingCandidate(
            grid_kw=grid_kw, storage_power_kw=0.0, storage_energy_kwh=0.0,
            deficit_kwh=0.0, recharge_kw=0.0, billed_peak_kw=grid_kw, feasible=True,
        )
    else:
        deficit_kw = floor - grid_kw
        deficit_kwh = deficit_kw * window_h
        #: Storage must hold the deficit AND be charged back through the round trip.
        storage_energy = deficit_kwh / round_trip_efficiency
        recharge_kw = storage_energy / off_window_h if off_window_h > 0 else float("inf")
        cand = SizingCandidate(
            grid_kw=grid_kw, storage_power_kw=deficit_kw,
            storage_energy_kwh=storage_energy, deficit_kwh=deficit_kwh,
            recharge_kw=recharge_kw,
            #: THE TRAP THIS MODEL EXISTS TO CATCH. Recharging the battery draws from
            #: the same meter and counts toward the same monthly peak. A design that
            #: shaves the window down to `grid_kw` and then recharges hard overnight
            #: has moved its peak, not removed it.
            billed_peak_kw=max(grid_kw, fleet.base_load_kw + recharge_kw),
            feasible=True,
        )
        if off_window_h <= 0:
            cand.feasible = False
            cand.infeasible_reason = (
                "service window covers the whole day; storage can never recharge"
            )
        elif cand.billed_peak_kw > grid_kw + 1e-6:
            cand.infeasible_reason = (
                f"recharge sets the billed peak at {cand.billed_peak_kw:.0f} kW, "
                f"above the {grid_kw:.0f} kW the service was sized for"
            )
            cand.feasible = False

    curve = _day_curve(cand.grid_kw, cand.recharge_kw if cand.feasible else 0.0, fleet)
    hist = historical_peak_kw if historical_peak_kw is not None else cand.billed_peak_kw
    bill = tariff.bill(curve, month=month, days=30, historical_peak_kw=hist)
    cand.bill_detail = bill
    cand.monthly_cost_usd = bill["total"]
    cand.annual_cost_usd = bill["total"] * 12
    return cand


def size(fleet: FleetSpec, tariff: Tariff, *, grid_options_kw: list[float] | None = None,
         month: int = 7, round_trip_efficiency: float = 0.96) -> SizingResult:
    """Sweep candidate grid sizes and report the frontier.

    The recommendation is the cheapest FEASIBLE candidate by annual operating cost.
    It is explicitly an operating-cost recommendation: capital cost is not invented
    here, and a caller weighing a smaller service against its upgrade cost has the
    R-4 ranges surfaced in `notes` to do that arithmetic with real figures.
    """
    floor = fleet.flat_load_floor_kw()
    result = SizingResult(
        fleet_id=fleet.fleet_id,
        energy_per_day_kwh=fleet.energy_per_day_kwh(),
        flat_load_floor_kw=floor,
        unmanaged_peak_kw=fleet.unmanaged_peak_kw(),
        service_points_needed=service_points_needed(fleet),
        unservable=unservable_classes(fleet),
    )

    if grid_options_kw is None:
        #: Sweep from half the floor (storage-heavy) to the unmanaged peak (no
        #: scheduling at all), so the frontier spans both extremes of the argument.
        lo, hi = floor * 0.5, max(floor, fleet.unmanaged_peak_kw())
        grid_options_kw = [lo + (hi - lo) * i / 8 for i in range(9)]

    #: THE FLOOR IS ALWAYS EVALUATED, whatever the caller swept. It is the cheapest
    #: point that needs no storage, so a sweep that steps over it silently recommends
    #: a larger service than physics requires -- which is exactly the overbuy this
    #: module exists to prevent.
    if not any(abs(g - floor) < 1e-6 for g in grid_options_kw):
        grid_options_kw = list(grid_options_kw) + [floor]

    for g in sorted(grid_options_kw):
        result.candidates.append(
            evaluate(fleet, g, tariff, month=month,
                     round_trip_efficiency=round_trip_efficiency)
        )

    feasible = [c for c in result.candidates
                if c.feasible and c.annual_cost_usd is not None]
    result.recommended = min(feasible, key=lambda c: c.annual_cost_usd) if feasible else None

    result.notes.append(
        f"Flat-load floor is {floor:,.0f} kW: the fleet needs "
        f"{fleet.energy_per_day_kwh():,.0f} kWh inside a {fleet.service_window_h:.0f}-hour "
        f"window, so no scheduler can average less. Below this, storage is not an "
        f"optimisation, it is a requirement."
    )
    result.notes.append(
        f"Unmanaged peak is {fleet.unmanaged_peak_kw():,.0f} kW -- what a utility sizes "
        f"for absent demonstrated load management (R-4). Managed-to-unmanaged ratio is "
        f"{fleet.unmanaged_peak_kw()/floor:.2f}:1, which is the service capacity "
        f"scheduling alone avoids buying."
    )
    if result.recommended and result.recommended.storage_energy_kwh > 0:
        result.notes.append(
            "The recommended candidate uses storage. Its recharge draws from the same "
            "meter and counts toward the same monthly peak, which is modelled: a design "
            "that shaves the window and then recharges hard has moved its peak, not "
            "removed it."
        )
    if result.unservable:
        result.notes.append(
            "UNSERVABLE CLASSES: " + "; ".join(
                f"{k} ({v})" for k, v in sorted(result.unservable.items())
            ) + ". The sizing below still reports energy and cost, but the window "
            "cannot serve these classes at any point count."
        )
    result.notes.append(
        "CAPITAL COST IS NOT INCLUDED. R-4 gives front-of-meter service-upgrade cost at "
        "$2.5-2.9M for US medium/heavy-duty truck charging facilities and $17,500 per "
        "DCFC station at small sites, with 6-24+ month lead times; no defensible per-kWh "
        "storage capex exists in merged research, so it is a caller input, not a number "
        "this module invents."
    )
    return result


def to_site_profile(fleet: FleetSpec, result: SizingResult, tariff_doc: dict[str, Any],
                    *, site_id: str, name: str,
                    unit_energy_kwh: float = 3000.0,
                    unit_power_kw: float = 1500.0) -> SiteProfile:
    """Emit the recommended sizing AS A SiteProfile -- the closure of the loop.

    The output of onboarding is the input to scheduling. Hand this to
    conformance.harness.run_all(site) and the proposed depot is checked by the same
    invariants as a real one, which is the only way a sizing claim earns belief.

    Storage is expressed in whole units because that is how it is bought; the unit
    defaults are the Tesla Megapack 2 XL figures already in ottoq_bess_units.
    """
    rec = result.recommended
    if rec is None:
        raise ValueError(f"{result.fleet_id}: no feasible candidate to emit")

    doc: dict[str, Any] = {
        "site_id": site_id,
        "name": name,
        "notes": (
            f"EMITTED BY onboarding.sizer FROM FLEET {fleet.fleet_id}. Flat-load floor "
            f"{result.flat_load_floor_kw:,.0f} kW; unmanaged peak "
            f"{result.unmanaged_peak_kw:,.0f} kW; recommended service "
            f"{rec.grid_kw:,.0f} kW at a billed peak of {rec.billed_peak_kw:,.0f} kW. "
            f"Capital cost is not included -- see SizingResult.notes."
        ),
        "grid": {"service_capacity_kw": round(rec.grid_kw), "voltage_class": "primary"},
        "installed_charger_kw": round(
            sum(c.count * c.max_charge_kw for c in fleet.classes)
        ),
        "tariff": tariff_doc,
    }
    if rec.storage_energy_kwh > 0:
        units = max(1, math.ceil(rec.storage_energy_kwh / (unit_energy_kwh * 0.85)))
        doc["storage"] = {
            "power_kw": unit_power_kw, "energy_kwh": unit_energy_kwh, "units": units,
            "round_trip_efficiency": 0.96, "soc_min_pct": 10, "soc_max_pct": 95,
            "recharge_counts_toward_peak": True,
        }
    return load_site(doc)


def load_fleet(doc: dict[str, Any]) -> FleetSpec:
    return FleetSpec(
        fleet_id=doc["fleet_id"],
        classes=tuple(
            FleetClass(
                asset_class=c["asset_class"], count=int(c["count"]),
                battery_kwh=float(c["battery_kwh"]),
                max_charge_kw=float(c["max_charge_kw"]),
                arrive_soc_pct=float(c.get("arrive_soc_pct", 20.0)),
                target_soc_pct=float(c.get("target_soc_pct", 90.0)),
                taper_efficiency=float(c.get("taper_efficiency", 0.80)),
                cycles_per_day=float(c.get("cycles_per_day", 1.0)),
            )
            for c in doc["classes"]
        ),
        service_window_h=float(doc.get("service_window_h", 8.0)),
        base_load_kw=float(doc.get("base_load_kw", 0.0)),
    )
