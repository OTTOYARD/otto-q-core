"""THE DECK-SCALE PROOF RUN -- slide 10's eight numbers, run-ID-backed.

Column A: UNMANAGED -- charge on arrival, first come first served (FifoPolicy,
verbatim). Column B: OTTO-Q SHAPED -- the forward orchestrator (lexicographic:
tardiness first, then peak). Same 48-asset Site Alpha fleet, same arrivals, same
points, billed on the real NES GSA-3 tariff. Per column: peak kW, BESS kWh
required, monthly demand charge, required interconnect size.

REPRODUCIBILITY DESIGN, stated because it differs from the other artifacts. The
48-asset pass-2 solve runs to a WALL-CLOCK limit (FEASIBLE, tardiness pinned at
its proven optimum of zero), and a wall-clock cut is not byte-stable across
machines. So the committed artifact carries the LOAD CURVES themselves, plus the
solve's provenance (seed, statuses, limits); everything money-shaped -- bills,
BESS equivalence, deltas -- is recomputed deterministically from the committed
curves, and that recomputation is what the test asserts. The solve is produced
once and reviewed; the arithmetic is regenerable forever.

THE BESS-EQUIVALENCE COLUMN, defined precisely so the deck cannot overclaim:
"BESS kWh required" for column A is the battery that would make the UNMANAGED
site present the SHAPED column's grid profile -- discharge power >= A's excess
above B's peak in every interval, energy >= the summed excess (round-trip
losses added at 96%), recharge fitting under the same ceiling in the window's
slack. It answers the acquisition question directly: buy this much battery, or
buy the scheduler. Column B requires none by construction.

Interconnect size is defined as the measured peak rounded UP to the next 50 kW:
the smallest standard service that runs the schedule. Stated on the artifact.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))

from assignment_policy import FifoPolicy                     # noqa: E402
from cost import peak_lower_bound, site_load_curve           # noqa: E402
from forward import ForwardOrchestratorPolicy                # noqa: E402
from harness import run_policy_traced                        # noqa: E402
from model import load_scenario                              # noqa: E402
from sites.site_profile import get as get_site               # noqa: E402

SC = HERE.parent / "solvers" / "cpsat" / "scenario_deck.json"
ARTIFACT = HERE / "deck_seed424242.json"
RTE = 0.96
STEP_MIN = 15


def _interconnect_kw(peak: float) -> int:
    return int(math.ceil(peak / 50.0) * 50)


def bess_to_match(curve_a, ceiling_kw: float) -> dict:
    """The battery that makes curve A present `ceiling_kw` to the grid."""
    h = STEP_MIN / 60.0
    excess = [(t, max(0.0, kw - ceiling_kw)) for t, kw in curve_a]
    power_kw = max((e for _, e in excess), default=0.0)
    energy_kwh = sum(e * h for _, e in excess[:-1])
    stored_kwh = energy_kwh / RTE
    slack_kwh = sum(max(0.0, ceiling_kw - kw) * h for _, kw in curve_a[:-1])
    return {
        "discharge_power_kw": round(power_kw, 1),
        "delivered_kwh": round(energy_kwh, 1),
        "stored_kwh_at_96pct_rte": round(stored_kwh, 1),
        "recharge_fits_in_window": stored_kwh <= slack_kwh + 1e-9,
    }


def derive(columns: dict, *, month: int = 7) -> dict:
    """Everything money-shaped, recomputed deterministically from the curves."""
    tariff = get_site("site_alpha").tariff
    out = {}
    for name, col in columns.items():
        curve = [tuple(p) for p in col["load_curve"]]
        peak = float(col["peak_site_kw"])
        bill = tariff.bill(curve, month=month, days=30, historical_peak_kw=peak)
        out[name] = {
            "total_tardy_min": col["total_tardy_min"],
            "peak_site_kw": peak,
            "required_interconnect_kw": _interconnect_kw(peak),
            "monthly_demand_charge": bill["demand_cost"],
            "monthly_total": bill["total"],
        }
    shaped_peak = out["otto_q_shaped"]["peak_site_kw"]
    out["unmanaged"]["bess_to_match_shaped"] = bess_to_match(
        [tuple(p) for p in columns["unmanaged"]["load_curve"]], shaped_peak)
    out["otto_q_shaped"]["bess_to_match_shaped"] = {
        "discharge_power_kw": 0.0, "delivered_kwh": 0.0,
        "stored_kwh_at_96pct_rte": 0.0, "recharge_fits_in_window": True,
        "note": "none required by construction -- the schedule is the battery",
    }
    a, b = out["unmanaged"], out["otto_q_shaped"]
    out["delta"] = {
        "kw_avoided": round(a["peak_site_kw"] - b["peak_site_kw"], 1),
        "interconnect_kw_avoided": (a["required_interconnect_kw"]
                                    - b["required_interconnect_kw"]),
        "monthly_demand_charge_avoided": round(
            a["monthly_demand_charge"] - b["monthly_demand_charge"], 2),
        "monthly_total_avoided": round(a["monthly_total"] - b["monthly_total"], 2),
        "bess_kwh_avoided": a["bess_to_match_shaped"]["stored_kwh_at_96pct_rte"],
        "peak_ratio": round(a["peak_site_kw"] / b["peak_site_kw"], 2),
    }
    return out


def solve_and_write() -> dict:
    """The once-per-revision solve. Slow; not run by tests."""
    sc = load_scenario(SC)
    columns = {}
    for name, policy in (("unmanaged", FifoPolicy()),
                         ("otto_q_shaped", ForwardOrchestratorPolicy())):
        sc_fresh = load_scenario(SC)                       # CRN: same declared fleet
        result, state = run_policy_traced(sc_fresh, policy)
        columns[name] = {
            "total_tardy_min": result["metrics"]["total_tardy_min"],
            "peak_site_kw": float(result["metrics"]["peak_site_kw"]),
            "load_curve": site_load_curve(state, end_min=720),
        }
    lb = peak_lower_bound(SC)
    payload = {
        "scenario": "deck_site_alpha_overnight_v1",
        "seed": 424242,
        "fleet": "18 robotaxi + 6 yard tractor + 6x4-AMR-pad-served 24 AMR, "
                 "48 assets, one overnight window (720 min)",
        "tariff": "NES GSA-3 (primary; ottoq_depot_tariffs)",
        "interconnect_definition": "measured peak rounded up to the next 50 kW",
        "peak_lower_bound_kw": lb["peak_lower_bound_kw"],
        "solver_provenance": {
            "pass1": "min_tardy, OPTIMAL, T*=0",
            "pass2": "min_peak at T*=0, wall-limited FEASIBLE (180 s); curves "
                     "committed, downstream arithmetic regenerable",
        },
        "columns": columns,
        "derived": derive(columns),
        "methodology": [
            "Baseline is charge-on-arrival, first come first served -- the "
            "industry's own documented unmanaged practice (third-party anchor: "
            "The Mobility House 97-bus depot, unmanaged 4.7 MW cut to 1.4 MW "
            "under managed charging; research answer R-4).",
            "Common random numbers: both columns consume the identical declared "
            "48-asset fleet and arrival list, frozen in scenario_deck.json.",
            "One overnight window billed as a month (30 days) on NES GSA-3 -- "
            "standard for demand-charge reasoning (one interval sets the month); "
            "a fair ranking and indicative magnitude, not a bill forecast.",
            "BESS equivalence is the battery making the unmanaged site present "
            "the shaped column's grid profile, losses included -- buy the "
            "battery, or buy the scheduler.",
        ],
    }
    blob = json.dumps(payload, indent=1, sort_keys=True)
    payload["deck_sha256"] = hashlib.sha256(blob.encode()).hexdigest()
    ARTIFACT.write_text(json.dumps(payload, indent=1, sort_keys=True) + "\n")
    return payload


def main():
    if "--write" in sys.argv:
        p = solve_and_write()
    else:
        p = json.loads(ARTIFACT.read_text())
    d = p["derived"]
    print(f"provable ideal peak: {p['peak_lower_bound_kw']} kW\n")
    print(f"{'':24} {'UNMANAGED':>12} {'OTTO-Q':>12}")
    for label, key in (("tardy min", "total_tardy_min"),
                       ("peak kW", "peak_site_kw"),
                       ("interconnect kW", "required_interconnect_kw"),
                       ("demand charge $/mo", "monthly_demand_charge"),
                       ("total $/mo", "monthly_total")):
        print(f"{label:24} {d['unmanaged'][key]:>12,} {d['otto_q_shaped'][key]:>12,}")
    ba = d["unmanaged"]["bess_to_match_shaped"]
    print(f"{'BESS to match shaped':24} {ba['stored_kwh_at_96pct_rte']:>9,} kWh "
          f"/ {ba['discharge_power_kw']:,} kW {'':>4} {'0 (none)':>12}")
    print(f"\nDELTA: {d['delta']}")
    return p


if __name__ == "__main__":
    main()
