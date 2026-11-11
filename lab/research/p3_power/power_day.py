#!/usr/bin/env python3
"""One lab day with 0810's power capture, optionally with a zone trip, and the 14 atoms of the arm.

  power_day.py --db ottoq_pw --seed 171717 --ticks 48 --out day.json [--trip TX-A1@20:90] [--step 2 --sim-start "2026-09-01 11:00:00+00"]

--trip NODE@TICK:MINUTES trips NODE after tick TICK for MINUTES sim-minutes (through
public.ottoq_twin_trip_power_node, the door 0810 adds). The arm is one transaction, as a certification arm is; it
is committed at the end so the study rows can be read afterwards. Lab only: it never connects to production.
"""
import argparse, json, sys, time
from pathlib import Path
import psycopg
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "engine" / "lib"))
from lab_run import Arm, ATOMS  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--db", required=True); ap.add_argument("--seed", type=int, default=171717)
ap.add_argument("--scenario", default="busy_day"); ap.add_argument("--ticks", type=int, default=48)
ap.add_argument("--trip"); ap.add_argument("--out", required=True)
ap.add_argument("--step", type=float, help="sim minutes per tick (default: the certification arm's 30)")
ap.add_argument("--sim-start", default=None)
a = ap.parse_args()
conn = psycopg.connect(f"host=/var/tmp port=55433 dbname={a.db} user=postgres")
arm = Arm(conn, a.seed, a.scenario) if not a.sim_start else Arm(conn, a.seed, a.scenario, sim_start=a.sim_start)
run = arm.start()
if a.step:  # as lab/research/p2_capacity/capacity_day.py sets a day's tick: time_scale 2 x minutes, 30-second ticks
    arm.q("UPDATE ottoq_sim_runs SET time_scale = %s, tick_interval_seconds = 30 WHERE sim_run_id = %s", (2 * a.step, run))
trip = None
if a.trip:
    node, rest = a.trip.split("@"); at, mins = rest.split(":"); trip = (node, int(at), float(mins))
res = {"db": a.db, "run": run, "seed": a.seed, "scenario": a.scenario, "ticks": a.ticks, "trip": a.trip}
t0 = time.time()
for k in range(1, a.ticks + 1):
    arm.tick(1)
    if trip and k == trip[1]:
        res["trip_result"] = arm.q("SELECT public.ottoq_twin_trip_power_node(%s::uuid, %s::text, %s::numeric, 'lab_power_day')",
                                   (run, trip[0], trip[2]))[0][0]
        print("trip:", json.dumps(res["trip_result"], default=str), flush=True)
    if k % max(8, a.ticks // 12) == 0:
        print(f"tick {k}/{a.ticks} {time.time()-t0:.0f}s", flush=True)
d = arm.digest()
res["atoms"] = {k: d[k] for k in ATOMS}
has = arm.q("SELECT to_regclass('public.ottoq_power_node_study') IS NOT NULL")[0][0]
arm.finish()
if has:
    res["one_line"] = arm.q("SELECT public.ottoq_power_one_line(%s, %s)", (arm.depot, run))[0][0]
conn.commit()
res["wall_s"] = round(time.time() - t0, 1); res["tick_s_mean"] = round(sum(arm.tick_seconds) / len(arm.tick_seconds), 2)
Path(a.out).write_text(json.dumps(res, indent=1, default=str))
print("done", res["wall_s"], "s")
