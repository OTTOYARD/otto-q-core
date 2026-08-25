"""The portable tariff object and its billing engine — KERNEL, sector-agnostic.

WHY THIS EXISTS. Until now the only tariff in the system was Nashville's NES GSA-3,
and the site power cap was the literal `SITE_POWER_CAP_KW = 3000.0` in
conformance/harness.py. Both are Nashville-shaped assumptions wearing the costume of
kernel constants. Research answer R-5 measured how badly that generalizes:

  - Demand-charge LEVEL spans ~$4.7/kW/mo (SRP) to ~$45/kW/mo (SCE TOU-8) — a 10x
    spread — and the SHAPE varies at least as much as the level.
  - The demand INTERVAL is a hard regional split: 15-minute in the West, Southwest
    and Texas; 30-minute in the Southeast (FPL, Georgia Power, NES). R-5's warning is
    exact: "A scheduler hard-coding NCP_30min (Nashville's shape) will silently
    mis-model every California, Arizona, Texas and Nevada depot."
  - A tariff has a LIST of priced demand components, not one. SCE has two to three,
    LADWP three, APS two, Georgia Power none plus a demand floor.
  - Ratchets are common at 80-95% over 11-12 months. Nashville's 30%/12-month is at
    the very bottom of the observed range, so it is the LEAST punishing tariff we
    could have calibrated against.

So `demand` is a list, `interval_min` is a first-class field with no default, and
seasons and time-of-use windows are declared per component. R-5 named `interval_min`
the field most likely to be wrong if omitted; here it has no default and validation
rejects a component without it.

WHAT THIS IS NOT. This computes what a tariff would bill for a given load curve. It
does not decide anything. Nothing here is sector-specific: a mine, a vertiport and a
robotaxi depot all buy electricity on schedules of exactly this shape.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

SEASONS = ("all", "summer", "winter", "transition", "summer_peak")
BASES = ("NCP", "CP", "TOU")
PERIODS = ("month", "day")


class TariffError(ValueError):
    """A tariff that cannot be billed. Raised at load time, never mid-computation."""


@dataclass(frozen=True)
class Tier:
    """A price tier on a single billed quantity.

    NES GSA-3 is the motivating case: $21.40/kW for the first 1,000 kW and $21.78/kW
    for everything above. That is ONE demand quantity priced in two tiers, not two
    demand components, and modelling it as two components would double-count the
    peak. `up_to_kw=None` means the tier runs to infinity and must be last.
    """

    up_to_kw: float | None
    rate: float


@dataclass(frozen=True)
class TouWindow:
    """A named time-of-use window as half-open minute-of-day ranges.

    Ranges may wrap past midnight (start > end), which is how off-peak windows are
    normally written. Kept as minutes-of-day rather than hours because 15-minute
    demand intervals do not divide cleanly into an hours-only model.

    `days` records which days the window applies (R-6: APS is weekdays-only, NV
    Energy is daily -- the difference is real tariff structure, not noise). The
    billing engine prices ONE REPRESENTATIVE DAY repeated for the month, and that
    day is treated as a weekday; a weekday-only window therefore slightly
    overstates on-peak energy for the ~8.7 weekend days it does not cover. Stated
    rather than silently absorbed: the demand side -- which dominates -- is
    unaffected when the month's peak falls on a weekday.
    """

    name: str
    ranges: tuple[tuple[int, int], ...]
    days: str = "daily"                       # "daily" | "weekdays"

    def contains(self, minute_of_day: int) -> bool:
        m = minute_of_day % 1440
        for lo, hi in self.ranges:
            if lo <= hi:
                if lo <= m < hi:
                    return True
            elif m >= lo or m < hi:   # wraps midnight
                return True
        return False


@dataclass(frozen=True)
class DemandComponent:
    """One priced demand charge.

    `basis`:
      NCP — non-coincident peak: the site's own highest interval in the period.
            Most common; dominant in the West/Southwest/Texas.
      TOU — the highest interval occurring INSIDE a named window. Almost always a
            supplement to an NCP component rather than a stand-alone basis.
      CP  — coincident peak: the site's demand at the moment the SYSTEM peaks.
            Rare below transmission level. Requires an externally supplied set of
            coincident intervals; billing raises rather than guessing.
    """

    label: str
    basis: str
    interval_min: int
    tiers: tuple[Tier, ...]
    tou_window: str | None = None
    season: str = "all"
    period: str = "month"

    def price(self, billed_kw: float) -> float:
        """Price a demand quantity through the tier ladder."""
        total, lower = 0.0, 0.0
        for tier in self.tiers:
            upper = tier.up_to_kw if tier.up_to_kw is not None else float("inf")
            span = max(0.0, min(billed_kw, upper) - lower)
            total += span * tier.rate
            lower = upper
            if billed_kw <= upper:
                break
        return total


@dataclass(frozen=True)
class EnergyRate:
    season: str
    tou_window: str | None
    rate_per_kwh: float


@dataclass(frozen=True)
class HoursUseBlocks:
    """Declining energy blocks keyed to HOURS-USE OF DEMAND (Georgia Power PLL-18).

    The tariff folds the demand charge into declining kWh blocks whose boundaries
    are expressed as "N hours times the billing demand": hours-use = kWh / billing
    demand, and a customer that runs more hours at the same demand pushes energy
    into the cheap tail. R-6 read the table verbatim from the primary PDF.

    `first_blocks` price kWh WITHIN `base_hours` x demand, in absolute-kWh tiers
    (Tier.up_to_kw reused as up-to-kWh); `tail_blocks` price kWh beyond, in
    hours-use tiers. `min_bill_fixed` + `min_bill_per_kw` form the minimum-bill
    FLOOR (R-6: a floor, not a demand charge on top) -- the customer pays the
    greater of the block charge and the floor.
    """

    base_hours: float
    first_blocks: tuple[Tier, ...]
    tail_blocks: tuple[tuple[float, float], ...]
    min_bill_fixed: float = 0.0
    min_bill_per_kw: float = 0.0

    def energy_cost(self, kwh: float, billing_demand_kw: float) -> float:
        base_cap = self.base_hours * billing_demand_kw
        within = min(kwh, base_cap)
        cost, lower = 0.0, 0.0
        for t in self.first_blocks:
            upper = t.up_to_kw if t.up_to_kw is not None else float("inf")
            span = max(0.0, min(within, upper) - lower)
            cost += span * t.rate
            lower = upper
            if within <= upper:
                break
        excess = max(0.0, kwh - base_cap)
        prev_hours = self.base_hours
        for up_to_hours, rate in self.tail_blocks:
            upper_kwh = ((up_to_hours - prev_hours) * billing_demand_kw
                         if up_to_hours != float("inf") else float("inf"))
            span = min(excess, upper_kwh)
            cost += span * rate
            excess -= span
            prev_hours = up_to_hours
            if excess <= 0:
                break
        return cost

    def floor(self, billing_demand_kw: float) -> float:
        return self.min_bill_fixed + self.min_bill_per_kw * billing_demand_kw


@dataclass(frozen=True)
class Ratchet:
    """A billing floor set by a historical peak.

    R-5: typical is 80-95% over 11-12 months (DOE/PNNL FEDS baseline: 80% over 11).
    Georgia Power reaches 95%; LADWP's facilities charge is effectively 100% over 12.
    NES's 30%/12 is unusually lenient, which is why calibrating only against Nashville
    understates how much one excursion costs everywhere else.
    """

    percent: float
    lookback_months: int
    basis_season: str | None = None

    def floor_kw(self, historical_peak_kw: float) -> float:
        return self.percent / 100.0 * historical_peak_kw


@dataclass(frozen=True)
class Tariff:
    tariff_id: str
    utility: str
    schedule_code: str
    source_url: str
    source_label: str                     # primary | regulatory | third-party
    fixed_charge_per_month: float = 0.0
    demand: tuple[DemandComponent, ...] = ()
    energy: tuple[EnergyRate, ...] = ()
    ratchet: Ratchet | None = None
    #: When set, ENERGY is priced by hours-use declining blocks (demand
    #: folded in) instead of the energy[] list, and the min-bill floor
    #: applies. demand[] should then be empty or true adders only.
    hours_use_blocks: "HoursUseBlocks | None" = None
    tou_windows: tuple[TouWindow, ...] = ()
    summer_months: tuple[int, ...] = (6, 7, 8, 9)
    winter_months: tuple[int, ...] = (12, 1, 2, 3)
    demand_charge_free: bool = False
    demand_charge_free_expiry: str | None = None
    separate_meter_required: bool = False
    notes: str = ""

    # ---- season & window helpers -------------------------------------------------
    def season_of(self, month: int) -> str:
        if month in self.summer_months:
            return "summer"
        if month in self.winter_months:
            return "winter"
        return "transition"

    def window(self, name: str) -> TouWindow | None:
        for w in self.tou_windows:
            if w.name == name:
                return w
        return None

    def _season_applies(self, declared: str, actual: str) -> bool:
        if declared == "all":
            return True
        if declared == "summer_peak":
            return actual == "summer"
        return declared == actual

    # ---- billing -----------------------------------------------------------------
    def bill(
        self,
        load_kw: list[tuple[float, float]],
        *,
        month: int,
        days: int = 30,
        historical_peak_kw: float = 0.0,
        coincident_minutes: set[int] | None = None,
    ) -> dict[str, Any]:
        """Bill a load curve.

        `load_kw` is [(minute_from_period_start, kw)] — a step function, each point
        holding until the next. Demand is computed per component at that component's
        OWN interval, which is the whole point of the object: a 30-minute basis and a
        15-minute basis bill the same curve differently, and by R-5's estimate a
        30-minute excursion differs by about half a charger's nameplate.

        `historical_peak_kw` drives the ratchet and cannot be derived from one run —
        it is a property of the site's billing history, so it is an explicit input.
        """
        season = self.season_of(month)
        lines: list[dict[str, Any]] = []

        if self.hours_use_blocks is not None:
            return self._bill_hours_use(load_kw, month=month, days=days,
                                        historical_peak_kw=historical_peak_kw,
                                        season=season)

        energy_kwh = _energy_by_window(load_kw, self)
        energy_cost = 0.0
        for name, kwh in sorted(energy_kwh.items()):
            rate = self._energy_rate(season, name)
            if rate is None:
                raise TariffError(
                    f"{self.tariff_id}: no energy rate for season={season!r} "
                    f"window={name!r}. Every hour of the curve must be priced."
                )
            cost = kwh * rate
            energy_cost += cost
            lines.append({"kind": "energy", "window": name, "kwh": round(kwh, 2),
                          "rate_per_kwh": rate, "cost": round(cost, 2)})

        demand_cost = 0.0
        billed_peaks: dict[str, float] = {}
        if not self.demand_charge_free:
            for comp in self.demand:
                if not self._season_applies(comp.season, season):
                    continue
                measured = _peak_for(load_kw, comp, self, coincident_minutes)
                billed = measured
                floor = 0.0
                if self.ratchet and comp.basis == "NCP" and comp.tou_window is None:
                    floor = self.ratchet.floor_kw(historical_peak_kw)
                    billed = max(billed, floor)
                periods = days if comp.period == "day" else 1
                cost = comp.price(billed) * periods
                demand_cost += cost
                billed_peaks[comp.label] = billed
                lines.append({
                    "kind": "demand", "label": comp.label, "basis": comp.basis,
                    "interval_min": comp.interval_min, "window": comp.tou_window,
                    "measured_kw": round(measured, 2), "ratchet_floor_kw": round(floor, 2),
                    "billed_kw": round(billed, 2), "periods": periods,
                    "cost": round(cost, 2),
                })

        total = energy_cost + demand_cost + self.fixed_charge_per_month
        return {
            "tariff_id": self.tariff_id, "season": season, "month": month,
            "energy_cost": round(energy_cost, 2),
            "demand_cost": round(demand_cost, 2),
            "fixed_cost": round(self.fixed_charge_per_month, 2),
            "total": round(total, 2),
            "billed_peaks_kw": {k: round(v, 2) for k, v in billed_peaks.items()},
            "lines": lines,
        }

    def _bill_hours_use(self, load_kw, *, month: int, days: int,
                        historical_peak_kw: float, season: str) -> dict[str, Any]:
        """Georgia-Power-shaped billing: demand folded into declining blocks.

        Billing demand takes the ratchet floor first (PLL-18 summer: greatest of
        current and 95 percent of the prior summer peak; the 60-percent-of-winter
        leg is NOT modelled because every committed run bills a summer month --
        stated rather than silently absorbed). One day's curve repeats for the
        month, so monthly kWh = day kWh x days.
        """
        hub = self.hours_use_blocks
        interval = self.demand[0].interval_min if self.demand else 30
        peaks = _interval_peaks(load_kw, interval)
        measured = max((kw for _, kw in peaks), default=0.0)
        billed = measured
        floor_kw = 0.0
        if self.ratchet:
            floor_kw = self.ratchet.floor_kw(historical_peak_kw)
            billed = max(billed, floor_kw)

        day_kwh = sum(_energy_by_window(load_kw, self).values())
        month_kwh = day_kwh * days
        blocks = hub.energy_cost(month_kwh, billed)
        floor_bill = hub.floor(billed)
        total_core = max(blocks, floor_bill)
        hours_use = month_kwh / billed if billed else 0.0

        total = total_core + self.fixed_charge_per_month
        return {
            "tariff_id": self.tariff_id, "season": season, "month": month,
            "energy_cost": round(blocks, 2),
            "demand_cost": 0.0,
            "min_bill_floor": round(floor_bill, 2),
            "floor_binding": floor_bill > blocks,
            "fixed_cost": round(self.fixed_charge_per_month, 2),
            "total": round(total, 2),
            "billed_peaks_kw": {"billing demand": round(billed, 2)},
            "hours_use": round(hours_use, 1),
            "lines": [{"kind": "hours_use_blocks", "kwh": round(month_kwh, 1),
                       "billing_demand_kw": round(billed, 2),
                       "ratchet_floor_kw": round(floor_kw, 2),
                       "cost": round(total_core, 2)}],
        }

    def _energy_rate(self, season: str, window: str) -> float | None:
        best = None
        for e in self.energy:
            if not self._season_applies(e.season, season):
                continue
            if e.tou_window in (None, window):
                # a window-specific rate beats an all-window rate
                if e.tou_window == window:
                    return e.rate_per_kwh
                best = e.rate_per_kwh if best is None else best
        return best


# ---- interval maths --------------------------------------------------------------

def _interval_peaks(load_kw: list[tuple[float, float]], interval_min: int
                    ) -> list[tuple[float, float]]:
    """Average kW within each fixed interval — how a demand meter actually reads.

    A demand meter integrates over its interval; it does not take the instantaneous
    maximum. Using the instantaneous max would overstate every peak and would make a
    15-minute and a 30-minute basis produce the same answer, erasing exactly the
    distinction R-5 says must not be erased.
    """
    if not load_kw:
        return []
    pts = sorted(load_kw)
    end = pts[-1][0]
    out: list[tuple[float, float]] = []
    start = 0.0
    while start < end:
        stop = start + interval_min
        energy = 0.0
        for i, (t, kw) in enumerate(pts):
            seg_end = pts[i + 1][0] if i + 1 < len(pts) else end
            lo, hi = max(t, start), min(seg_end, stop)
            if hi > lo:
                energy += kw * (hi - lo)
        out.append((start, energy / interval_min))
        start = stop
    return out


def _peak_for(load_kw, comp: DemandComponent, tariff: Tariff,
              coincident_minutes: set[int] | None) -> float:
    intervals = _interval_peaks(load_kw, comp.interval_min)
    if not intervals:
        return 0.0
    if comp.basis == "CP":
        if coincident_minutes is None:
            raise TariffError(
                f"{tariff.tariff_id}/{comp.label}: a coincident-peak component needs "
                f"the system-peak intervals supplied; it cannot be inferred from site "
                f"load. Pass coincident_minutes= or model the component as NCP."
            )
        vals = [kw for start, kw in intervals
                if int(start) in coincident_minutes]
        return max(vals) if vals else 0.0
    if comp.basis == "TOU":
        win = tariff.window(comp.tou_window or "")
        if win is None:
            raise TariffError(
                f"{tariff.tariff_id}/{comp.label}: names TOU window "
                f"{comp.tou_window!r} which the tariff does not define."
            )
        vals = [kw for start, kw in intervals if win.contains(int(start))]
        return max(vals) if vals else 0.0
    return max(kw for _, kw in intervals)


def _energy_by_window(load_kw, tariff: Tariff) -> dict[str, float]:
    """kWh split by TOU window. A tariff with no windows bills everything as 'all'."""
    if not load_kw:
        return {}
    pts = sorted(load_kw)
    end = pts[-1][0]
    out: dict[str, float] = {}
    for i, (t, kw) in enumerate(pts):
        seg_end = pts[i + 1][0] if i + 1 < len(pts) else end
        m = t
        while m < seg_end:
            nxt = min(seg_end, m + 1.0)
            name = "all"
            for w in tariff.tou_windows:
                if w.contains(int(m)):
                    name = w.name
                    break
            out[name] = out.get(name, 0.0) + kw * (nxt - m) / 60.0
            m = nxt
    return out


# ---- loading ---------------------------------------------------------------------

def load_tariff(doc: dict[str, Any]) -> Tariff:
    def tiers_of(d: dict[str, Any], label: str) -> tuple[Tier, ...]:
        raw = d.get("tiers")
        if raw is None:
            if "rate_per_kw" not in d:
                raise TariffError(f"demand component {label!r}: needs tiers or rate_per_kw")
            raw = [{"up_to_kw": None, "rate": d["rate_per_kw"]}]
        ts = tuple(Tier(t.get("up_to_kw"), float(t["rate"])) for t in raw)
        for t in ts[:-1]:
            if t.up_to_kw is None:
                raise TariffError(
                    f"demand component {label!r}: only the LAST tier may be unbounded"
                )
        return ts

    demand = []
    for d in doc.get("demand", []):
        label = d.get("label", "?")
        if "interval_min" not in d:
            raise TariffError(
                f"demand component {label!r}: interval_min is required and has no "
                f"default. 15-minute and 30-minute bases bill the same curve "
                f"differently (R-5); guessing it silently mis-models the site."
            )
        basis = d.get("basis", "NCP")
        if basis not in BASES:
            raise TariffError(f"demand component {label!r}: basis must be one of {BASES}")
        season = d.get("season", "all")
        if season not in SEASONS:
            raise TariffError(f"demand component {label!r}: season must be one of {SEASONS}")
        period = d.get("period", "month")
        if period not in PERIODS:
            raise TariffError(f"demand component {label!r}: period must be one of {PERIODS}")
        if basis == "TOU" and not d.get("tou_window"):
            raise TariffError(f"demand component {label!r}: TOU basis needs a tou_window")
        demand.append(DemandComponent(
            label=label, basis=basis, interval_min=int(d["interval_min"]),
            tiers=tiers_of(d, label), tou_window=d.get("tou_window"),
            season=season, period=period,
        ))

    energy = tuple(
        EnergyRate(e.get("season", "all"), e.get("tou_window"), float(e["rate_per_kwh"]))
        for e in doc.get("energy", [])
    )
    windows = tuple(
        TouWindow(w["name"], tuple((int(a), int(b)) for a, b in w["ranges"]),
                  w.get("days", "daily"))
        for w in doc.get("tou_windows", [])
    )
    r = doc.get("ratchet")
    ratchet = Ratchet(float(r["percent"]), int(r["lookback_months"]),
                      r.get("basis_season")) if r else None

    hb = doc.get("hours_use_blocks")
    hours_use = None
    if hb:
        hours_use = HoursUseBlocks(
            base_hours=float(hb["base_hours"]),
            first_blocks=tuple(Tier(t.get("up_to_kwh"), float(t["rate"]))
                               for t in hb["first_blocks"]),
            tail_blocks=tuple((float(t["up_to_hours"]) if t["up_to_hours"] is not None
                               else float("inf"), float(t["rate"]))
                              for t in hb["tail_blocks"]),
            min_bill_fixed=float(hb.get("min_bill_fixed", 0.0)),
            min_bill_per_kw=float(hb.get("min_bill_per_kw", 0.0)),
        )

    t = Tariff(
        tariff_id=doc["tariff_id"], utility=doc["utility"],
        schedule_code=doc["schedule_code"], source_url=doc.get("source_url", ""),
        source_label=doc.get("source_label", "third-party"),
        fixed_charge_per_month=float(doc.get("fixed_charge_per_month", 0.0)),
        demand=tuple(demand), energy=energy, ratchet=ratchet,
        hours_use_blocks=hours_use, tou_windows=windows,
        summer_months=tuple(doc.get("summer_months", (6, 7, 8, 9))),
        winter_months=tuple(doc.get("winter_months", (12, 1, 2, 3))),
        demand_charge_free=bool(doc.get("demand_charge_free", False)),
        demand_charge_free_expiry=doc.get("demand_charge_free_expiry"),
        separate_meter_required=bool(doc.get("separate_meter_required", False)),
        notes=doc.get("notes", ""),
    )
    for comp in t.demand:
        if comp.basis == "TOU" and t.window(comp.tou_window or "") is None:
            raise TariffError(
                f"{t.tariff_id}/{comp.label}: names TOU window {comp.tou_window!r} "
                f"which the tariff does not define"
            )
    if not t.energy and t.hours_use_blocks is None:
        raise TariffError(f"{t.tariff_id}: a tariff with no energy rate cannot bill a curve")
    if t.hours_use_blocks is not None and not t.energy:
        # blocks price the energy; a zero-rate row keeps kWh accounting alive
        t = Tariff(**{**t.__dict__, "energy": (EnergyRate("all", None, 0.0),)})
    return t
