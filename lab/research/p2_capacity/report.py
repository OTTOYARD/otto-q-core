#!/usr/bin/env python3
"""Summarise the capacity days (results.jsonl from capacity_day.py) into the capacity curve, one line per day and one
per (scenario, fleet) averaged over seeds, with the resource the engine's constraint board most often named the wall.

Usage: python3 -I lab/research/p2_capacity/report.py [results.jsonl]
"""
from __future__ import annotations

import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))


def row(d: dict) -> dict:
    sc = d.get("scorecard") or {}
    tp, tl, cw = sc.get("throughput", {}), sc.get("timeliness", {}), sc.get("charge_wait", {})
    r9 = sc.get("rule9", {})
    owners = d.get("owners") or []
    res = {x["kind"]: x for x in (d.get("resources") or [])}
    walls = Counter((w.get("wall") or {}).get("resource") if isinstance(w.get("wall"), dict) else w.get("wall")
                    for w in d.get("walls") or [] if "error" not in w)
    charged = sum(o.get("charged") or 0 for o in owners)
    over = sum(o.get("over_contract_wait") or 0 for o in owners)
    return {
        "scenario": d["scenario"], "fleet": d["fleet"], "seed": d["seed"], "ticks": d["ticks"], "wall_s": d["wall_s"],
        "error": bool(d.get("error")),
        "visits": tp.get("visits"), "served": tp.get("visits_served"), "served_per_day": tp.get("served_per_day"),
        "in_depot": tp.get("in_depot_at_horizon"),
        "on_time": tl.get("on_time"), "due_served": tl.get("due_served"), "on_time_pct": tl.get("on_time_pct"),
        "door_p50": tl.get("door_p50_min"), "door_p95": tl.get("door_p95_min"),
        "wait_p50": cw.get("p50_wait_min"), "wait_p95": cw.get("p95_wait_floor_min"),
        "over_contract_pct": round(100.0 * over / charged, 1) if charged else None,
        "left_below_target": r9.get("left_below_target"), "left_with_work_open": r9.get("left_with_needed_work_open"),
        "post_busy_pct": (res.get("dcfc") or {}).get("busy_pct"), "wash_busy_pct": (res.get("wash_bay") or {}).get("busy_pct"),
        "service_busy_pct": (res.get("service_bay") or {}).get("busy_pct"),
        "wall": walls.most_common(1)[0][0] if walls else None, "walls": dict(walls),
        "owners": {o["owner"]: {k: o.get(k) for k in ("visits", "served", "on_time", "with_due", "wait_p95_min",
                                                       "over_contract_wait", "charged")} for o in owners},
    }


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "results.jsonl")
    days = [row(json.loads(line)) for line in open(path) if line.strip()]
    days.sort(key=lambda r: (r["scenario"], r["fleet"], r["seed"]))
    cols = ["scenario", "fleet", "seed", "visits", "served", "served_per_day", "in_depot", "on_time", "due_served",
            "door_p50", "door_p95", "wait_p50", "wait_p95", "over_contract_pct", "post_busy_pct", "wash_busy_pct",
            "service_busy_pct", "wall", "left_below_target", "left_with_work_open", "wall_s"]
    print(" | ".join(cols))
    for r in days:
        print(" | ".join(str(r.get(c)) for c in cols))
    print()
    agg = defaultdict(list)
    for r in days:
        agg[(r["scenario"], r["fleet"])].append(r)
    keys = ["served_per_day", "in_depot", "on_time_pct", "door_p50", "door_p95", "wait_p95", "over_contract_pct",
            "post_busy_pct", "wash_busy_pct", "service_busy_pct"]
    print("scenario | fleet | seeds | " + " | ".join(keys) + " | walls")
    for (s, f), rs in sorted(agg.items()):
        vals = []
        for k in keys:
            xs = [r[k] for r in rs if isinstance(r.get(k), (int, float))]
            vals.append(round(sum(xs) / len(xs), 1) if xs else None)
        walls = Counter()
        for r in rs:
            walls.update(r["walls"])
        print(f"{s} | {f} | {len(rs)} | " + " | ".join(str(v) for v in vals) + f" | {dict(walls)}")


if __name__ == "__main__":
    main()
