#!/usr/bin/env python3
"""The capacity curve in steady state: the visits that arrive after a lab day's start-up and early enough to finish.

A lab day starts at 6 AM CT with the whole fleet at the depot and most of it needing a charge at once (the twin's run
start, `ottoq_tick_invariance_reset_fleet`): on the first lab days 91-106 visits "arrive" in the 6 AM hour and about half
of them wait past the contract's 30 minutes, which no overnight operation would ask of a depot. And a visit that arrives
in the last hour cannot finish before the day ends at 6 PM. So the comfortable-capacity question is read here on the
visits that arrive from 9 AM to 5 PM CT (by default): how many an hour, how many charged within the contract's queue
wait (each owner's own `max_queue_wait_minutes`), and how long a car spent from the gate to leaving ready.

A whole day (288 ticks) is read the same way on a window measured from the run's own start and end instead
(--skip-h 3 --tail-h 1: everything after the start-up and before the last hour), and with each hour's uptime beside it:
the share of the fleet out at work, against the share the work side asked for (`ottoq_deploy_target_now`).

Reads each kept replica (capacity_day.py --keep); appends one line per day to steady_state.jsonl and prints the table.
Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/steady_state.py [--from 9 --to 17] [db ...]
       /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/steady_state.py --skip-h 3 --tail-h 1 [db ...]
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
       WHERE CASE WHEN %(rel)s
                  THEN o.arrived_at >= (SELECT r2.sim_clock_start FROM ottoq_sim_runs r2, r WHERE r2.sim_run_id = r.run)
                                       + (%(skip)s * interval '1 hour')
                   AND o.arrived_at < (SELECT r2.sim_clock_current FROM ottoq_sim_runs r2, r WHERE r2.sim_run_id = r.run)
                                       - (%(tail)s * interval '1 hour')
                  ELSE EXTRACT(HOUR FROM o.arrived_at AT TIME ZONE 'America/Chicago') >= %(h0)s
                   AND EXTRACT(HOUR FROM o.arrived_at AT TIME ZONE 'America/Chicago') < %(h1)s END)
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

UPTIME_SQL = """
WITH r AS (SELECT sim_run_id AS run, sim_clock_start AS t0, sim_clock_current AS t1
             FROM ottoq_sim_runs WHERE run_by = 'ab_harness' ORDER BY started_at DESC LIMIT 1),
o AS (SELECT x.* FROM r, public.ottoq_visit_outcomes(r.run) x),
fleet AS (SELECT count(*)::numeric AS n FROM vehicles
           WHERE home_depot_id = '11111111-1111-1111-1111-111111111111' AND category = 'autonomous'),
h AS (SELECT g AS at FROM r, generate_series(r.t0 + (%(skip)s * interval '1 hour'), r.t1 - (%(tail)s * interval '1 hour'),
                                              interval '30 minutes') g)
SELECT round(avg(((SELECT n FROM fleet) - (SELECT count(*) FROM o WHERE o.arrived_at <= h.at
                                                 AND (o.departed_at IS NULL OR o.departed_at > h.at)))
                 / (SELECT n FROM fleet)) * 100, 1) AS out_pct,
       round(avg(public.ottoq_deploy_target_now(r.run, '11111111-1111-1111-1111-111111111111', h.at)
                 / (SELECT n FROM fleet)) * 100, 1) AS asked_pct,
       (SELECT n FROM fleet) AS fleet
  FROM h, r
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("dbs", nargs="*")
    ap.add_argument("--from", dest="h0", type=int, default=9, help="first arrival hour, CT")
    ap.add_argument("--to", dest="h1", type=int, default=17, help="arrivals before this hour, CT")
    ap.add_argument("--skip-h", type=float, help="instead: arrivals from this many hours after the run's start ...")
    ap.add_argument("--tail-h", type=float, default=1.0, help="... to this many hours before its end")
    ap.add_argument("--out", default=os.path.join(HERE, "steady_state.jsonl"))
    a = ap.parse_args()
    dbs = a.dbs
    if not dbs:
        with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname="postgres") as c:
            dbs = [r[0] for r in c.execute("SELECT datname FROM pg_database WHERE datname LIKE 'ottoq_cap_%' ORDER BY 1")]
    rel = a.skip_h is not None
    params = {"h0": a.h0, "h1": a.h1, "rel": rel, "skip": a.skip_h or 0.0, "tail": a.tail_h}
    head = (f"arrivals {a.skip_h:g} h after the start to {a.tail_h:g} h before the end" if rel
            else f"arrivals {a.h0}:00-{a.h1}:00 CT")
    print(f"{head} | visits | per hour | charged within contract | wait p50/p95 min | "
          f"gate to leaving p50/p95 min | left ready | fleet out / asked (%)")
    for db in dbs:
        try:
            with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=db) as c:
                if not c.execute("SELECT count(*) FROM ottoq_sim_runs WHERE run_by = 'ab_harness'").fetchone()[0]:
                    continue            # a day still running (its transaction not committed) or rolled back
                cols = None
                rows = []
                cur = c.execute(SQL, params)
                cols = [d.name for d in cur.description]
                rows = [dict(zip(cols, r)) for r in cur.fetchall()]
                t0, t1 = c.execute("SELECT sim_clock_start, sim_clock_current FROM ottoq_sim_runs "
                                   "WHERE run_by = 'ab_harness' ORDER BY started_at DESC LIMIT 1").fetchone()
                up = c.execute(UPTIME_SQL, {"skip": a.skip_h if rel else 3.0, "tail": a.tail_h}).fetchone()
        except psycopg.Error as e:
            print(f"{db}: {str(e).splitlines()[0]}")
            continue
        hours = ((t1 - t0).total_seconds() / 3600.0 - (a.skip_h or 0.0) - a.tail_h) if rel else (a.h1 - a.h0)
        rec = {"db": db, "window": ({"skip_h": a.skip_h, "tail_h": a.tail_h} if rel
                                    else {"from_hour_ct": a.h0, "to_hour_ct": a.h1}),
               "hours": round(hours, 2), "run_hours": round((t1 - t0).total_seconds() / 3600.0, 2),
               "uptime": {"fleet": float(up[2]), "out_pct": float(up[0]), "asked_pct": float(up[1])},
               "by_owner": {r["owner"]: {k: (float(v) if v is not None and k not in ("owner",) else v)
                                         for k, v in r.items() if k != "owner"} for r in rows}}
        with open(a.out, "a") as f:
            f.write(json.dumps(rec, default=str) + "\n")
        t = rec["by_owner"]["all"]
        pct = 100.0 * t["within_contract"] / t["charged"] if t["charged"] else float("nan")
        print(f"{db.removeprefix('ottoq_cap_')} | {t['visits']:.0f} | {t['visits'] / hours:.1f} | "
              f"{t['within_contract']:.0f}/{t['charged']:.0f} ({pct:.0f}%) | {t['wait_p50']}/{t['wait_p95']} | "
              f"{t['door_p50']}/{t['door_p95']} | {t['left_ready']:.0f} | "
              f"{rec['uptime']['out_pct']}/{rec['uptime']['asked_pct']}")


if __name__ == "__main__":
    main()
