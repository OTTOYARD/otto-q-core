#!/usr/bin/env python3
"""Write a finished lab day's load before the battery, step by step, as a forecast shape for battery_lp.py.

Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/make_load_shape.py --from-db ottoq_cap_normal_day_116_424242
   writes lab/research/p2_capacity/load_shape_<from-db>.json: {"from_db", "run", "step_min", "pre_kw": [...]}
"""
from __future__ import annotations

import argparse
import json
import os

import psycopg

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
TWIN = "11111111-1111-1111-1111-111111111111"
HERE = os.path.dirname(os.path.abspath(__file__))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from-db", required=True)
    ap.add_argument("--out")
    a = ap.parse_args()
    with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=a.from_db) as c:
        run = c.execute("SELECT sim_run_id::text FROM ottoq_sim_runs WHERE run_by = 'ab_harness' "
                        "ORDER BY started_at DESC LIMIT 1").fetchone()[0]
        rows = c.execute("""SELECT COALESCE(total_ev_charging_kw, 0) + COALESCE(building_load_kw, 0)
                                   + COALESCE(lighting_load_kw, 0) - COALESCE(solar_generation_kw, 0)
                              FROM site_energy_snapshots WHERE sim_run_id = %s AND depot_id = %s
                             ORDER BY timestamp""", (run, TWIN)).fetchall()
    out = a.out or os.path.join(HERE, f"load_shape_{a.from_db.removeprefix('ottoq_cap_')}.json")
    with open(out, "w") as f:
        json.dump({"from_db": a.from_db, "run": run, "step_min": 5, "pre_kw": [round(float(r[0]), 1) for r in rows]}, f)
    print(out, len(rows), "steps")


if __name__ == "__main__":
    main()
