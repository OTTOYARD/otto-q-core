#!/usr/bin/env python3
"""Grade the battery day plan's own EV forecast against what the depot then drew (LAB ONLY).

Reads `forecast_audit.jsonl` (written by `capacity_day.py --log-forecast`: after every tick, ottoq_bess_day_plan's forecast
arrays at the run's clock, half hour by half hour, and the known term's first loop alone) and, from each day's kept replica,
the EV charging the depot drew (site_energy_snapshots, 5-minute). For every tick and every half hour ahead it sets each
forecast term against the mean drawn over that half hour, and prints the bias (forecast less drawn) and the mean absolute
error by how far ahead, for:
  known    the known term as the day plan reads it (cars on a charger now held at their starting rate, plus cars coming
           home charged from their arrival whether or not a post is free: ottoq_forecast_ev_known_kw)
  active   its first loop alone (the cars on a charger now)
  queue    the post-aware term (ottoq_forecast_ev_queue_kw: the cars waiting and coming home, queued onto the posts)
  persist  the last hour's draw held flat
  ev       what the day plan uses: max(known, queue, persist)
  alt      max(active, queue, persist): the day plan's rule without the post-blind arrivals

Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/forecast_grade.py [forecast_audit.jsonl] [--ahead 8]
Nothing here touches production.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # run with -I: the sibling module
from ev_drawn import drawn  # noqa: E402  the replica's EV series, or its committed copy (ev_drawn.jsonl)

HERE = os.path.dirname(os.path.abspath(__file__))




def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("audit", nargs="?", default=os.path.join(HERE, "forecast_audit.jsonl"))
    ap.add_argument("--ahead", type=int, default=8, help="half hours ahead to grade")
    a = ap.parse_args()
    rows = [json.loads(line) for line in open(a.audit) if line.strip()]
    by_day = defaultdict(list)
    for r in rows:
        by_day[(r["db"], r["run"])].append(r)
    for (db, run), rs in by_day.items():
        ev = dict(drawn(db, run))
        times = sorted(ev)
        terms = ("known", "active", "queue", "persist", "ev", "alt")
        err = {t: defaultdict(list) for t in terms}
        for r in rs:
            clk = dt.datetime.fromisoformat(r["clock"])
            known, queue = r.get("ev_known_kw") or [], r.get("ev_queue_kw") or []
            active, evk = r.get("ev_active_kw") or [], r.get("ev_kw") or []
            persist = float(r.get("ev_persist_kw") or 0)
            for h in range(min(a.ahead, len(known), len(queue), len(evk))):
                lo, hi = clk + dt.timedelta(minutes=30 * h), clk + dt.timedelta(minutes=30 * (h + 1))
                got = [ev[t] for t in times if lo < t <= hi]
                if len(got) < 6:          # a half hour the day did not reach
                    continue
                real = sum(got) / len(got)
                act = float(active[h]) if h < len(active) else 0.0
                f = {"known": float(known[h]), "active": act, "queue": float(queue[h]), "persist": persist,
                     "ev": float(evk[h]), "alt": max(act, float(queue[h]), persist)}
                for t in terms:
                    err[t][h].append(f[t] - real)
        print(f"{db} (run {run[:8]}, {len(rs)} ticks): forecast less drawn, kW, by half hours ahead (bias / mean absolute)")
        print("  ahead   " + "  ".join(f"{t:>14s}" for t in terms))
        for h in range(a.ahead):
            if not err["ev"][h]:
                continue
            cells = []
            for t in terms:
                e = err[t][h]
                cells.append(f"{sum(e) / len(e):6.0f} /{sum(abs(x) for x in e) / len(e):6.0f}")
            print(f"  {30 * h:3d}-{30 * (h + 1):3d}  " + "  ".join(f"{c:>14s}" for c in cells) + f"   n={len(err['ev'][h])}")


if __name__ == "__main__":
    main()
