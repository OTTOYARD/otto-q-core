#!/usr/bin/env python3
"""Replay a run's charge line on its posts under an ordering rule (db/checks/0471, db/migrations/0781).

A rehearsal, not the twin: each visit that charged joins the line at its arrival and takes its real charge minutes; a
post is down from each faulted charge to the next charge on it; the posts are whatever stalls the run's charges used.
Every order sees the same arrivals, minutes and repairs, so the orders differ only in who is served next. It does not
replay the bays (a car's first service seat is the run's own), the agent's orders, the gate or the ticks.

Usage:
  scripts/replay_charge_line.py EXTRACT.json [--margin 30]

EXTRACT.json is the one row of db/checks/0471 query (1), saved as JSON ({"d": {...}} or the bare object). Prints, per
run, the kernel's order today (0642: a car past 90 minutes first, then the response ratio in minutes) and 0781's (the
same, with a car whose turn in the service bays is its charge and the margin away yielding to the cars a charge sends
home), with hindsight's variant (each car's real first service seat as its turn) beside them.
"""
import argparse
import json
import sys
from datetime import datetime, timedelta

FLOOR = 90.0
SERVICE = {"mechanical_pm", "sensor_calibration", "fault_repair", "cosmetic_repair"}
ENACTED = {"otto_q_enacted", "twin_observed"}
STEP = 0.25           # minutes; the twin's tick is about 0.31


def P(s):
    return datetime.fromisoformat(s) if s else None


def mins(a, b):
    return (b - a).total_seconds() / 60.0


def jobs_of(run, d):
    """One charge job per visit that charged: its arrival, real charge minutes, whether it owes service-bay work, its
    open service minutes, its first service seat, and its due time."""
    meta = [r for r in d["runs"] if r["run"] == run][0]
    t1 = P(meta["e"])
    visits = sorted([v for v in d["visits"] if v["run"] == run], key=lambda v: (v["car"], v["arr"]))
    sess = [s for s in d["sessions"] if s["run"] == run]
    seats = {}
    for b in d["bays"]:
        if (b["run"] == run and b["type"] == "service_bay" and b["by"] in ENACTED
                and b["state"] in ("done", "active", "interrupted", "released")):
            seats.setdefault(b["car"], []).append(P(b["s"]))
    by_car = {}
    for v in visits:
        by_car.setdefault(v["car"], []).append(v)
    jobs = []
    for car, vs in by_car.items():
        for i, v in enumerate(vs):
            a, nxt, ready = P(v["arr"]), (P(vs[i + 1]["arr"]) if i + 1 < len(vs) else None), P(v["ready"])
            ss = [s for s in sess if s["car"] == car and P(s["s"]) >= a - timedelta(minutes=1)
                  and (nxt is None or P(s["s"]) < nxt) and (ready is None or P(s["s"]) <= ready)]
            if not ss:
                continue
            svc = [x for x in (v["bay"] or []) if x["svc"] in SERVICE]
            st = sorted(t for t in seats.get(car, []) if t >= a and (nxt is None or t < nxt))
            jobs.append(dict(car=car, visit=v["visit"], arr=a, nxt=nxt, due=P(v["due"]),
                             p=sum(mins(P(s["s"]), P(s["e"]) or t1) for s in ss),
                             svc=bool(svc),
                             svc_min=sum(float(x["est"] or 40) for x in svc if x["st"] not in ("done", "cancelled", "skipped")),
                             seat=st[0] if st else None))
    return jobs


def downtime(run, d, t1):
    by_stall = {}
    for s in d["sessions"]:
        if s["run"] == run:
            by_stall.setdefault(s["stall"], []).append(s)
    down = {}
    for st, ss in by_stall.items():
        ss.sort(key=lambda s: P(s["s"]))
        for i, s in enumerate(ss):
            if s["stat"] == "faulted" and s["e"]:
                down.setdefault(st, []).append((P(s["e"]), P(ss[i + 1]["s"]) if i + 1 < len(ss) else t1))
    return down, sorted(by_stall)


