"""The cost dimension of the four-policy comparison — what each schedule actually bills.

WHY THIS EXISTS. The committed comparison reports total_tardy_min, p95 wait, peak
site kW, point turns, moves and makespan. Not one of those is money. That is the gap
docs/BENCHMARK_CREDIBILITY.md names: the tariff never reaches the objective, so
"OTTO-Q wins on peak kW" was withdrawn as a claim about a quantity nobody is billed
for. Peak kW is not a bill. A tariff turns a load curve into a bill, and only then can
two policies be compared on the axis a depot operator actually cares about.

WHAT IT DOES NOT DO. It does not change the committed comparison. That artifact is
asserted byte-for-byte by test_policies.py and `run_policy`'s return shape is frozen;
this module uses `run_policy_traced`, bills the SAME run the metrics describe, and
emits its own artifact. Folding cost into the main comparison would be a deliberate
baseline regeneration, not a side effect of adding a feature.

WHAT THE NUMBERS MEAN, PRECISELY. The scenario is one reduced canonical day of 12
assets. Billing a month from one day assumes that day repeats -- which is the standard
way a demand charge is reasoned about (the monthly bill is set by ONE peak interval),
but it is an assumption and it is stated on every artifact this writes. A policy that
would produce its worst day once a month still pays for it all month; a policy whose
peak is genuinely lower every day pays less. The comparison is therefore a fair
RANKING and an indicative magnitude, not a forecast of a real bill.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from harness import run_policy_traced          # noqa: E402
from sites.site_profile import get as get_site  # noqa: E402
from solvers.cpsat.model import load_scenario   # noqa: E402  (path set above)

DAY_MIN = 1440
STEP_MIN = 15


def site_load_curve(state, *, step_min: int = STEP_MIN,
                    end_min: int = DAY_MIN) -> list[tuple[float, float]]:
    """Reconstruct the site's kW draw from the run's charge segments.

    Sampled at `step_min` so the curve can be billed at any demand interval; the
    tariff engine averages within its own interval, so sampling finer than the meter
    is correct and sampling coarser would silently flatten peaks.

    `end_min` must cover the scenario's horizon. The default (one day) matches the
    canonical scenario and the committed cost artifact; the 24h scenario runs a
    1,800-minute horizon, and truncating it at 1,440 would silently drop every
    charge in the tail -- an understated bill that no test would flag as wrong,
    which is exactly the kind of quiet error this file exists to prevent.
    """
    events: list[tuple[float, float]] = []
    for segs in state.segments.values():
        for s in segs:
            events.append((float(s["start"]), float(s["kw"])))
            events.append((float(s["end"]), -float(s["kw"])))
    events.sort()

    curve: list[tuple[float, float]] = []
    for m in range(0, end_min, step_min):
        load = sum(d for t, d in events if t <= m)
        curve.append((float(m), max(0.0, load)))
    curve.append((float(end_min), 0.0))
    return curve


def _pareto(tardy: dict[str, int], cost: dict[str, float]) -> list[str]:
    """Policies not beaten on BOTH axes by some other policy (lower is better on each).

    A policy that is worse on tardiness AND more expensive is dominated: there is no
    weighting of the two objectives under which you would choose it. Naming the
    dominated set is the point -- a single-axis comparison can never produce it, and it
    is the difference between "this policy is behind" and "this policy is not on the
    frontier at all".
    """
    names = sorted(tardy)
    keep = []
    for a in names:
        dominated = any(
            b != a and tardy[b] <= tardy[a] and cost[b] <= cost[a]
            and (tardy[b] < tardy[a] or cost[b] < cost[a])
            for b in names
        )
        if not dominated:
            keep.append(a)
    return keep


def cost_comparison(scenario_path, *, site_ids: tuple[str, ...] = (
        "site_alpha", "atlanta_georgia_power", "phoenix_aps_e35"),
        month: int = 7) -> dict:
    """Bill every policy's schedule on every site, and pair the deltas against FIFO."""
    from assignment_policy import ALL_POLICIES

    curves: dict[str, list[tuple[float, float]]] = {}
    peaks: dict[str, float] = {}
    tardy: dict[str, int] = {}
    for cls in ALL_POLICIES:
        sc = load_scenario(scenario_path)      # same seed -> same draw (CRN preserved)
        policy = cls()
        result, state = run_policy_traced(sc, policy)
        curves[policy.name] = site_load_curve(state)
        peaks[policy.name] = float(result["metrics"]["peak_site_kw"])
        tardy[policy.name] = int(result["metrics"]["total_tardy_min"])

    out: dict[str, dict] = {}
    for site_id in site_ids:
        site = get_site(site_id)
        rows: dict[str, dict] = {}
        for name, curve in curves.items():
            #: The ratchet needs a billing history this scenario does not have. Using
            #: THIS policy's own peak as the history is the neutral choice: it neither
            #: rewards nor punishes a policy for a past it never ran, and it is stated
            #: on the artifact so nobody reads it as a modelled 12-month floor.
            bill = site.tariff.bill(curve, month=month, days=30,
                                    historical_peak_kw=peaks[name])
            rows[name] = {
                "billed_peaks_kw": bill["billed_peaks_kw"],
                "demand_cost": bill["demand_cost"],
                "energy_cost": bill["energy_cost"],
                "fixed_cost": bill["fixed_cost"],
                "monthly_total": bill["total"],
                "annual_total": round(bill["total"] * 12, 2),
                "measured_peak_kw": peaks[name],
            }
        base = rows.get("fifo", {}).get("monthly_total")
        for name, r in rows.items():
            r["monthly_delta_vs_fifo"] = (round(r["monthly_total"] - base, 2)
                                          if base is not None else None)
        out[site_id] = {
            "tariff": site.tariff.schedule_code,
            "utility": site.tariff.utility,
            "policies": rows,
        }

    #: The tradeoff the comparison could not previously see. Tardiness and demand cost
    #: pull in OPPOSITE directions: serving assets sooner means charging more of them
    #: at once, which raises the peak interval the demand charge bills. Until cost was
    #: computed there was only one axis, so "better" was unambiguous and wrong.
    frontier = _pareto(tardy, {n: out[site_ids[0]]["policies"][n]["monthly_total"]
                               for n in curves})

    payload = {
        "scenario": "reduced_canonical_nash_v1",
        "seed": 424242,
        "month": month,
        "sites": out,
        "tradeoff": {
            "reference_site": site_ids[0],
            "total_tardy_min": tardy,
            "monthly_total_usd": {n: out[site_ids[0]]["policies"][n]["monthly_total"]
                                  for n in sorted(curves)},
            "pareto_optimal": frontier,
            "dominated": sorted(set(curves) - set(frontier)),
        },
        "assumptions": [
            "One reduced canonical day of 12 assets, billed as though that day repeats "
            "for a month. Standard for reasoning about a demand charge (one interval "
            "sets the month) but an assumption, not a forecast of a real bill.",
            "The ratchet floor uses each policy's own peak as its billing history; the "
            "scenario has no 12-month history to draw on.",
            "Wash and inspect routing is identical FCFS for every policy, so this "
            "isolates the charge-assignment decision -- the axis the policies differ on.",
            "This scenario's peak never approaches any site's power cap, so the cap is "
            "not a binding constraint here and no policy is being rewarded for "
            "respecting it (docs/BENCHMARK_CREDIBILITY.md).",
        ],
    }
    blob = json.dumps(payload, indent=1, sort_keys=True)
    payload["cost_sha256"] = hashlib.sha256(blob.encode()).hexdigest()
    return payload


