#!/usr/bin/env python3
"""Where a solved perfect day gains on the real one (E5; LAB ONLY).

Reads a finished lab day (its kept replica) and the schedule `bound_ops.py --dump-schedule` wrote for it, and splits the
gap two ways:
  - by lane: each job's wait after its car was free for it (at the gate, or its previous job's end), real against solved;
  - by when the car reached the gate: the start-up (the first two hours, when the lab day begins with the whole fleet at
    the depot) against the rest of the day, in minutes from the visit's start to ready, real against solved.

Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_perfect_day/regret_split.py <db> <schedule.jsonl> [ready_min]
Nothing here touches production.
"""
from __future__ import annotations

import importlib.util
import json
import math
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bound_ops", os.path.join(HERE, "bound_ops.py"))
bo = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bo)


def main() -> None:
    db, dump = sys.argv[1], sys.argv[2]
    day = bo.load(db, None, occupancy=True)
    H = day["horizon"]
    rows = [json.loads(line) for line in open(dump)]
    jobs = defaultdict(list)
    for r in rows:
        jobs[r["visit"]].append(r)
    # the readiness tail the solve used (bound_ops.py --ready-min, 5 by default); a third argument overrides it
    ready_min = int(sys.argv[3]) if len(sys.argv) > 3 else bo.READY_MIN

    lane = defaultdict(lambda: [0.0, 0.0, 0])
    for js in jobs.values():
        for k, key in enumerate(("real_start", "solved_start")):
            t = None
            for j in sorted((j for j in js if j[key] is not None), key=lambda j: j[key]):
                free = j["rel"] if t is None else max(t, j["rel"])
                lane[j["lane"]][k] += j[key] - free
                lane[j["lane"]][2] += 1 if k == 0 else 0
                t = j[key] + j["dur"]
    print("waits after the car was free for the job (minutes): lane | real | solved | jobs")
    for name, (r, s, n) in sorted(lane.items()):
        print(f"  {name:12s} {r:7.0f} {s:7.0f} {n:4d}")

    blocks = defaultdict(lambda: [0.0, 0.0, 0])
    for v in day["visits"]:
        arr = float(v["arr"])
        dep = float(v["dep"]) if v["dep"] is not None else H
        ready = min(float(v["ready"]) if v["ready"] is not None else dep, dep) if v["dep"] is not None else H
        real = max(min(ready, H) - arr, 0)
        js = jobs.get(v["visit_id"], [])
        last = max([j["solved_start"] + max(round(j["dur"]), 1) for j in js] + [math.ceil(v["rel"])])
        solved = max(min(last + ready_min, max(math.ceil(H), arr)) - math.floor(arr), 0)
        b = "start-up (at the gate in the first 2 h)" if v["rel"] < 120 else "the rest of the day"
        blocks[b][0] += real
        blocks[b][1] += solved
        blocks[b][2] += 1
    print("minutes from the visit's start to ready, by when the car reached the gate: real | solved | gap")
    for b, (r, s, n) in blocks.items():
        print(f"  {b:40s} visits {n:3d}  {r:7.0f} {s:7.0f}  {r - s:6.0f} ({(r - s) / r * 100:4.1f}%)")


if __name__ == "__main__":
    main()
