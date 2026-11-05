#!/usr/bin/env python3
"""E1 acceptance test 2 -- forks (docs/FRONTIER_PLAN_2026-11-03.md, E1 "Done when" 2).

"An unchanged branch reproduces the original byte-for-byte, and a changed branch differs only
after the fork tick."

One lab arm (a certification arm: lib/lab_run.py) is ticked to the fork tick F inside one
transaction; a SAVEPOINT is taken; then, one after another, each branch runs to tick N, is
digested (the pair's 14 atoms, the arrival stream, per-tick digests of events, decisions and
commands) and rolled back to the savepoint:

  trunk      the arm as it is
  replay     the arm as it is, again (must equal trunk)
  changed    the arm with one decision rule changed at the fork: a run-scoped dial, by default
             charge_order_minutes = 0 (0642's charge-line key, the incumbent E6 will challenge,
             switched back to the order before it)

The transaction is rolled back at the end: the lab keeps nothing from the test.

    /var/tmp/ottoq_lab_venv/bin/python -I lab/engine/acceptance/forks.py --dsn DSN --out FILE.json
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import psycopg  # noqa: E402
from lab_run import Arm, compare  # noqa: E402


def branch(arm: Arm, fork_clocks: list, fork_secs: list, ticks_after: int, dial: tuple | None) -> dict:
    arm.clocks, arm.tick_seconds = list(fork_clocks), list(fork_secs)
    arm.q("SELECT set_config('ottoq.sim_run_id', %s, true)", (arm.run,))  # every branch sets it itself (0329/0421)
    if dial:
        arm.set_run_dial(dial[0], dial[1])
    t0 = time.perf_counter()
    arm.tick(ticks_after)
    d = arm.digest()
    d["wall_seconds_after_fork"] = round(time.perf_counter() - t0, 2)
    arm.q("ROLLBACK TO SAVEPOINT lab_fork")
    return d


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=171717)
    ap.add_argument("--ticks", type=int, default=12)
    ap.add_argument("--fork", type=int, default=6)
    ap.add_argument("--scenario", default="busy_day")
    ap.add_argument("--dial", default="charge_order_minutes=0", help="key=value set at run scope in the changed branch")
    a = ap.parse_args()
    key, _, val = a.dial.partition("=")
    started = datetime.now(timezone.utc)
    with psycopg.connect(a.dsn, autocommit=False) as conn:
        arm = Arm(conn, seed=a.seed, scenario=a.scenario)
        arm.start()
        arm.tick(a.fork)
        fork_clocks, fork_secs = list(arm.clocks), list(arm.tick_seconds)
        arm.q("SAVEPOINT lab_fork")
        trunk = branch(arm, fork_clocks, fork_secs, a.ticks - a.fork, None)
        replay = branch(arm, fork_clocks, fork_secs, a.ticks - a.fork, None)
        changed = branch(arm, fork_clocks, fork_secs, a.ticks - a.fork, (key, float(val)))
        conn.rollback()
    finished = datetime.now(timezone.utc)

    c_replay = compare(trunk, replay)
    c_changed = compare(trunk, changed)
    result = {
        "test": "E1 acceptance 2: forks", "started": started.isoformat(timespec="seconds"),
        "finished": finished.isoformat(timespec="seconds"),
        "seed": a.seed, "scenario": a.scenario, "ticks": a.ticks, "fork_tick": a.fork, "changed_dial": {key: val},
        "replay_vs_trunk": c_replay, "changed_vs_trunk": c_changed,
        "verdict": {
            "unchanged_branch_reproduces": not c_replay["disagreeing_atoms"] and c_replay["first_tick_that_differs"] is None,
            "unchanged_branch_reproduces_except_minted_robot_leg_id":
                set(c_replay["disagreeing_atoms"]) <= {"end_state"} and c_replay["end_state_equal_without_robot_leg_id"]
                and c_replay["first_tick_that_differs"] is None,
            "changed_branch_differs_only_after_fork":
                c_changed["first_tick_that_differs"] is not None and c_changed["first_tick_that_differs"] > a.fork,
        },
        "branches": {"trunk": trunk, "replay": replay, "changed": changed},
    }
    with open(a.out, "w") as fh:
        json.dump(result, fh, indent=1, default=str)
        fh.write("\n")
    print(json.dumps({k: result[k] for k in ("replay_vs_trunk", "changed_vs_trunk", "verdict")}, indent=1, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