def main() -> dict:
    sc = HERE.parent / "solvers" / "cpsat" / "scenario_canonical.json"
    comp = cost_comparison(sc)
    artifact = HERE / "cost_seed424242.json"
    blob = json.dumps(comp, indent=1, sort_keys=True) + "\n"
    if "--write" in sys.argv:
        artifact.write_text(blob)
        print(f"wrote {artifact.name}  sha256={comp['cost_sha256']}")
    elif artifact.exists():
        same = artifact.read_text() == blob
        print(f"regenerated sha256={comp['cost_sha256']} -> "
              f"{'MATCHES' if same else 'DIFFERS FROM'} committed artifact")

    for site_id, s in comp["sites"].items():
        print(f"\n{site_id}  ({s['utility']} {s['tariff']})")
        print(f"  {'policy':>14} {'peak kW':>9} {'demand $':>10} {'energy $':>10} "
              f"{'month $':>10} {'vs fifo':>10}")
        for name, r in sorted(s["policies"].items()):
            print(f"  {name:>14} {r['measured_peak_kw']:>9,.0f} {r['demand_cost']:>10,.0f} "
                  f"{r['energy_cost']:>10,.0f} {r['monthly_total']:>10,.0f} "
                  f"{r['monthly_delta_vs_fifo']:>10,.0f}")
    t = comp["tradeoff"]
    print(f"\n--- the tradeoff, at {t['reference_site']} ---")
    print(f"  {'policy':>14} {'tardy min':>10} {'month $':>10}")
    for n in sorted(t["total_tardy_min"]):
        print(f"  {n:>14} {t['total_tardy_min'][n]:>10,} "
              f"{t['monthly_total_usd'][n]:>10,.0f}")
    print(f"  pareto-optimal: {', '.join(t['pareto_optimal'])}")
    print(f"  DOMINATED     : {', '.join(t['dominated']) or '(none)'}")
    return comp


