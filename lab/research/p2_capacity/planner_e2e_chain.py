#!/usr/bin/env python3
"""How the production battery planner's chain behaved in the lab's end-to-end days (LAB ONLY; run from the repository root).

For each p36e2e day (and any other tag given): how many plans the engine asked for, landed, superseded on arrival or
failed; the round trip and the solve time; the share of ticks the battery followed a plan (mode mpc_follow), and every
other mode it was run in; the ledger's rows; and the battery's charge at 6 PM day 1, when the billed window opens.

Usage: python -I lab/research/p2_capacity/planner_e2e_chain.py [--tag p36e2e] [SEED ...]
"""
from __future__ import annotations

import argparse
import json

import psycopg

HOST, PORT = "/var/tmp", 55433
SEEDS = ["171717", "424242", "616161", "818181", "919191", "373737"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("seeds", nargs="*", default=SEEDS)
    ap.add_argument("--tag", default="p36e2e")
    a = ap.parse_args()
    results = {}
    with open("lab/research/p2_capacity/results.jsonl") as f:
        for line in f:
            if line.strip():
                d = json.loads(line)
                results[d["db"]] = d
    tot = {"asked": 0, "ready_or_superseded": 0, "failed": 0, "pending": 0, "ticks": 0, "follow": 0}
    for s in a.seeds:
        db = f"ottoq_cap_normal_day_116_{s}_{a.tag}"
        r = results.get(db)
        if not r:
            print(f"{s}: not finished")
            continue
        with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=db) as c:
            states = dict(c.execute("""SELECT plan_state, count(*) FROM ottoq_energy_plan WHERE source = 'bess_planner'
                                        GROUP BY 1""").fetchall())
            lat = c.execute("""SELECT round(avg(latency_ms)), max(latency_ms), round(avg((detail->>'solve_ms')::numeric), 1),
                                      max((detail->>'solve_ms')::numeric)
                                 FROM ottoq_energy_plan WHERE source = 'bess_planner' AND plan_state <> 'pending'""").fetchone()
            modes = dict(c.execute("""SELECT COALESCE(reason->>'mode', '?'), count(*) FROM ottoq_energy_commands
                                       WHERE command_type = 'bess_setpoint_kw' GROUP BY 1 ORDER BY 2 DESC""").fetchall())
            ledger = c.execute("""SELECT count(*), count(*) FILTER (WHERE outcome = 'answered') FROM ottoq_model_call_ledger
                                   WHERE provider = 'intelligence_battery_planner' AND role = 'planner'""").fetchone()
            soc6 = c.execute("""SELECT (reason->>'soc_pct')::numeric FROM ottoq_energy_commands c JOIN ottoq_sim_runs r
                                   ON r.sim_run_id = c.sim_run_id
                                 WHERE c.command_type = 'bess_setpoint_kw' AND c.issued_at > r.sim_clock_start + interval '12 hours'
                                 ORDER BY c.issued_at LIMIT 1""").fetchone()
            errors = dict(c.execute("""SELECT detail->>'error', count(*) FROM ottoq_energy_plan WHERE source = 'bess_planner'
                                        AND plan_state = 'failed' GROUP BY 1""").fetchall())
        asked = sum(states.values())
        ticks = sum(modes.values())
        follow = modes.get("mpc_follow", 0)
        tot["asked"] += asked
        tot["ready_or_superseded"] += states.get("ready", 0) + states.get("superseded", 0)
        tot["failed"] += states.get("failed", 0)
        tot["pending"] += states.get("pending", 0)
        tot["ticks"] += ticks
        tot["follow"] += follow
        print(f"{s}: asked {asked}, landed {states.get('ready', 0) + states.get('superseded', 0)}, failed {states.get('failed', 0)} "
              f"{errors or ''}, pending at the end {states.get('pending', 0)}; round trip mean {lat[0]} ms (max {lat[1]}), "
              f"solve mean {lat[2]} ms (max {lat[3]}); followed a plan on {follow} of {ticks} ticks; other modes "
              f"{ {k: v for k, v in modes.items() if k != 'mpc_follow'} }; ledger {ledger[1]} answered of {ledger[0]}; "
              f"battery at 6 PM day 1 {soc6[0] if soc6 else '?'}%; planner_service {r.get('planner_service')}")
    if tot["ticks"]:
        print(f"all: asked {tot['asked']}, landed {tot['ready_or_superseded']}, failed {tot['failed']}, pending at the end "
              f"{tot['pending']}; followed a plan on {tot['follow']} of {tot['ticks']} ticks ({tot['follow'] / tot['ticks']:.1%})")


if __name__ == "__main__":
    main()
