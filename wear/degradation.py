"""The derived wear layer — battery degradation from exposure we already capture. KERNEL.

WHAT THIS IS AND IS NOT. Exposure capture already works: a 20-tick run produced 61
OCPP sessions and 187 ServiceDetailRecords carrying soc_start, soc_end,
energy_delivered_kwh, peak_power_kw and ambient_temp_c. The gap was never capture, it
was the DERIVED layer that turns those columns into a number a scheduler can optimise.
This is that layer.

Nothing here is calibrated on simulation output. The coefficients are literature
(research answer R-3); the exposure is whatever SDRs it is handed. Point it at a real
depot's SDRs and it works identically -- which is the whole requirement: the
intelligence layer must never learn the simulator's habits.

THE MODEL, from R-3's request:

    calendar = k_cal * exp(-Ea / (R * T_pack)) * f_soc(SoC_parked) * sqrt(t_hours)
    cycle    = k_cyc * Ah_throughput * g_rate(C_rate) * h_temp(T_pack)

EVERY COEFFICIENT CARRIES ITS PROVENANCE, and the model reports which of its outputs
rest on inference rather than measurement. This is the same discipline as the pack
mechanism registry: a number whose source cannot be checked is a number that will
eventually be quoted as fact. `Coefficient.provenance` is one of:

    primary     -- peer-reviewed experiment or model
    review      -- peer-reviewed survey
    inference   -- R-3's synthesis across sources, explicitly flagged there
    not_found   -- no defensible value exists; the model refuses rather than guessing

THE TWO LEVERS. R-3's headline for us: the cold charge (lithium plating) and the
high-SoC park (calendar fade) are the two things a DEPOT SCHEDULER can actually pull.
Discharge rate barely matters and we do not control it anyway; ambient temperature we
do not control either. What we control is WHEN a vehicle charges (so, how cold it is)
and WHAT SoC it sits at between shifts. Both have peer-reviewed effect sizes. This
module therefore optimises exactly two things and says so, rather than presenting a
general-purpose battery model we cannot support.

WHY THE PLATING GATE IS A STEP AND NOT A CURVE. R-3 is explicit: a clean charge-side
normalised g_rate table is NOT FOUND in any single source, and the physically correct,
scheduler-actionable behaviour is to GATE the cold-fast-charge regime rather than
apply a smooth multiplier. So `plating_risk()` returns a regime, not a coefficient,
and the penalty is applied as a documented step. Inventing a smooth curve here would
be inventing the exact number R-3 says does not exist.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

R_GAS = 8.314                 # J/(mol K)
T_REF_K = 298.15              # 25 C -- the temperature R-3's Arrhenius fits normalise to

PROVENANCE = ("primary", "review", "inference", "not_found")


@dataclass(frozen=True)
class Coefficient:
    """A number with its source. A coefficient without provenance is not usable here."""

    value: float | None
    units: str
    provenance: str
    source: str

    def __post_init__(self) -> None:
        if self.provenance not in PROVENANCE:
            raise ValueError(f"provenance must be one of {PROVENANCE}")

    def require(self, what: str) -> float:
        if self.provenance == "not_found" or self.value is None:
            raise NotFoundError(
                f"{what}: no defensible value exists ({self.source}). The model refuses "
                f"rather than inventing one."
            )
        return self.value


class NotFoundError(ValueError):
    """Raised where R-3 records NOT FOUND. Refusing is the correct behaviour."""


@dataclass(frozen=True)
class Chemistry:
    """Per-chemistry coefficients, each traceable to R-3."""

    name: str
    activation_energy: Coefficient          # Ea, J/mol
    #: SoC above which calendar fade steps up -- the half-lithiated graphite transition.
    soc_step_pct: float
    #: f_soc multipliers, normalised to 50% SoC = 1.0.
    f_soc_table: tuple[tuple[float, float], ...]
    #: Temperature below which charging at >= ~0.5C risks lithium plating.
    plating_temp_c: float
    #: Observed worst-case capacity loss attributable to cold charging.
    cold_loss_fraction: Coefficient


_KEIL = "Keil et al. 2016, J. Electrochem. Soc. 163(9) A1872, doi:10.1149/2.0411609jes"
_ECKER = "Ecker et al. 2012, J. Power Sources 215, 248-257, doi:10.1016/j.jpowsour.2012.05.012"
_SCHIMPE = "Schimpe et al. 2018, J. Electrochem. Soc. 165(2) A181, doi:10.1149/2.0161802jes"
_YARIMCA = "Yarimca et al. 2024, Batteries 10(11):374, doi:10.3390/batteries10110374"
_PREGER = "Preger et al. 2020, J. Electrochem. Soc. 167(12) 120532, doi:10.1149/1945-7111/abae37"
_WALDMANN = "Waldmann et al. 2014, J. Power Sources 262, 129-135, doi:10.1016/j.jpowsour.2014.03.112"

#: R-3 Q2 is explicit that the SHAPE (plateau -> step -> 100% rise) is primary literature
#: but the NUMERIC multipliers are its own synthesis: "no single source tabulates a clean
#: normalised multiplier series ... treat these as order-of-magnitude placeholders and
#: calibrate against your cell." They are carried as `inference` and every result computed
#: from them is flagged. R-3 gives ranges; the midpoint is taken and the range preserved.
NMC = Chemistry(
    name="NMC",
    activation_energy=Coefficient(90_700.0, "J/mol", "primary", _ECKER),
    soc_step_pct=60.0,
    f_soc_table=((30, 1.0), (50, 1.0), (70, 1.75), (80, 1.75), (90, 2.0), (100, 4.0)),
    plating_temp_c=10.0,
    cold_loss_fraction=Coefficient(0.35, "fraction of capacity", "review", _YARIMCA),
)

LFP = Chemistry(
    name="LFP",
    activation_energy=Coefficient(62_000.0, "J/mol", "primary", _SCHIMPE),
    soc_step_pct=70.0,
    f_soc_table=((30, 1.0), (50, 1.0), (70, 1.25), (80, 1.5), (90, 1.75), (100, 2.0)),
    #: R-3: LFP shows a "tipping point" at 5-10 C -- below it cold/plating dominates.
    plating_temp_c=7.5,
    cold_loss_fraction=Coefficient(0.35, "fraction of capacity", "review", _YARIMCA),
)

CHEMISTRIES = {"NMC": NMC, "LFP": LFP}

#: Discharge-side rate dependence. R-3 Q4: "discharge rate dependence for NMC and LFP
#: cells appears low" -- so 1.0, and that is a measured near-null, not a placeholder.
G_RATE_DISCHARGE = Coefficient(1.0, "multiplier", "primary", _PREGER)

#: Charge-side smooth multiplier. R-3 Q4 records this as NOT FOUND and recommends gating
#: the cold regime instead. Requesting it raises.
G_RATE_CHARGE = Coefficient(
    None, "multiplier", "not_found",
    "R-3 Q4: no clean charge-only normalised table in any single source; "
    "R-3 recommends a plating gate instead of a smooth multiplier",
)

#: Normalised h_temp across -10..50 C. R-3 Q5: the U-shape with a ~25 C minimum is primary
#: (Waldmann 2014) but "exact normalised multipliers are not tabulated cleanly across
#: -10->50 C in a single citable table -- NOT FOUND as such".
H_TEMP_TABLE = Coefficient(
    None, "multiplier", "not_found",
    f"R-3 Q5: U-shape and 25 C minimum are primary ({_WALDMANN}); a normalised "
    f"multiplier table across the range is NOT FOUND",
)


def f_soc(chem: Chemistry, soc_pct: float) -> float:
    """Calendar-fade multiplier for parked SoC, normalised to 50% = 1.0.

    Linear interpolation between R-3's tabulated points, clamped at the ends. The table
    is INFERENCE (see NMC/LFP above); anything computed from it is flagged.
    """
    tbl = chem.f_soc_table
    if soc_pct <= tbl[0][0]:
        return tbl[0][1]
    if soc_pct >= tbl[-1][0]:
        return tbl[-1][1]
    for (x0, y0), (x1, y1) in zip(tbl, tbl[1:]):
        if x0 <= soc_pct <= x1:
            if x1 == x0:
                return y0
            return y0 + (y1 - y0) * (soc_pct - x0) / (x1 - x0)
    return tbl[-1][1]


def arrhenius(chem: Chemistry, temp_c: float) -> float:
    """exp(-Ea/RT) normalised to 25 C, so 25 C returns 1.0."""
    ea = chem.activation_energy.require(f"{chem.name} activation energy")
    t_k = temp_c + 273.15
    if t_k <= 0:
        raise ValueError(f"temperature {temp_c} C is below absolute zero")
    return math.exp(-ea / (R_GAS * t_k)) / math.exp(-ea / (R_GAS * T_REF_K))


def calendar_fade(chem: Chemistry, *, soc_pct: float, temp_c: float,
                  hours: float, k_cal: float = 1.0, time_exponent: float = 0.5) -> float:
    """Relative calendar fade over `hours` parked at `soc_pct` and `temp_c`.

    Returned in units of `k_cal`, i.e. relative unless the caller supplies a calibrated
    k_cal for its own cell. R-3 Q3 confirms sqrt(t) (exponent 0.5) is the SEI-limited
    form and the right default for a 12-month horizon, while noting the two most-cited
    empirical fits use 0.75 -- hence the parameter rather than a hard-coded 0.5.
    """
    if hours < 0:
        raise ValueError("hours must be non-negative")
    return (k_cal * arrhenius(chem, temp_c) * f_soc(chem, soc_pct)
            * (hours ** time_exponent))


def plating_risk(chem: Chemistry, *, temp_c: float, c_rate: float) -> str:
    """Regime, not a coefficient. R-3 Q4/Q5 say gate this; do not curve-fit it.

    Returns 'severe' below 0 C at any meaningful rate, 'elevated' in the cold band at
    >= 0.5C, and 'none' otherwise. R-3: "charging at >= ~0.5C below ~0-10 C risks
    plating; below 0 C even moderate rates do."
    """
    if c_rate <= 0:
        return "none"
    if temp_c < 0.0 and c_rate >= 0.2:
        return "severe"
    if temp_c < chem.plating_temp_c and c_rate >= 0.5:
        return "elevated"
    return "none"


@dataclass
class ExposureRecord:
    """One completed charge event, as an SDR already carries it."""

    asset_id: str
    chemistry: str
    battery_kwh: float
    soc_start_pct: float
    soc_end_pct: float
    energy_delivered_kwh: float
    peak_power_kw: float
    ambient_temp_c: float
    duration_h: float

    def c_rate(self) -> float:
        return self.peak_power_kw / self.battery_kwh if self.battery_kwh else 0.0

    def ah_throughput_frac(self) -> float:
        """Throughput as a fraction of one full equivalent cycle."""
        return self.energy_delivered_kwh / self.battery_kwh if self.battery_kwh else 0.0


@dataclass
class WearAssessment:
    asset_id: str
    equivalent_full_cycles: float
    calendar_fade_rel: float
    plating_events: int
    severe_plating_events: int
    #: Outputs resting on R-3's inferred f_soc table rather than measured values.
    inference_flags: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def as_row(self) -> dict[str, Any]:
        return {
            "asset_id": self.asset_id,
            "equivalent_full_cycles": round(self.equivalent_full_cycles, 3),
            "calendar_fade_rel": round(self.calendar_fade_rel, 4),
            "plating_events": self.plating_events,
            "severe_plating_events": self.severe_plating_events,
            "rests_on_inference": bool(self.inference_flags),
        }


def assess(records: list[ExposureRecord], *, parked_hours: float = 0.0,
           parked_soc_pct: float | None = None,
           parked_temp_c: float = 25.0) -> list[WearAssessment]:
    """Derive wear per asset from captured exposure.

    `parked_*` describe the idle period between shifts -- the high-SoC park that is one
    of our two levers. When `parked_soc_pct` is None the final observed SoC is used,
    which is the honest default: it is what the asset actually sat at.
    """
    by_asset: dict[str, list[ExposureRecord]] = {}
    for r in records:
        by_asset.setdefault(r.asset_id, []).append(r)

    out: list[WearAssessment] = []
    for asset_id, rs in sorted(by_asset.items()):
        chem_name = rs[0].chemistry.upper()
        if chem_name not in CHEMISTRIES:
            raise ValueError(
                f"{asset_id}: chemistry {rs[0].chemistry!r} has no R-3 coefficients; "
                f"have {sorted(CHEMISTRIES)}"
            )
        chem = CHEMISTRIES[chem_name]

        efc = sum(r.ah_throughput_frac() for r in rs)
        plating = [plating_risk(chem, temp_c=r.ambient_temp_c, c_rate=r.c_rate())
                   for r in rs]
        soc = parked_soc_pct if parked_soc_pct is not None else rs[-1].soc_end_pct
        cal = calendar_fade(chem, soc_pct=soc, temp_c=parked_temp_c,
                            hours=parked_hours) if parked_hours > 0 else 0.0

        a = WearAssessment(
            asset_id=asset_id,
            equivalent_full_cycles=efc,
            calendar_fade_rel=cal,
            plating_events=sum(1 for p in plating if p == "elevated"),
            severe_plating_events=sum(1 for p in plating if p == "severe"),
        )
        if parked_hours > 0:
            a.inference_flags.append(
                f"calendar_fade_rel uses the f_soc table, which R-3 Q2 labels INFERENCE "
                f"(shape is primary, {_KEIL}; multipliers are R-3's synthesis). Treat as "
                f"order-of-magnitude until calibrated against the actual cell."
            )
        if a.severe_plating_events or a.plating_events:
            a.notes.append(
                f"{a.severe_plating_events} severe + {a.plating_events} elevated plating "
                f"exposures. R-3: up to {chem.cold_loss_fraction.value:.0%} capacity loss "
                f"observed at -10/-20 C ({chem.cold_loss_fraction.source}). This is a "
                f"REGIME, not a smooth penalty -- moving these sessions warmer or slower "
                f"removes the exposure entirely."
            )
        out.append(a)
    return out


def soc_park_saving(chem: Chemistry, *, from_soc_pct: float, to_soc_pct: float) -> float:
    """How much calendar fade is avoided by parking lower. The second lever, quantified.

    R-3 Q2's scheduling consequence: "parking at 50% instead of 90-100% SoC cuts
    calendar fade by roughly 2-5x for NMC". This returns that ratio from the same table
    the model uses, so the claim and the model can never drift apart.

    Rests on the INFERENCE-tagged f_soc table -- the direction and rough magnitude are
    supported; the precise ratio is not a measured value.
    """
    hi, lo = f_soc(chem, from_soc_pct), f_soc(chem, to_soc_pct)
    return hi / lo if lo else float("inf")


def provenance_report() -> dict[str, Any]:
    """Everything the model rests on, and how well supported each piece is.

    Exists so the honest sentence about this layer can be generated rather than
    remembered. Anything tagged `not_found` is something the model refuses to compute.
    """
    rows = [
        {"item": "NMC activation energy", "provenance": NMC.activation_energy.provenance,
         "value": NMC.activation_energy.value, "source": NMC.activation_energy.source},
        {"item": "LFP activation energy", "provenance": LFP.activation_energy.provenance,
         "value": LFP.activation_energy.value, "source": LFP.activation_energy.source},
        {"item": "f_soc multipliers", "provenance": "inference", "value": None,
         "source": f"shape primary ({_KEIL}); multipliers are R-3 Q2's synthesis"},
        {"item": "sqrt(t) time exponent", "provenance": "primary", "value": 0.5,
         "source": f"{_KEIL}; R-3 Q3 notes empirical fits use 0.75 beyond ~1 yr"},
        {"item": "discharge g_rate", "provenance": G_RATE_DISCHARGE.provenance,
         "value": G_RATE_DISCHARGE.value, "source": G_RATE_DISCHARGE.source},
        {"item": "charge g_rate (smooth)", "provenance": G_RATE_CHARGE.provenance,
         "value": None, "source": G_RATE_CHARGE.source},
        {"item": "h_temp table", "provenance": H_TEMP_TABLE.provenance, "value": None,
         "source": H_TEMP_TABLE.source},
        {"item": "cold-charge capacity loss", "provenance": NMC.cold_loss_fraction.provenance,
         "value": NMC.cold_loss_fraction.value, "source": NMC.cold_loss_fraction.source},
    ]
    return {
        "coefficients": rows,
        "refuses_to_compute": [r["item"] for r in rows if r["provenance"] == "not_found"],
        "rests_on_inference": [r["item"] for r in rows if r["provenance"] == "inference"],
        "levers": [
            "cold charging -- gated as a regime (plating_risk), never curve-fitted",
            "parked SoC -- quantified by soc_park_saving, on the inferred f_soc table",
        ],
    }
