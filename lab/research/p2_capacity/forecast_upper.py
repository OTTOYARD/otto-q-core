#!/usr/bin/env python3
"""Two upper forecasts of the depot's EV charging, graded out of sample (LAB ONLY; the battery planner's question, 2026-11-06).

A battery that shaves the demand peak needs to know how high the next half hours could go, not their average. Two ways to
say that, both fitted per half hour ahead on the day plan's own terms at the tick (as `forecast_learn.py`):
  offset  the learned mean (ridge) plus a fixed quantile of its misses, the misses each training day had when it was left
          out of the fit (what `forecast_learn.py --save --quantile q --offset-from cv` writes for the planner)
  qr      a linear quantile regression at q (the pinball loss, solved as a linear program, OR-Tools GLOP): the bound moves
          with what the depot knows at the tick, wide when the cars coming home are many, narrow when they are not
Graded leave-one-seed-out (fit on the other seeds' days, scored on the held-out seed): the share of half hours the depot
drew no more than the forecast (coverage, which should read q), and how far over the draw the forecast stood on average
(the room it hides from a planner: smaller is better at the same coverage), with the pinball loss at q.

Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/forecast_upper.py forecast_audit_0801.jsonl --q 0.8
       [--save-qr PATH --exclude-seed SEED]   (writes a qr model in forecast_learn.py's format: offset 0, the planner reads it)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict

import numpy as np
from ortools.linear_solver import pywraplp

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # run with -I: the sibling modules
from ev_drawn import drawn  # noqa: E402
from forecast_learn import AHEAD, examples, ridge  # noqa: E402


def standardise(X: np.ndarray):
    mu, sd = X[:, 1:].mean(0), X[:, 1:].std(0) + 1e-9
    return mu, sd, np.hstack([X[:, :1], (X[:, 1:] - mu) / sd])


def qr_fit(X: np.ndarray, y: np.ndarray, q: float, l1: float = 0.0):
    """Linear quantile regression on standardised features: min sum of pinball(q) (+ l1 on the slopes)."""
    mu, sd, Z = standardise(X)
    n, p = Z.shape
    s = pywraplp.Solver.CreateSolver("GLOP")
    w = [s.NumVar(-s.infinity(), s.infinity(), "") for _ in range(p)]
    u = [s.NumVar(0, s.infinity(), "") for _ in range(n)]
    v = [s.NumVar(0, s.infinity(), "") for _ in range(n)]
    a = [s.NumVar(0, s.infinity(), "") for _ in range(p)]
    for i in range(n):
        s.Add(sum(float(Z[i, j]) * w[j] for j in range(p)) + u[i] - v[i] == float(y[i]))
    for j in range(1, p):
        s.Add(a[j] >= w[j])
        s.Add(a[j] >= -w[j])
    s.Minimize(sum(q * u[i] + (1 - q) * v[i] for i in range(n)) + l1 * n * sum(a[1:]))
    if s.Solve() not in (pywraplp.Solver.OPTIMAL, pywraplp.Solver.FEASIBLE):
        raise RuntimeError("quantile regression did not solve")
    wv = np.array([x.solution_value() for x in w])
    return mu, sd, wv, (lambda Xn: np.hstack([Xn[:, :1], (Xn[:, 1:] - mu) / sd]) @ wv)


def seed_of(db: str) -> str:
    m = re.search(r"_(\d{6})_", db + "_")
    return m.group(1) if m else db


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("audit")
    ap.add_argument("--q", type=float, default=0.8)
    ap.add_argument("--lam", type=float, default=10.0)
    ap.add_argument("--l1", type=float, default=0.0, help="l1 on the quantile regression's slopes, per example")
    ap.add_argument("--save-qr", help="fit the quantile regression on every day but --exclude-seed's and write it here")
    ap.add_argument("--exclude-seed", action="append", default=[])
    a = ap.parse_args()
    days = defaultdict(list)
    for line in open(a.audit):
        if line.strip():
            r = json.loads(line)
            days[(r["db"], r["run"])].append(r)
    data = {d: examples(rs, drawn(*d)) for d, rs in days.items()}
    if a.save_qr:
        keep = {d: ex for d, ex in data.items() if seed_of(d[0]) not in a.exclude_seed}
        model = {"kind": "quantile_regression", "q": a.q, "l1": a.l1,
                 "features": ["1", "on_charger", "arrivals", "queue", "last_hour", "base", "solar", "sin_hour", "cos_hour",
                              "rule_without_arrivals"],
                 "days": sorted(d[0] for d in keep), "per_half_hour": [], "quantile": a.q, "offset_from": "qr"}
        for h in range(AHEAD):
            tr = [e for ex in keep.values() for e in ex if e["h"] == h]
            mu, sd, w, _ = qr_fit(np.array([e["x"] for e in tr]), np.array([e["y"] for e in tr]), a.q, a.l1)
            model["per_half_hour"].append({"h": h, "n": len(tr), "mu": mu.tolist(), "sd": sd.tolist(), "w": w.tolist(),
                                           "offset_kw": 0.0})
        with open(a.save_qr, "w") as f:
            json.dump(model, f)
        print(f"saved {a.save_qr}: quantile regression at {a.q}, fit on {len(keep)} days")
        return
    seeds = sorted({seed_of(d[0]) for d in data})
    print(f"{len(data)} days, {len(seeds)} seeds; upper forecasts at q = {a.q}, leave one seed out: coverage (share of "
          f"half hours drawn at or under the forecast), mean excess over the draw (kW), pinball loss")
    print("  ahead    offset: cover  excess  pinball      qr: cover  excess  pinball")
    tot = defaultdict(list)
    for h in range(AHEAD):
        res = {"offset": [], "qr": []}
        for s in seeds:
            tr_days = {d: ex for d, ex in data.items() if seed_of(d[0]) != s}
            tr = [e for ex in tr_days.values() for e in ex if e["h"] == h]
            te = [e for d, ex in data.items() if seed_of(d[0]) == s for e in ex if e["h"] == h]
            if not tr or not te:
                continue
            Xtr, ytr = np.array([e["x"] for e in tr]), np.array([e["y"] for e in tr])
            Xte, yte = np.array([e["x"] for e in te]), np.array([e["y"] for e in te])
            # offset: the mean, plus the q-quantile of each training day's out-of-sample misses
            miss = []
            for out_day in tr_days:
                tr_i = [e for d, ex in tr_days.items() if d != out_day for e in ex if e["h"] == h]
                te_i = [e for e in tr_days[out_day] if e["h"] == h]
                if tr_i and te_i:
                    f_i = ridge(np.array([e["x"] for e in tr_i]), np.array([e["y"] for e in tr_i]), a.lam)
                    miss.extend((np.array([e["y"] for e in te_i]) - f_i(np.array([e["x"] for e in te_i]))).tolist())
            f = ridge(Xtr, ytr, a.lam)
            up_off = np.maximum(f(Xte) + float(np.quantile(miss, a.q)), 0)
            _, _, _, g = qr_fit(Xtr, ytr, a.q, a.l1)
            up_qr = np.maximum(g(Xte), 0)
            for k, up in (("offset", up_off), ("qr", up_qr)):
                res[k].append((up, yte))
        cells = []
        for k in ("offset", "qr"):
            up = np.concatenate([x for x, _ in res[k]])
            y = np.concatenate([z for _, z in res[k]])
            d = y - up
            pin = np.mean(np.maximum(a.q * d, (a.q - 1) * d))
            cells.append(f"{np.mean(y <= up):6.1%} {np.mean(up - y):7.0f} {pin:8.1f}")
            tot[k].append((np.mean(y <= up), np.mean(up - y), pin))
        print(f"  {30 * h:3d}-{30 * (h + 1):3d}   " + "        ".join(cells))
    for k in ("offset", "qr"):
        c = np.array(tot[k])
        print(f"  all {k:6s}: coverage {c[:, 0].mean():.1%}, mean excess {c[:, 1].mean():.0f} kW, pinball {c[:, 2].mean():.1f}")


if __name__ == "__main__":
    main()
