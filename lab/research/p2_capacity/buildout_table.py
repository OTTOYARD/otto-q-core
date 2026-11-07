#!/usr/bin/env python3
"""The build-out table (LAB ONLY): for whole lab days (288 ticks), each day's site, visits served, the share charged
within the contract wait from the gate and the waits (steady_state.py's readers, arrivals 3 h after the start to 1 h
before the end), the 1-7 PM share of the fleet out at work (uptime_by_hour.sql), how busy the service bays and posts were,
and the wall the engine's constraint board named most. Reads results.jsonl for the day's record and each kept replica.

Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/buildout_table.py <db> [<db> ...]
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
from collections import Counter

import psycopg

HERE = os.path.dirname(os.path.abspath(__file__))
HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
_spec = importlib.util.spec_from_file_location("steady_state", os.path.join(HERE, "steady_state.py"))
ss = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ss)


def record(db: str) -> dict | None:
    rec = None
    for line in open(os.path.join(HERE, "results.jsonl")):
        if line.strip():
            d = json.loads(line)
            if d.get("db") == db and d.get("ticks") == 288 and not d.get("error"):
                rec = d
    return rec


def main() -> None:
    print("| site (service bays / posts) | fleet, seed | visits served | visits an hour | within the contract wait, from the gate "
          "| wait p50 / p95 from the gate | 1-7 PM out at work (asked) | service bays busy | posts busy | the wall named most (of 48) |")
    print("|---|---|---:|---:|---:|---:|---:|---:|---:|---|")
    uptime_sql = open(os.path.join(HERE, "uptime_by_hour.sql")).read()
    for db in sys.argv[1:]:
        d = record(db)
        if d is None:
            print(f"| {db}: no whole day in results.jsonl |")
            continue
        added = d.get("added_stalls") or {}
        bays, posts = 2 + int(added.get("service_bay", 0)), 30 + int(added.get("dcfc", 0))
        res = {r["kind"]: r for r in d.get("resources") or []}
        walls = Counter((w.get("wall") or {}).get("resource") if isinstance(w.get("wall"), dict) else w.get("wall")
                        for w in d.get("walls") or [] if "error" not in w)
        with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=db) as c:
            cur = c.execute(ss.SQL, {"h0": 9, "h1": 17, "rel": True, "skip": 3.0, "tail": 1.0})
            cols = [x.name for x in cur.description]
            t = next(dict(zip(cols, r)) for r in cur.fetchall() if r[0] == "all")
            t0, t1 = c.execute("SELECT sim_clock_start, sim_clock_current FROM ottoq_sim_runs WHERE run_by = 'ab_harness' "
                               "ORDER BY started_at DESC LIMIT 1").fetchone()
            hrs = [r for r in c.execute(uptime_sql).fetchall() if r[0] in ("13", "14", "15", "16", "17", "18", "19")]  # 1 PM through the 7 PM hour, as the README reads it
        hours = (t1 - t0).total_seconds() / 3600.0 - 4.0
        out = sum(float(r[1]) for r in hrs) / len(hrs) if hrs else float("nan")
        asked = sum(float(r[2]) for r in hrs) / len(hrs) if hrs else float("nan")
        pct = 100.0 * float(t["within_contract"]) / float(t["charged"]) if t["charged"] else float("nan")
        top = ", ".join(f"{k} {n}" for k, n in walls.most_common(2))
        print(f"| {bays} / {posts} | {d['fleet']}, {d['seed']} | {d['scorecard']['throughput']['visits_served']} "
              f"| {float(t['visits']) / hours:.1f} | {pct:.0f}% | {t['wait_p50']} / {t['wait_p95']} min "
              f"| {out:.0f}% ({asked:.0f}%) | {res.get('service_bay', {}).get('busy_pct')}% | {res.get('dcfc', {}).get('busy_pct')}% | {top} |")


if __name__ == "__main__":
    main()
