#!/usr/bin/env python3
"""E1 acceptance test 3 -- throughput (docs/FRONTIER_PLAN_2026-11-03.md, E1 "Done when" 3).

"Simulated depot-days per hour is measured and reported. It is the first number the Lab owes."

A depot-day here is 24 simulated hours of the twin depot: one certification arm of 48 ticks at
30 sim-minutes a tick (lib/lab_run.py), unpaced. The test runs

  1. one arm alone (a single stream), then
  2. N arms at once, each in its own replica database cloned from the lab database
     (lib/lab_run.py clone_database: CREATE DATABASE ... TEMPLATE plus the template's database-level settings),
     so parallel arms never share the depot's rows and all run with production's session settings,

and reports wall time per arm, sim-hours per wall-hour and depot-days per wall-hour. Every arm
is rolled back when it has been timed and digested: nothing is kept. The replicas are dropped.

    /var/tmp/ottoq_lab_venv/bin/python -I lab/engine/acceptance/throughput.py --dsn-base "host=/var/tmp port=55433 user=postgres" --out FILE.json
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import sys
import threading
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import psycopg  # noqa: E402
from lab_run import Arm, clone_database  # noqa: E402

TICK_SIM_MINUTES = 30  # tick_interval_seconds 30 x time_scale 60, fixed playback (ottoq_sim_advance_tick_world)


def one_arm(dsn: str, seed: int, ticks: int, out: dict) -> None:
    t0 = time.perf_counter()
    with psycopg.connect(dsn, autocommit=False) as conn:
        arm = Arm(conn, seed=seed)
        arm.start()
        t1 = time.perf_counter()
        arm.tick(ticks)
        t2 = time.perf_counter()
        h_evt = arm.q("SELECT public.ottoq_ab_arm_atoms(%s, %s)->>'h_evt'", (arm.depot, arm.run))[0][0]
        conn.rollback()
    out.update(seed=seed, ticks=ticks, start_seconds=round(t1 - t0, 2), tick_seconds=round(t2 - t1, 2),
               total_seconds=round(time.perf_counter() - t0, 2), h_evt=h_evt,
               per_tick_seconds=[round(x, 3) for x in arm.tick_seconds])


def rates(sim_hours: float, wall_seconds: float) -> dict:
    per_hour = sim_hours / (wall_seconds / 3600.0)
    return {"sim_hours": sim_hours, "wall_seconds": round(wall_seconds, 1),
            "sim_hours_per_wall_hour": round(per_hour, 1), "depot_days_per_wall_hour": round(per_hour / 24.0, 2)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn-base", required=True, help="libpq keywords without dbname")
    ap.add_argument("--db", default="ottoq_lab")
    ap.add_argument("--out", required=True)
    ap.add_argument("--ticks", type=int, default=48)
    ap.add_argument("--replicas", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--seed", type=int, default=171717)
    a = ap.parse_args()
    started = datetime.now(timezone.utc)
    sim_hours_per_arm = a.ticks * TICK_SIM_MINUTES / 60.0

    # 1. a single stream, in the lab database itself
    single: dict = {}
    t0 = time.perf_counter()
    one_arm(f"{a.dsn_base} dbname={a.db}", a.seed, a.ticks, single)
    single_wall = time.perf_counter() - t0

    # 2. N replicas in parallel
    names = [f"{a.db}_r{i}" for i in range(a.replicas)]
    clone_seconds = []
    with psycopg.connect(f"{a.dsn_base} dbname=postgres", autocommit=True) as admin:
        for n in names:
            clone_seconds.append(round(clone_database(admin, a.db, n), 2))
    results = [dict() for _ in names]
    threads = [threading.Thread(target=one_arm, args=(f"{a.dsn_base} dbname={n}", a.seed + i, a.ticks, results[i]))
               for i, n in enumerate(names)]
    t0 = time.perf_counter()
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    parallel_wall = time.perf_counter() - t0
    with psycopg.connect(f"{a.dsn_base} dbname=postgres", autocommit=True) as admin:
        for n in names:
            admin.execute(f"DROP DATABASE IF EXISTS {n} WITH (FORCE)")
    failed = [i for i, r in enumerate(results) if "total_seconds" not in r]
    if failed:
        raise SystemExit(f"replica arms failed: {failed}")

    result = {
        "test": "E1 acceptance 3: throughput", "started": started.isoformat(timespec="seconds"),
        "finished": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "machine": {"cpus": os.cpu_count(), "platform": platform.platform()},
        "arm": {"scenario": "busy_day", "ticks": a.ticks, "tick_sim_minutes": TICK_SIM_MINUTES,
                "sim_hours": sim_hours_per_arm},
        "single_stream": {**rates(sim_hours_per_arm, single_wall), "arm": single},
        "parallel": {"replicas": a.replicas, **rates(sim_hours_per_arm * a.replicas, parallel_wall),
                     "clone_seconds": clone_seconds, "arms": results},
    }
    with open(a.out, "w") as fh:
        json.dump(result, fh, indent=1)
        fh.write("\n")
    print(json.dumps({"single_stream": {k: v for k, v in result["single_stream"].items() if k != "arm"},
                      "parallel": {k: v for k, v in result["parallel"].items() if k != "arms"}}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
