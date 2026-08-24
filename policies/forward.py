"""The forward orchestrator — deadlines are hard constraints, dollars are the objective.

THE FORMULATION, which is the product decision this module encodes. The cost axis
(policies/cost.py) measured that no single metric crowns a winner: greedy wins
tardiness by ignoring cost, FIFO wins cost by accident (it serializes, so it never
stacks load), and each policy leaves 2.0-2.4x the provable ideal bill on the table.
The answer is not a weighted soup of the two axes -- a weight is a price on lateness
nobody actually agreed to. It is LEXICOGRAPHIC:

    pass 1: minimize total tardiness.            -> T*, the best service physics allows
    pass 2: hold tardiness at T*, minimize the   -> the flattest load curve that
            site's instantaneous peak kW.           still delivers that service

Serve every asset as well as the best policy can, and only then spend every remaining
degree of freedom on flattening the bill. No naive policy can do both, because doing
both REQUIRES forward knowledge: load can only be spread flat by a scheduler that
already knows tonight's total demand.

WHY INSTANTANEOUS PEAK IS THE PASS-2 OBJECTIVE and not the billed interval average:
the instantaneous peak upper-bounds the average over ANY demand interval, so
minimizing it can only over-serve the bill, never cheat it. The bill reported
downstream is always computed from the actual curve by the real tariff
(sites/tariff.py), never from the proxy. See build_and_solve(objective_mode=...).

STORAGE, AND WHY FORESIGHT MAKES IT UNFAIR. A demand charge bills the worst metering
interval of the month. A reactive controller discovers the peak in the interval AFTER
it was billed; a forward scheduler knows the peak before it happens, because it is the
one scheduling it -- so it can aim the battery's discharge at exactly the intervals
that will otherwise set the bill. dispatch_storage() is that aim: it takes the
day-ahead curve (which only a forward scheduler possesses), finds the lowest grid
ceiling the battery can hold, and schedules the recharge where it will not create a
new peak -- because recharge draws from the same meter and counts toward the same
monthly maximum (the trap ONBOARDING.md documents).

This policy is DELIBERATELY NOT in ALL_POLICIES: comparison_seed424242.json is a
frozen, byte-asserted artifact and adding a fifth run would silently regenerate it.
The forward comparison is its own artifact, forward_seed424242.json.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))

from assignment_policy import ALL_POLICIES, Assignment, AssignmentPolicy  # noqa: E402
from cost import peak_lower_bound, site_load_curve                        # noqa: E402
from harness import run_policy_traced                                     # noqa: E402
from model import build_and_solve, load_scenario                          # noqa: E402
from sites.site_profile import Storage, get as get_site                   # noqa: E402


class ForwardOrchestratorPolicy(AssignmentPolicy):
    """Lexicographic: best achievable service first, flattest load second."""

    name = "forward"

    def decide(self, state, arrivals):
        pass1 = build_and_solve(state.sc, objective_mode="min_tardy")
        t_star = sum(a["tardy_min"] for a in pass1["assets"])
        pass2 = build_and_solve(state.sc, objective_mode="min_peak",
                                max_tardy_total=t_star, previous_plan=pass1)
        starts = {}
        for a in pass2["assets"]:
            for op in a["ops"]:
                if op["op"] == "charge":
                    starts[a["aid"]] = (op["point"], op["start"])
        out = []
        for asset in sorted(arrivals, key=lambda a: (starts[a.aid][1], a.aid)):
            point_id, start = starts[asset.aid]
            state.book_charge(asset, state.point(point_id), start)
            out.append(Assignment(asset.aid, point_id, start))
        return out


# ---- forward storage dispatch ----------------------------------------------------

def dispatch_storage(curve: list[tuple[float, float]], storage: Storage,
                     *, step_min: int = 15) -> dict:
    """Hold the grid under the lowest ceiling the battery can sustain for this curve.

    Binary search on the grid ceiling G. For a candidate G the battery must supply
    everything above G (bounded by its power in every step and by its usable energy
    over the day, inflated by round-trip losses), and the recharge -- spread over the
    below-ceiling steps -- must itself fit under G, because recharge draws from the
    same meter. The dispatch is feasible iff all three hold; the search returns the
    smallest feasible G to 0.1 kW.

    Requires the ENTIRE day-ahead curve, which is precisely why it belongs to the
    forward scheduler and not to a reactive controller: by the time a reactive system
    has observed the peak, the meter has already billed it.
    """
    if not curve:
        return {"grid_peak_kw": 0.0, "discharge": [], "recharge_kw": 0.0,
                "supported": True, "note": "empty curve"}

    pts = sorted(curve)
    steps: list[tuple[float, float]] = []           # (t, kw) fixed-width resample
    end = pts[-1][0]
    t = 0.0
    while t < end:
        load = 0.0
        for i, (tt, kw) in enumerate(pts):
            nxt = pts[i + 1][0] if i + 1 < len(pts) else end
            if tt <= t < nxt:
                load = kw
                break
        steps.append((t, load))
        t += step_min
    hours_per_step = step_min / 60.0

    p_max = storage.total_power_kw()
    e_usable = storage.usable_kwh()
    rte = storage.round_trip_efficiency

    def feasible(g: float) -> bool:
        deficit_kwh = 0.0
        for _, kw in steps:
            over = kw - g
            if over > p_max + 1e-9:
                return False                         # battery cannot bridge this step
            if over > 0:
                deficit_kwh += over * hours_per_step
        if deficit_kwh > e_usable + 1e-9:
            return False
        recharge_kwh = deficit_kwh / rte             # losses are paid at the meter
        slack_kwh = sum(max(0.0, g - kw) * hours_per_step for _, kw in steps)
        return recharge_kwh <= slack_kwh + 1e-9

    lo = max(0.0, max(kw for _, kw in steps) - p_max)
    hi = max(kw for _, kw in steps)
    if not feasible(hi):
        return {"grid_peak_kw": hi, "discharge": [], "recharge_kw": 0.0,
                "supported": False,
                "note": "storage cannot recharge within this curve's slack"}
    for _ in range(64):
        mid = (lo + hi) / 2
        if feasible(mid):
            hi = mid
        else:
            lo = mid
        if hi - lo < 0.1:
            break
    g = round(hi, 1)

    discharge = [(t, round(max(0.0, kw - g), 1)) for t, kw in steps if kw > g]
    deficit_kwh = sum(d * hours_per_step for _, d in discharge)
    recharge_kwh = deficit_kwh / rte
    slack_steps = [(t, kw) for t, kw in steps if kw < g]
    grid_curve = []
    #: Recharge fills the below-ceiling steps evenly up to (never past) the ceiling.
    per_step_room = [(t, g - kw) for t, kw in slack_steps]
    total_room = sum(r for _, r in per_step_room) * hours_per_step
    fill = recharge_kwh / total_room if total_room > 0 else 0.0
    room = dict(per_step_room)
    for t, kw in steps:
        if kw > g:
            grid_curve.append((t, g))
        else:
            grid_curve.append((t, round(kw + room.get(t, 0.0) * fill, 2)))
    grid_curve.append((float(end), grid_curve[-1][1] if grid_curve else 0.0))

    return {
        "grid_peak_kw": g,
        "discharge": discharge,
        "deficit_kwh": round(deficit_kwh, 1),
        "recharge_kwh": round(recharge_kwh, 1),
        "grid_curve": grid_curve,
        "supported": True,
        "note": (f"grid held at {g} kW; battery supplies {deficit_kwh:.0f} kWh, "
                 f"recharges {recharge_kwh:.0f} kWh inside the same ceiling"),
    }


# ---- the comparison artifact -----------------------------------------------------

def forward_comparison(scenario_path, *, site_id: str = "site_alpha",
                       storage_site_id: str = "nashville_nes_gsa3_bess",
                       month: int = 7, curve_end_min: int = 1440,
                       scenario_label: str = "reduced_canonical_nash_v1") -> dict:
    """All five policies billed, plus the forward policy with storage aimed by foresight.

    `curve_end_min` must cover the scenario's horizon -- the 24h scenario runs 1,800
    minutes and truncating its curve at a day would silently drop the tail's charges.
    """
    site = get_site(site_id)
    storage_site = get_site(storage_site_id)
    rows: dict[str, dict] = {}
    forward_curve = None

    for cls in list(ALL_POLICIES) + [ForwardOrchestratorPolicy]:
        sc = load_scenario(scenario_path)            # CRN: same draw for every policy
        policy = cls()
        result, state = run_policy_traced(sc, policy)
        curve = site_load_curve(state, end_min=curve_end_min)
        peak = float(result["metrics"]["peak_site_kw"])
        bill = site.tariff.bill(curve, month=month, days=30, historical_peak_kw=peak)
        rows[policy.name] = {
            "total_tardy_min": result["metrics"]["total_tardy_min"],
            "peak_site_kw": peak,
            "monthly_total": bill["total"],
            "annual_total": round(bill["total"] * 12, 2),
        }
        if policy.name == "forward":
            forward_curve = curve

    base = rows["fifo"]["monthly_total"]
    for r in rows.values():
        r["monthly_delta_vs_fifo"] = round(r["monthly_total"] - base, 2)

    dispatch = dispatch_storage(forward_curve, storage_site.storage)
    stor_bill = storage_site.tariff.bill(
        dispatch["grid_curve"], month=month, days=30,
        historical_peak_kw=dispatch["grid_peak_kw"],
    ) if dispatch["supported"] else None

    lb = peak_lower_bound(scenario_path)
    payload = {
        "scenario": scenario_label,
        "seed": 424242,
        "month": month,
        "site_id": site_id,
        "policies": {k: rows[k] for k in sorted(rows)},
        "peak_lower_bound_kw": lb["peak_lower_bound_kw"],
        "forward_with_storage": {
            "storage_site_id": storage_site_id,
            "supported": dispatch["supported"],
            "grid_peak_kw": dispatch.get("grid_peak_kw"),
            "deficit_kwh": dispatch.get("deficit_kwh"),
            "recharge_kwh": dispatch.get("recharge_kwh"),
            "monthly_total": stor_bill["total"] if stor_bill else None,
            "note": dispatch["note"],
        },
        "formulation": (
            "Lexicographic: pass 1 minimizes total tardiness (T*); pass 2 holds "
            "tardiness at T* and minimizes the instantaneous site peak, an upper "
            "bound on every billed interval average. Storage dispatch then holds the "
            "grid at the lowest ceiling the battery can sustain, recharge included, "
            "using the day-ahead curve only a forward scheduler possesses."
        ),
        "assumptions": [
            "One reduced canonical day billed as a month -- a fair ranking and an "
            "indicative magnitude, not a bill forecast (see POLICY_COST_FINDING.md).",
            "The ratchet uses each policy's own peak as history; the scenario has no "
            "12-month billing history.",
            "The storage row bills the Nashville tariff with the site's committed "
            "Megapack fleet; the no-storage rows bill the same tariff without it, so "
            "the two are comparable like-for-like.",
        ],
    }
    blob = json.dumps(payload, indent=1, sort_keys=True)
    payload["forward_sha256"] = hashlib.sha256(blob.encode()).hexdigest()
    return payload


def forward_comparison_24h() -> dict:
    """The same formulation at scale: the 24h KPI-gate scenario, 16 assets, 30 hours.

    The reduced canonical day is a 12-asset toy; this is the scenario the CI KPI gate
    already guards. Same seed discipline, same tariff, same bound -- the question it
    answers is whether forward's edge survives a longer horizon with overlapping
    arrival waves, and the artifact makes the answer reproducible rather than told.
    """
    sc24 = HERE.parent / "solvers" / "cpsat" / "scenario_24h.json"
    import json as _json
    horizon = _json.loads(Path(sc24).read_text())["horizon_min"]
    return forward_comparison(sc24, curve_end_min=horizon,
                              scenario_label="canonical_24h_nash_v1")


def main() -> dict:
    if "--24h" in sys.argv:
        comp = forward_comparison_24h()
        artifact = HERE / "forward_24h_seed424242.json"
    else:
        sc = HERE.parent / "solvers" / "cpsat" / "scenario_canonical.json"
        comp = forward_comparison(sc)
        artifact = HERE / "forward_seed424242.json"
    blob = json.dumps(comp, indent=1, sort_keys=True) + "\n"
    if "--write" in sys.argv:
        artifact.write_text(blob)
        print(f"wrote {artifact.name}  sha256={comp['forward_sha256']}")
    elif artifact.exists():
        same = artifact.read_text() == blob
        print(f"regenerated sha256={comp['forward_sha256']} -> "
              f"{'MATCHES' if same else 'DIFFERS FROM'} committed artifact")

    print(f"\nprovable ideal peak: {comp['peak_lower_bound_kw']} kW\n")
    print(f"  {'policy':>12} {'tardy min':>10} {'peak kW':>8} {'month $':>9} {'vs fifo':>9}")
    for name, r in comp["policies"].items():
        print(f"  {name:>12} {r['total_tardy_min']:>10,} {r['peak_site_kw']:>8,.0f} "
              f"{r['monthly_total']:>9,.0f} {r['monthly_delta_vs_fifo']:>9,.0f}")
    fs = comp["forward_with_storage"]
    if fs["supported"]:
        print(f"\n  forward + storage ({fs['storage_site_id']}): grid held at "
              f"{fs['grid_peak_kw']} kW -> ${fs['monthly_total']:,.0f}/mo "
              f"(battery moves {fs['deficit_kwh']} kWh, recharges {fs['recharge_kwh']})")
    return comp


if __name__ == "__main__":
    main()
