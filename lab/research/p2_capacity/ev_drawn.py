"""The EV charging a lab day drew, every 5 minutes, from its kept replica, or from the committed copy once read (LAB ONLY).

The forecast graders and the learned forecast (`forecast_grade.py`, `forecast_learn.py`) set each forecast against what the
depot then drew. That series lives in the day's replica (site_energy_snapshots), and a replica is lab scratch: dropped to
free the disk, it would take the training days with it. So the first read of a day writes its series to
`ev_drawn.jsonl` beside this file (a few kB a day), and every later read takes it from there.
"""
from __future__ import annotations

import datetime as dt
import json
import os

import psycopg

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "ev_drawn.jsonl")
TWIN = "11111111-1111-1111-1111-111111111111"


def _cached() -> dict:
    out = {}
    if os.path.exists(CACHE):
        with open(CACHE) as f:
            for line in f:
                if line.strip():
                    d = json.loads(line)
                    out[(d["db"], d["run"])] = d
    return out


def drawn(db: str, run: str) -> list[tuple[dt.datetime, float]]:
    """[(snapshot time, EV kW)] in time order: the committed copy, else the replica (and the copy is written)."""
    d = _cached().get((db, run))
    if d is None:
        with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=db) as c:
            rows = c.execute("""SELECT timestamp, COALESCE(total_ev_charging_kw, 0) FROM site_energy_snapshots
                                 WHERE sim_run_id = %s AND depot_id = %s ORDER BY timestamp""", (run, TWIN)).fetchall()
        d = {"db": db, "run": run, "t": [t.isoformat() for t, _ in rows], "kw": [round(float(k), 3) for _, k in rows]}
        with open(CACHE, "a") as f:
            f.write(json.dumps(d) + "\n")
    return [(dt.datetime.fromisoformat(t), float(k)) for t, k in zip(d["t"], d["kw"])]
