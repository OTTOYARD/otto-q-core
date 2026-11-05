#!/usr/bin/env python3
"""The battery what-if days side by side: each day's bill as its battery plan ran it, made comparable, and a check that
the cars did not notice.

Each what-if day (`lab/research/p2_capacity/capacity_day.py --tag ...`) runs the same cars on the same seed with one change
to the battery's plan. Its bill comes from `bound_energy.py` (each day paying for its own highest half hour), but the days
end with different energy in the battery, and a plan that ends emptier looks cheaper while it has only moved the cost to
tomorrow. So each bill is also given at the base day's end state: the difference in stored energy valued at what the day
plan itself prices a stored kWh (its replacement cost, the cheapest TOU rate over the round trip: `replacement_usd_kwh`).
And the cars: every line of the scorecard that a vehicle could feel must be identical to the base day's (the battery plan
never limits a car's charge: `ottoq_effective_charge_cap_kw`, 0136), or the table says so.

Usage: python3 -I lab/research/p2_perfect_day/whatif_table.py BASE_DB WHATIF_DB [WHATIF_DB ...]
(the dbs' bound_energy.jsonl rows must exist: the latest row per db, with no --dr-reserve-kwh, is used)
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(HERE, "..", "p2_capacity", "results.jsonl")
RATE_STORED = 0.0700   # the day plan's replacement_usd_kwh on these days (min TOU 0.0672 / round trip 0.96), read from its own record


def latest(path: str, key, pred=lambda d: True) -> dict:
    out = {}
    with open(path) as f:
        for line in f:
            if line.strip():
                d = json.loads(line)
                if pred(d):
                    out[key(d)] = d
    return out


def main() -> None:
    dbs = sys.argv[1:]
    energy = latest(os.path.join(HERE, "bound_energy.jsonl"), lambda d: d["db"], lambda d: not d.get("dr_reserve"))
    days = latest(CAP, lambda d: d["db"])
    base = dbs[0]
    b_end = energy[base]["battery"]["soc_end_kwh"]
    b_sc = days[base]["scorecard"]
    car_keys = ("throughput", "timeliness", "charge_wait", "rule9")
    print("day | half-hour peak kW | bill USD | battery at day end kWh | bill at the base day's end state USD | cars as the base day")
    for db in dbs:
        e = energy[db]
        rp, end = e["real_plan"], e["battery"]["soc_end_kwh"]
        adj = rp["total_usd"] - (end - b_end) * RATE_STORED      # ending emptier leaves energy to buy back
        same = all(days[db]["scorecard"].get(k) == b_sc.get(k) for k in car_keys)
        tag = days[db].get("tag") or "base"
        print(f"{tag} | {rp['peak30_kw']} | {rp['total_usd']:.2f} | {end} | {adj:.2f} | {'identical' if same else 'DIFFERENT'}")
    nb = energy[base]["no_battery"]
    pf = energy[base]["perfect_foresight"]
    print(f"no battery | {nb['peak30_kw']} | {nb['total_usd']:.2f} | | |")
    print(f"perfect foresight (ends at the base day's end state) | {pf['peak30_kw']} | {pf['total_usd']:.2f} | {b_end} | "
          f"{pf['total_usd']:.2f} |")


if __name__ == "__main__":
    main()