if __name__ == "__main__":
    main()


# ---- how much of the cost gap is actually recoverable? ---------------------------

def peak_lower_bound(scenario_path) -> dict:
    """A PROVABLE lower bound on the peak any feasible schedule can achieve.

    Answers the question that has to precede "should we optimise for cost": is there
    anything to win? A gap between two policies says one is better than the other; it
    says nothing about how much either is leaving on the table.

    THE ARGUMENT, which is why this is a bound and not an estimate. Take any window
    [s, e]. Every asset whose ENTIRE feasible interval [arrival, ready_by] lies inside
    that window must receive all of its energy within it -- it cannot start earlier or
    finish later. So the average draw over that window is at least (energy of those
    assets) / (e - s), and the PEAK is at least the average. Maximising over all
    windows gives a valid lower bound. A single asset with a tight window supplies a
    second floor the same way.

    This is a bound, not a target. Achieving it would need perfectly interleaved
    fractional charging; real points deliver fixed kW, so the true optimum sits
    somewhere above it. That makes the headroom it reports CONSERVATIVE -- the real
    recoverable amount is smaller than the number below, never larger.
    """
    sc = load_scenario(scenario_path)
    classes = sc["asset_classes"]
    items = []
    for a in sc["assets"]:
        c = classes[a.cls]
        items.append({
            "aid": a.aid, "start": float(a.arrival_min), "end": float(a.ready_by_min),
            "kwh": c["battery_kwh"] * (a.target_soc - a.soc) / 100.0,
        })

    times = sorted({i["start"] for i in items} | {i["end"] for i in items})
    best_kw, best_window = 0.0, None
    for idx, s in enumerate(times):
        for e in times[idx + 1:]:
            hours = (e - s) / 60.0
            if hours <= 0:
                continue
            need = sum(i["kwh"] for i in items if i["start"] >= s and i["end"] <= e)
            if need <= 0:
                continue
            kw = need / hours
            if kw > best_kw:
                best_kw, best_window = kw, (s, e, need, hours)

    solo = max(i["kwh"] / ((i["end"] - i["start"]) / 60.0) for i in items)
    bound = max(best_kw, solo)
    return {
        "peak_lower_bound_kw": round(bound, 1),
        "binding_window": ({"start_min": best_window[0], "end_min": best_window[1],
                            "kwh": round(best_window[2], 1),
                            "hours": round(best_window[3], 2)} if best_window else None),
        "single_asset_floor_kw": round(solo, 1),
        "total_energy_kwh": round(sum(i["kwh"] for i in items), 1),
    }


def headroom(scenario_path, *, site_id: str = "site_alpha", month: int = 7) -> dict:
    """What the ideal schedule would bill, and therefore what is left on the table.

    The ideal is a flat curve at the lower bound, held long enough to deliver the
    scenario's energy. Since the bound is conservative, the headroom reported here is
    an UNDERSTATEMENT of the true opportunity, which is the right direction for a
    number that will be used to decide whether work is worth doing.
    """
    lb = peak_lower_bound(scenario_path)
    kw = lb["peak_lower_bound_kw"]
    sc = load_scenario(scenario_path)
    start = min(float(a.arrival_min) for a in sc["assets"])
    minutes = lb["total_energy_kwh"] / kw * 60.0

    curve = [(float(m), kw if start <= m < start + minutes else 0.0)
             for m in range(0, DAY_MIN, STEP_MIN)]
    curve.append((float(DAY_MIN), 0.0))

    site = get_site(site_id)
    ideal = site.tariff.bill(curve, month=month, days=30, historical_peak_kw=kw)

    comp = cost_comparison(scenario_path, site_ids=(site_id,), month=month)
    rows = comp["sites"][site_id]["policies"]
    return {
        "site_id": site_id,
        "peak_lower_bound_kw": kw,
        "ideal_monthly_usd": ideal["total"],
        "policies": {
            name: {
                "monthly_usd": r["monthly_total"],
                "left_on_table_usd": round(r["monthly_total"] - ideal["total"], 2),
                "multiple_of_ideal": round(r["monthly_total"] / ideal["total"], 2)
                if ideal["total"] else None,
            }
            for name, r in sorted(rows.items())
        },
        "caveat": (
            "The bound assumes perfectly interleaved fractional charging; real points "
            "deliver fixed kW, so the true optimum is above it and the headroom here "
            "is an understatement, never an overstatement."
        ),
    }
