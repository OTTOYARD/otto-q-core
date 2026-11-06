#!/usr/bin/env python3
"""A learned EV-load forecast for the battery, graded against the day plan's own (LAB ONLY; the research wing's E8 question:
can OTTO-Q's overnight learning give the battery a better forecast than its hand-built rule?).

Rule 10 lets production OTTO-Q update its estimates overnight from the day's real data, and never its rules: a forecast
model refit each night is an estimate. This tests the idea on the lab's audited days (`capacity_day.py --log-forecast`):
for every tick and each half hour ahead (h = 0..7), a ridge regression on what the day plan already computes at that tick
(the cars on a charger now held at their starting rate, the cars coming home charged from their arrival, the post-aware
queue, the last hour's draw, the building and the sun) and the hour of the day, predicting the EV charging the depot then
drew over that half hour. Graded leave-one-day-out (fit on the other days, scored on the held-out day), against:
  ev     the day plan's rule as it runs: max(known, queue, last hour)
  alt    the same rule without the post-blind arrivals: max(on charger, queue, last hour) (whatif_dayplan_on_charger.sql)
  queue  the post-aware queue term alone

Only base days are used (days whose day plan ran unchanged: the known term in their log still holds the arrivals).
Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/forecast_learn.py [forecast_audit.jsonl] [--lam 10]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
from collections import defaultdict
from zoneinfo import ZoneInfo

import numpy as np
import psycopg

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
HERE = os.path.dirname(os.path.abspath(__file__))
TWIN = "11111111-1111-1111-1111-111111111111"
CT = ZoneInfo("America/Chicago")
AHEAD = 8


def drawn(db: str, run: str) -> list[tuple[dt.datetime, float]]:
    with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=db) as c:
        return [(t, float(kw)) for t, kw in c.execute(
            """SELECT timestamp, COALESCE(total_ev_charging_kw, 0) FROM site_energy_snapshots
                WHERE sim_run_id = %s AND depot_id = %s ORDER BY timestamp""", (run, TWIN)).fetchall()]


def examples(rows: list[dict], ev: list[tuple[dt.datetime, float]]) -> list[dict]:
    out = []
    for r in rows:
        clk = dt.datetime.fromisoformat(r["clock"])
        known, queue = r.get("ev_known_kw") or [], r.get("ev_queue_kw") or []
        active, rule = r.get("ev_active_kw") or [], r.get("ev_kw") or []
        base, solar = r.get("base_kw") or [], r.get("solar_kw") or []
        persist = float(r.get("ev_persist_kw") or 0)
        for h in range(min(AHEAD, len(known), len(queue), len(rule), len(active))):
            lo, hi = clk + dt.timedelta(minutes=30 * h), clk + dt.timedelta(minutes=30 * (h + 1))
            got = [kw for t, kw in ev if lo < t <= hi]
            if len(got) < 6:
                continue
            hr = (lo.astimezone(CT).hour + lo.astimezone(CT).minute / 60.0)
            act, kn, q = float(active[h]), float(known[h]), float(queue[h])
            out.append({"h": h, "y": sum(got) / len(got), "rule": float(rule[h]), "alt": max(act, q, persist), "queue": q,
                        "x": [1.0, act, kn - act, q, persist, float(base[h]) if h < len(base) else 0.0,
                              float(solar[h]) if h < len(solar) else 0.0,
                              math.sin(2 * math.pi * hr / 24), math.cos(2 * math.pi * hr / 24),
                              max(act, q, persist)]})
    return out


def ridge(X: np.ndarray, y: np.ndarray, lam: float) -> np.ndarray:
    mu, sd = X[:, 1:].mean(0), X[:, 1:].std(0) + 1e-9         # standardise all but the intercept
    Z = np.hstack([X[:, :1], (X[:, 1:] - mu) / sd])
    P = lam * np.eye(Z.shape[1])
    P[0, 0] = 0.0
    w = np.linalg.solve(Z.T @ Z + P, Z.T @ y)
    return lambda Xn: np.hstack([Xn[:, :1], (Xn[:, 1:] - mu) / sd]) @ w


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("audit", nargs="?", default=os.path.join(HERE, "forecast_audit.jsonl"))
    ap.add_argument("--lam", type=float, default=10.0)
    a = ap.parse_args()
    days = defaultdict(list)
    for line in open(a.audit):
        if line.strip():
            r = json.loads(line)
            days[(r["db"], r["run"])].append(r)
    data = {d: examples(rs, drawn(*d)) for d, rs in days.items()}
    print(f"{len(data)} days; leave-one-day-out ridge (lambda {a.lam}), per half hour ahead: mean absolute error, kW "
          f"(bias in brackets)")
    for held in data:
        print(f"held out: {held[0].removeprefix('ottoq_cap_')} ({len(data[held])} examples)")
        print("  ahead      day plan's rule      without arrivals         queue alone        learned")
        for h in range(AHEAD):
            tr = [e for d, ex in data.items() if d != held for e in ex if e["h"] == h]
            te = [e for e in data[held] if e["h"] == h]
            if not tr or not te:
                continue
            f = ridge(np.array([e["x"] for e in tr]), np.array([e["y"] for e in tr]), a.lam)
            yhat = f(np.array([e["x"] for e in te]))
            y = np.array([e["y"] for e in te])
            cell = lambda p: f"{np.mean(np.abs(p - y)):6.0f} ({np.mean(p - y):+5.0f})"
            print(f"  {30 * h:3d}-{30 * (h + 1):3d}   " + "   ".join(
                cell(np.array([e[k] for e in te])) for k in ("rule", "alt", "queue")) + "   " + cell(yhat))


if __name__ == "__main__":
    main()
