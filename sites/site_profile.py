"""SiteProfile — a first-class declarative object for THE PLACE. KERNEL.

THE GAP THIS CLOSES. A pack describes the assets and the work. Nothing described the
site, so the site's properties leaked into code as constants: the conformance harness
carried `SITE_POWER_CAP_KW = 3000.0`, and the only tariff in the system was
Nashville's. Four separately-proven problems trace to that one missing object — every
committed scenario's power cap is arithmetically unreachable, the tariff never reaches
the objective, there is no battery-buffered scenario, and the ratchet is unmodelled
(docs/BENCHMARK_CREDIBILITY.md). Pack + SiteProfile = a complete runnable description.

KERNEL PURITY. Nothing here names a sector. A mine, a vertiport, a yard and a robotaxi
depot each have a grid connection, a tariff, maybe storage, a physical layout with
travel times, an environment, and maybe robotics. The declared VALUES differ; the
object does not. If sector logic ever needs to enter this file, CLAUDE.md 2.2 says
that is a platform-thesis finding to escalate, not to absorb.

THE POWER MODEL IS TWO-LEVEL, AND THAT IS THE POINT (research answer R-4).
A single scalar "site power cap" is the wrong abstraction, and R-4 says precisely why:

  "Panel capacity and utility service capacity are distinct constraints. Available
   breaker slots do not guarantee that the utility service entrance, utility
   transformer, or distribution feeder has sufficient capacity."

The binding limit is the utility service entrance / service transformer — utility-side,
not the customer panel — with dedicated switchgear as a second downstream limit for
DCFC above 100 kW. So `service_capacity_kw` is the cap that binds, and the sum of
charger nameplate is a SEPARATE, larger quantity. Their ratio is the oversubscription
ratio, and R-4 measures it at ~2:1 to ~3.4:1 in normal practice (band ~1.4:1 to ~7:1,
the extreme being battery-buffered). Deliberate oversubscription is standard for
multi-charger depots — but only when paired with certified load management, which is
what this kernel is. Making the ratio a derived, reportable quantity rather than an
accident of two unrelated constants is the whole reason for the split.

A profile whose chargers cannot exceed its service capacity is not a hard site: it is
a site where the scheduler has nothing to do, and `is_binding()` says so out loud. That
is the defect documented in BENCHMARK_CREDIBILITY, made detectable by construction.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from sites.tariff import Tariff, TariffError, load_tariff

PROFILE_DIR = Path(__file__).parent / "profiles"


class SiteProfileError(ValueError):
    """A site description that cannot be run."""


@dataclass(frozen=True)
class GridConnection:
    """The utility side. `service_capacity_kw` is the limit that actually binds."""

    service_capacity_kw: float
    #: Utility transformer thermal rating. R-4 flags transformer headroom as the real
    #: binding quantity where it differs from the headline service figure.
    transformer_kw: float | None = None
    #: Dedicated switchgear rating; R-4 notes DCFC >100 kW typically requires it.
    switchgear_kw: float | None = None
    voltage_class: str = "primary"
    #: A safety margin held back from the cap, as the depots table already models.
    safety_margin_pct: float = 0.0
    upgrade_lead_time_months: tuple[int, int] | None = None
    upgrade_cost_usd: tuple[float, float] | None = None

    def effective_cap_kw(self) -> float:
        """The smallest binding limit, after margin. This is what a scheduler obeys."""
        limits = [self.service_capacity_kw]
        if self.transformer_kw is not None:
            limits.append(self.transformer_kw)
        if self.switchgear_kw is not None:
            limits.append(self.switchgear_kw)
        return min(limits) * (1.0 - self.safety_margin_pct / 100.0)

    def binding_level(self) -> str:
        """Which physical level binds — the thing an operator would actually upgrade."""
        pairs = [("service", self.service_capacity_kw)]
        if self.transformer_kw is not None:
            pairs.append(("transformer", self.transformer_kw))
        if self.switchgear_kw is not None:
            pairs.append(("switchgear", self.switchgear_kw))
        return min(pairs, key=lambda p: p[1])[0]


@dataclass(frozen=True)
class Storage:
    """On-site storage. Sized by ENERGY, not power — see docs/BESS_SITE_ACQUISITION_THESIS.md.

    The correction that document records: beyond roughly 1.7 hours of duration it is
    the energy requirement, not the power requirement, that sets the pack count. A
    4-hour wave needs ~4.7 Megapacks, not the 2 a power-only calculation suggests.
    Recharge counts toward the monthly peak, so recharge must itself be scheduled —
    which is why `recharge_counts_toward_peak` is stated rather than assumed.
    """

    power_kw: float
    energy_kwh: float
    round_trip_efficiency: float = 0.96
    soc_min_pct: float = 10.0
    soc_max_pct: float = 95.0
    units: int = 1
    recharge_counts_toward_peak: bool = True

    def usable_kwh(self) -> float:
        return self.energy_kwh * self.units * (self.soc_max_pct - self.soc_min_pct) / 100.0

    def total_power_kw(self) -> float:
        return self.power_kw * self.units

    def duration_h(self) -> float:
        p = self.total_power_kw()
        return self.usable_kwh() / p if p else 0.0


@dataclass(frozen=True)
class Layout:
    """Physical geometry as the scheduler experiences it: durations and capacities."""

    move_duration_min: float = 4.0
    path_capacity: int = 2
    dcfc_cooldown_min: float = 18.0


@dataclass(frozen=True)
class Environment:
    cold_start_below_c: float | None = None
    cold_start_penalty_min: float = 0.0
    ambient_profile: str | None = None


@dataclass(frozen=True)
class Robotics:
    """Installed automation. Real and shipped — arm mate/demate cycles, tethers."""

    arms: int = 0
    mate_min: float = 0.0
    demate_min: float = 0.0
    tether_release_supported: bool = True


@dataclass(frozen=True)
class SiteProfile:
    site_id: str
    name: str
    grid: GridConnection
    tariff: Tariff
    storage: Storage | None = None
    layout: Layout = field(default_factory=Layout)
    environment: Environment = field(default_factory=Environment)
    robotics: Robotics = field(default_factory=Robotics)
    #: Sum of installed charger nameplate kW. Deliberately SEPARATE from the grid
    #: connection — their ratio is the oversubscription ratio (R-4).
    installed_charger_kw: float = 0.0
    timezone: str = "UTC"
    notes: str = ""

    # ---- the derived quantities that make the split earn its keep ----------------
    def power_cap_kw(self) -> float:
        """The cap a scheduler must respect."""
        return self.grid.effective_cap_kw()

    def oversubscription_ratio(self) -> float | None:
        """installed nameplate / service capacity. R-4: ~2:1 to ~3.4:1 is normal."""
        cap = self.grid.service_capacity_kw
        if not cap or not self.installed_charger_kw:
            return None
        return self.installed_charger_kw / cap

    def is_binding(self) -> bool:
        """Can the site's own chargers exceed its cap?

        If not, the power cap is decoration: no schedule can violate it, so a run
        reporting 'zero power-cap violations' has measured arithmetic rather than
        scheduling. That is exactly the vacuous claim withdrawn in
        docs/BENCHMARK_CREDIBILITY.md, and the point of surfacing it here is that a
        profile can now be checked for it before a benchmark is run on it.
        """
        return self.installed_charger_kw > self.power_cap_kw()

    def headroom_report(self) -> dict[str, Any]:
        ratio = self.oversubscription_ratio()
        return {
            "site_id": self.site_id,
            "service_capacity_kw": self.grid.service_capacity_kw,
            "effective_cap_kw": round(self.power_cap_kw(), 1),
            "binding_level": self.grid.binding_level(),
            "installed_charger_kw": self.installed_charger_kw,
            "oversubscription_ratio": round(ratio, 2) if ratio else None,
            "within_r4_observed_band": (1.4 <= ratio <= 7.0) if ratio else None,
            "is_binding": self.is_binding(),
            "storage_kw": self.storage.total_power_kw() if self.storage else 0.0,
            "storage_usable_kwh": round(self.storage.usable_kwh(), 1) if self.storage else 0.0,
            "storage_duration_h": round(self.storage.duration_h(), 2) if self.storage else 0.0,
        }

    def firm_capacity_kw(self) -> float:
        """Cap plus what storage can add while it lasts.

        This is the quantity Chase's site-acquisition thesis turns on: a 3-5 MW service
        plus a 3-5 MW battery presents as a larger site for the duration of a wave. It
        is explicitly duration-limited — `storage.duration_h()` says for how long — and
        the recharge afterwards counts toward the same monthly peak.
        """
        base = self.power_cap_kw()
        return base + (self.storage.total_power_kw() if self.storage else 0.0)


def load_site(doc: dict[str, Any]) -> SiteProfile:
    for required in ("site_id", "name", "grid", "tariff"):
        if required not in doc:
            raise SiteProfileError(f"site profile missing required key {required!r}")

    g = doc["grid"]
    if "service_capacity_kw" not in g:
        raise SiteProfileError(
            f"{doc['site_id']}: grid.service_capacity_kw is required. R-4: the binding "
            f"limit is the utility service/transformer, not the panel — a site without "
            f"one has no cap to schedule against."
        )
    grid = GridConnection(
        service_capacity_kw=float(g["service_capacity_kw"]),
        transformer_kw=(float(g["transformer_kw"]) if g.get("transformer_kw") else None),
        switchgear_kw=(float(g["switchgear_kw"]) if g.get("switchgear_kw") else None),
        voltage_class=g.get("voltage_class", "primary"),
        safety_margin_pct=float(g.get("safety_margin_pct", 0.0)),
        upgrade_lead_time_months=(tuple(g["upgrade_lead_time_months"])
                                  if g.get("upgrade_lead_time_months") else None),
        upgrade_cost_usd=(tuple(g["upgrade_cost_usd"])
                          if g.get("upgrade_cost_usd") else None),
    )

    try:
        tariff = load_tariff(doc["tariff"])
    except TariffError as exc:
        raise SiteProfileError(f"{doc['site_id']}: {exc}") from exc

    s = doc.get("storage")
    storage = Storage(
        power_kw=float(s["power_kw"]), energy_kwh=float(s["energy_kwh"]),
        round_trip_efficiency=float(s.get("round_trip_efficiency", 0.96)),
        soc_min_pct=float(s.get("soc_min_pct", 10.0)),
        soc_max_pct=float(s.get("soc_max_pct", 95.0)),
        units=int(s.get("units", 1)),
        recharge_counts_toward_peak=bool(s.get("recharge_counts_toward_peak", True)),
    ) if s else None

    lay = doc.get("layout", {})
    env = doc.get("environment", {})
    rob = doc.get("robotics", {})
    return SiteProfile(
        site_id=doc["site_id"], name=doc["name"], grid=grid, tariff=tariff,
        storage=storage,
        layout=Layout(
            move_duration_min=float(lay.get("move_duration_min", 4.0)),
            path_capacity=int(lay.get("path_capacity", 2)),
            dcfc_cooldown_min=float(lay.get("dcfc_cooldown_min", 18.0)),
        ),
        environment=Environment(
            cold_start_below_c=(float(env["cold_start_below_c"])
                                if env.get("cold_start_below_c") is not None else None),
            cold_start_penalty_min=float(env.get("cold_start_penalty_min", 0.0)),
            ambient_profile=env.get("ambient_profile"),
        ),
        robotics=Robotics(
            arms=int(rob.get("arms", 0)),
            mate_min=float(rob.get("mate_min", 0.0)),
            demate_min=float(rob.get("demate_min", 0.0)),
            tether_release_supported=bool(rob.get("tether_release_supported", True)),
        ),
        installed_charger_kw=float(doc.get("installed_charger_kw", 0.0)),
        timezone=doc.get("timezone", "UTC"),
        notes=doc.get("notes", ""),
    )


def load_site_file(path: Path) -> SiteProfile:
    return load_site(json.loads(Path(path).read_text()))


def available() -> list[str]:
    return sorted(p.stem for p in PROFILE_DIR.glob("*.json"))


def get(site_id: str) -> SiteProfile:
    path = PROFILE_DIR / f"{site_id}.json"
    if not path.exists():
        raise SiteProfileError(f"no site profile {site_id!r}; have {available()}")
    return load_site_file(path)
