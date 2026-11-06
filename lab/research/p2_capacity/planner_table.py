#!/usr/bin/env python3
"""The battery planner study on the 0801 lab copy, seed by seed: what each way of running the battery cost (LAB ONLY).

Every seed has a base day (the day plan as it runs, `--tag b801`) and planner days (`battery_lp.py` followed through the
MPC bridge) on the same seed and the same lab copy, one per forecast: another day's shape, the learned mean, and the
learned mean plus a quantile of its out-of-sample misses. With G525 fixed (0801) a seed's cars reproduce, so a planner day
is compared only when every car-facing line of its scorecard is the base day's (`whatif_table.py`'s test); a day whose cars
differ is shown and left out of every average.

Each bill comes from `bound_energy.py` (the day pays for its own highest half hour) and is given at the base day's battery
end state (the stored-energy difference at the day plan's replacement cost, `whatif_table.py`), beside no battery and
perfect foresight (the whole day's load known; with and without the 600 kWh call reserve the planner holds).

The quantile is then chosen as a planner would have to choose it, without the day it is graded on: for each seed, the
forecast with the lowest mean bill over the OTHER seeds (leave one seed out), and its bill on this seed.

Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/planner_table.py SEED [SEED ...]
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENERGY = os.path.join(HERE, "..", "p2_perfect_day", "bound_energy.jsonl")
DAYS = os.path.join(HERE, "results.jsonl")
RATE_STORED = 0.0700          # the day plan's replacement_usd_kwh (whatif_table.py)
BASE_TAG = "b801"
ARMS = [("p801shape", "another day's shape"), ("p801mean", "learned mean"), ("p801q80", "mean + q80 miss"),
        ("p801q90", "mean + q90 miss"), ("p801q95", "mean + q95 miss")]
LEARNED = [t for t, _ in ARMS if t != "p801shape"]
CAR_KEYS = ("throughput", "timeliness", "charge_wait", "rule9")


def latest(path: str, key, pred=lambda d: True) -> dict:
    out = {}
    with open(path) as f:
        for line in f:
            if line.strip():
                d = json.loads(line)
                if pred(d):
                    out[key(d)] = d
    return out


def strip_ids(x):
    if isinstance(x, dict):
        return {k: strip_ids(v) for k, v in x.items() if k != "sim_run_id"}
    return x


def db(seed: str, tag: str) -> str:
    return f"ottoq_cap_normal_day_116_{seed}_{tag}"


def main() -> None:
    seeds = sys.argv[1:]
    energy = latest(ENERGY, lambda d: d["db"], lambda d: not d.get("dr_reserve"))
    energy_res = latest(ENERGY, lambda d: d["db"], lambda d: bool(d.get("dr_reserve")))
    days = latest(DAYS, lambda d: d["db"])
    rows = {}
    for s in seeds:
        b = db(s, BASE_TAG)
        if b not in energy or b not in days:
            print(f"seed {s}: base day not billed yet")
            continue
        b_end = energy[b]["battery"]["soc_end_kwh"]
        b_sc = days[b]["scorecard"]
        r = {"base": energy[b]["real_plan"]["total_usd"], "base_peak": energy[b]["real_plan"]["peak30_kw"],
             "base_at": energy[b]["real_plan"].get("peak30_ends_ct", "?"),
             "start": energy[b]["battery"]["soc_start_kwh"], "end": b_end,
             # no battery at the day plan's end-of-day charge: the stored energy the plan bought, at its replacement cost
             "none": energy[b]["no_battery"]["total_usd"] + (b_end - energy[b]["battery"]["soc_start_kwh"]) * RATE_STORED,
             "pf": energy[b]["perfect_foresight"]["total_usd"],
             "pf_res": energy_res[b]["perfect_foresight"]["total_usd"] if b in energy_res else None, "arms": {}}
        for tag, _ in ARMS:
            d = db(s, tag)
            if d not in energy or d not in days:
                continue
            e = energy[d]
            adj = e["real_plan"]["total_usd"] - (e["battery"]["soc_end_kwh"] - b_end) * RATE_STORED
            same = all(strip_ids(days[d]["scorecard"].get(k)) == strip_ids(b_sc.get(k)) for k in CAR_KEYS)
            r["arms"][tag] = {"usd": round(adj, 2), "peak": e["real_plan"]["peak30_kw"], "same": same,
                              "end": e["battery"]["soc_end_kwh"], "at": e["real_plan"].get("peak30_ends_ct", "?")}
        rows[s] = r

    print("bill at the base day's battery end state, USD (half-hour peak kW, the half hour's end CT); no battery at the "
          "same end-of-day charge; * = the cars differ from the base day's")
    head = ["seed", "day plan", "no battery"] + [lab for _, lab in ARMS] + ["perfect foresight", "PF with the reserve"]
    print(" | ".join(head))
    for s, r in rows.items():
        cells = [s, f"{r['base']:.2f} ({r['base_peak']:.0f}, {r['base_at']})", f"{r['none']:.2f}"]
        for tag, _ in ARMS:
            a = r["arms"].get(tag)
            cells.append("" if a is None else f"{a['usd']:.2f} ({a['peak']:.0f}, {a['at']}){'' if a['same'] else ' *'}")
        cells += [f"{r['pf']:.2f}", "" if r["pf_res"] is None else f"{r['pf_res']:.2f}"]
        print(" | ".join(cells))

    clean = {s: r for s, r in rows.items() if r["arms"] and all(a["same"] for a in r["arms"].values())
             and len(r["arms"]) == len(ARMS)}
    print(f"\n{len(clean)} of {len(rows)} seeds with every arm run and every arm's cars the base day's")
    if not clean:
        return
    n = len(clean)
    print("arm | mean bill USD | mean saving on the day plan USD | seeds beating the day plan | "
          "seeds beating the shape | share of the day plan's gap to perfect foresight (reserve held) closed")
    for tag, lab in [("base", "day plan")] + ARMS:
        bills = [r["base"] if tag == "base" else r["arms"][tag]["usd"] for r in clean.values()]
        save = [r["base"] - (r["base"] if tag == "base" else r["arms"][tag]["usd"]) for r in clean.values()]
        beat_b = sum(1 for x in save if x > 0.005)
        beat_s = sum(1 for r in clean.values()
                     if tag != "base" and r["arms"][tag]["usd"] < r["arms"]["p801shape"]["usd"] - 0.005)
        gaps = [(r["base"] - (r["pf_res"] if r["pf_res"] is not None else r["pf"])) for r in clean.values()]
        share = sum(save) / sum(gaps) if sum(gaps) > 0 else float("nan")
        print(f"{lab} | {sum(bills) / n:.2f} | {sum(save) / n:+.2f} | {beat_b} of {n} | "
              f"{'' if tag in ('base', 'p801shape') else f'{beat_s} of {n}'} | {share:.0%}")
    # the quantile chosen without the day it is graded on
    print("\nthe forecast chosen on the other seeds' bills (leave one seed out), and its bill on the seed left out")
    picks, saves, vs_shape = {}, [], []
    for s, r in clean.items():
        others = [o for o in clean if o != s]
        if not others:
            break
        best = min(LEARNED, key=lambda t: sum(clean[o]["arms"][t]["usd"] for o in others) / len(others))
        picks[s] = best
        saves.append(r["base"] - r["arms"][best]["usd"])
        vs_shape.append(r["arms"]["p801shape"]["usd"] - r["arms"][best]["usd"])
        print(f"{s}: chose {best}, {r['arms'][best]['usd']:.2f} against the day plan's {r['base']:.2f} "
              f"({r['base'] - r['arms'][best]['usd']:+.2f}) and the shape's {r['arms']['p801shape']['usd']:.2f}")
    if saves:
        print(f"chosen leave-one-seed-out: mean saving on the day plan {sum(saves) / len(saves):+.2f} USD a day "
              f"({sum(1 for x in saves if x > 0.005)} of {len(saves)} seeds), on the shape "
              f"{sum(vs_shape) / len(vs_shape):+.2f} ({sum(1 for x in vs_shape if x > 0.005)} of {len(vs_shape)})")


if __name__ == "__main__":
    main()
