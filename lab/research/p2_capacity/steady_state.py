#!/usr/bin/env python3
"""The capacity curve in steady state: the visits that arrive after a lab day's start-up and early enough to finish.

A lab day starts at 6 AM CT with the whole fleet at the depot and most of it needing a charge at once (the twin's run
start, `ottoq_tick_invariance_reset_fleet`): on the first lab days 91-106 visits "arrive" in the 6 AM hour and about half
of them wait past the contract's 30 minutes, which no overnight operation would ask of a depot. And a visit that arrives
in the last hour cannot finish before the day ends at 6 PM. So the comfortable-capacity question is read here on the
visits that arrive from 9 AM to 5 PM CT (by default): how many an hour, how many charged within the contract's queue
wait (each owner's own `max_queue_wait_minutes`), and how long a car spent from the gate to leaving ready.

Reads each kept replica (capacity_day.py --keep); appends one line per day to steady_state.jsonl and prints the table.
Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/steady_state.py [--from 9 --to 17] [db ...]
       (no db: every ottoq_cap_* replica holding a finished day)
"""
from __future__ import annotations

import argparse
import json
import os

import psycopg

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
HERE = os.path.dirname(os.path.abspath(__file__))

SQL = """
WITH r AS (SELECT sim_run_id AS run FROM ottoq_sim_runs WHERE run_by = 'ab_harness' ORDER BY started_at DESC LIMIT 1),
o AS (SELECT x.* FROM r, public.ottoq_visit_outcomes(r.run) x),
sla AS (SELECT DISTINCT ON (s.fleet_operator_id) s.fleet_operator_id, s.max_queue_wait_minutes
          FROM ottoq_fleet_operator_slas s WHERE s.status = 'active' ORDER BY s.fleet_operator_id, s.version DESC),
w AS (SELECT o.*, fo.name AS owner, sla.max_queue_wait_minutes AS contract_wait,
             (SELECT min(s.started_at) FROM ocpp_sessions s, r
               WHERE s.sim_run_id = r.run AND s.vehicle_id = o.vehicle_id AND s.started_at >= o.arrived_at
                 AND (o.departed_at IS NULL OR s.started_at <= o.departed_at)) AS plugged_at
        FROM o JOIN vehicles v ON v.id = o.vehicle_id
        JOIN fleet_operators fo ON fo.id = v.fleet_operator_id
        LEFT JOIN sla ON sla.fleet_operator_id = v.fleet_operator_id
       WHERE EXTRACT(HOUR FROM o.arrived_at AT TIME ZONE 'America/Chicago') >= %(h0)s
         AND EXTRACT(HOUR FROM o.arrived_at AT TIME ZONE 'America/Chicago') < %(h1)s)
SELECT COALESCE(owner, 'all') AS owner, count(*) AS visits,
       count(*) FILTER (WHERE departed_at IS NOT NULL) AS left_ready,
       count(plugged_at) AS charged,
       count(*) FILTER (WHERE plugged_at IS NOT NULL
                          AND extract(epoch FROM (plugged_at - arrived_at)) / 60.0 <= contract_wait) AS within_contract,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (plugged_at - arrived_at)) / 60.0)::numeric, 1) AS wait_p50,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY extract(epoch FROM (plugged_at - arrived_at)) / 60.0)::numeric, 1) AS wait_p95,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY door_min) FILTER (WHERE departed_at IS NOT NULL)::numeric, 1) AS door_p50,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY door_min) FILTER (WHERE departed_at IS NOT NULL)::numeric, 1) AS door_p95
  FROM w GROUP BY GROUPING SETS ((owner), ()) ORDER BY owner NULLS FIRST
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("dbs", nargs="*")
    ap.add_argument("--from", dest="h0", type=int, default=9, help="first arrival hour, CT")
    ap.add_argument("--to", dest="h1", type=int, default=17, help="arrivals before this hour, CT")
    ap.add_argument("--out", default=os.path.join(HERE, "steady_state.jsonl"))
    a = ap.parse_args()
    dbs = a.dbs
    if not dbs:
        with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname="postgres") as c:
            dbs = [r[0] for r in c.execute("SELECT datname FROM pg_database WHERE datname LIKE 'ottoq_cap_%' ORDER BY 1")]
    hours = a.h1 - a.h0
    print(f"arrivals {a.h0}:00-{a.h1}:00 CT | visits | per hour | charged within contract | wait p50/p95 min | "
          f"gate to leaving p50/p95 min | left ready")
    for db in dbs:
        try:
            with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=db) as c:
                if not c.execute("SELECT count(*) FROM ottoq_sim_runs WHERE run_by = 'ab_harness'").fetchone()[0]:
                    continue            # a day still running (its transaction not committed) or rolled back
                cols = None
                rows = []
                cur = c.execute(SQL, {"h0": a.h0, "h1": a.h1})
                cols = [d.name for d in cur.description]
                rows = [dict(zip(cols, r)) for r in cur.fetchall()]
        except psycopg.Error as e:
            print(f"{db}: {str(e).splitlines()[0]}")
            continue
        rec = {"db": db, "from_hour_ct": a.h0, "to_hour_ct": a.h1,
               "by_owner": {r["owner"]: {k: (float(v) if v is not None and k not in ("owner",) else v)
                                         for k, v in r.items() if k != "owner"} for r in rows}}
        with open(a.out, "a") as f:
            f.write(json.dumps(rec, default=str) + "\n")
        t = rec["by_owner"]["all"]
        pct = 100.0 * t["within_contract"] / t["charged"] if t["charged"] else float("nan")
        print(f"{db.removeprefix('ottoq_cap_')} | {t['visits']:.0f} | {t['visits'] / hours:.1f} | "
              f"{t['within_contract']:.0f}/{t['charged']:.0f} ({pct:.0f}%) | {t['wait_p50']}/{t['wait_p95']} | "
              f"{t['door_p50']}/{t['door_p95']} | {t['left_ready']:.0f}")


if __name__ == "__main__":
    main()