def bay_eta(jobs, d, run, t0, H, B=2):
    """eta(visit, t): the work ahead of the car in the service-bay line as it stands at t (first come, as 0781's
    public.ottoq_bay_line orders it) and what is left of the cars in the bays, over B bays."""
    line = [dict(v=j["visit"], r=max(mins(t0, j["arr"]), 0.0), seat=(mins(t0, j["seat"]) if j["seat"] else None),
                 leave=(mins(t0, j["nxt"]) if j["nxt"] else H + 1e6), w=j["svc_min"]) for j in jobs if j["svc"]]
    occ = []
    for b in d["bays"]:
        if (b["run"] == run and b["type"] == "service_bay" and b["by"] in ENACTED
                and b["state"] in ("done", "active", "interrupted", "released")):
            occ.append((mins(t0, P(b["s"])), mins(t0, P(b["rel"]) if b["rel"] else P(b["e"])), mins(t0, P(b["e"]))))

    def eta(visit, t):
        present = sorted((x for x in line if x["r"] <= t and (x["seat"] is None or x["seat"] > t) and x["leave"] > t),
                         key=lambda x: (x["r"], x["v"]))
        ahead = 0.0
        for x in present:
            if x["v"] == visit:
                return (ahead + sum(max(pe - t, 0) for s, e, pe in occ if s <= t < e)) / B
            ahead += x["w"]
        return None
    return eta


def replay(jobs, down, posts, t0, H, gate):
    """gate(j, t) -> True when the car yields (0781's exit key 1); None for today's order."""
    for j in jobs:
        j["_r"] = max(mins(t0, j["arr"]), 0.0)
    dw = {p: [(mins(t0, a), mins(t0, b)) for a, b in down.get(p, [])] for p in posts}
    free_at = {p: 0.0 for p in posts}
    waiting, start, pending, i, t = [], {}, sorted(jobs, key=lambda j: j["_r"]), 0, 0.0
    while t <= H:
        while i < len(pending) and pending[i]["_r"] <= t:
            waiting.append(pending[i])
            i += 1
        freep = [p for p in posts if free_at[p] <= t and not any(a <= t < b for a, b in dw[p])]
        if freep and waiting:
            def key(j):
                w = t - j["_r"]
                fl = w if w >= FLOOR else None
                x = 1 if (gate is not None and j["svc"] and gate(j, t)) else 0
                return (0 if fl is not None else 1, -(fl or 0), x, -(w + j["p"]) / max(j["p"], 1.0), j["car"])
            waiting.sort(key=key)
            for p in sorted(freep):
                if not waiting:
                    break
                j = waiting.pop(0)
                start[j["visit"]] = t
                free_at[p] = t + j["p"]
        t += STEP
    out = []
    for j in jobs:
        s = start.get(j["visit"])
        out.append(dict(j=j, s=s, e=(s + j["p"]) if s is not None else None, w=(s if s is not None else H) - j["_r"]))
    return out


def summary(res, t0, H):
    ex = [r for r in res if not r["j"]["svc"]]
    bg = [r for r in res if r["j"]["svc"]]
    seated = [r for r in bg if r["j"]["seat"] is not None]
    return dict(
        ex_wait=sum(r["w"] for r in ex) / len(ex), ex_flow=sum(((r["e"] if r["e"] is not None else H) - r["j"]["_r"]) for r in ex),
        bg_wait=sum(r["w"] for r in bg) / len(bg),
        miss=sum(1 for r in seated if r["e"] is None or r["e"] > mins(t0, r["j"]["seat"])),
        miss_min=sum(max((r["e"] if r["e"] is not None else H) - mins(t0, r["j"]["seat"]), 0) for r in seated),
        breach=sum(max(r["w"] - 30, 0) for r in res))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("extract")
    ap.add_argument("--margin", type=float, default=30.0)
    a = ap.parse_args()
    d = json.load(open(a.extract))
    d = d.get("d", d)
    print(f"{'run':10} {'order':34} {'exit-bound wait / time':>24} {'bay-held wait':>14} {'seats before charged':>21} {'past 30 min':>12}")
    for meta in d["runs"]:
        run, t0, t1 = meta["run"], P(meta["s"]), P(meta["e"])
        H = mins(t0, t1)
        jobs = jobs_of(run, d)
        down, posts = downtime(run, d, t1)
        eta = bay_eta(jobs, d, run, t0, H)
        hind = {j["visit"]: (mins(t0, j["seat"]) if j["seat"] else H + 600.0) for j in jobs if j["svc"]}
        rules = [("today (floor 90, minutes)", None),
                 (f"0781, margin {a.margin:g}", lambda j, t: (lambda e: e is not None and e - j["p"] >= a.margin)(eta(j["visit"], t))),
                 (f"0781 with hindsight's bay turns", lambda j, t: hind[j["visit"]] - t - j["p"] >= a.margin)]
        for name, gate in rules:
            s = summary(replay(jobs, down, posts, t0, H, gate), t0, H)
            print(f"{run:10} {name:34} {s['ex_wait']:10.1f} / {s['ex_flow']:9,.0f} {s['bg_wait']:14.1f} "
                  f"{s['miss']:10d} ({s['miss_min']:5.0f}) {s['breach']:12,.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
