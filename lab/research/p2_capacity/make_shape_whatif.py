#!/usr/bin/env python3
"""Write a what-if (capacity_day.py --lab-sql) that gives the battery's day plan a typical day's shape of EV charging.

The day plan (0435, `ottoq_bess_day_plan`) forecasts the cars' charging over the rest of the day as the larger of what is
known (sessions under way, cars returning), the line already waiting (0444) and what the depot drew over the last hour.
Beyond the next hour or two that is persistence. The lab's battery bound found the money in the shape of the whole day
(`lab/research/p2_perfect_day/README.md`). This what-if adds a fourth floor, the EV charging another finished lab day drew
in the same half hour of the day, so the plan's own algorithm, unchanged otherwise, sees a typical day's shape. It is the
smallest form of the build (a learned profile, as the plan already reads the building's hourly median), measured with the
plan as it runs rather than with a linear program.

Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/make_shape_whatif.py --from-db ottoq_cap_normal_day_116_424242
   writes lab/research/p2_capacity/whatif_ev_shape_<from-db>.sql
"""
from __future__ import annotations

import argparse
import os

import psycopg

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
TWIN = "11111111-1111-1111-1111-111111111111"
HERE = os.path.dirname(os.path.abspath(__file__))
ANCHOR = "    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), COALESCE(v_queue[k], 0), v_ev_persist);   /* 0444 */"
PATCH = ("    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), COALESCE(v_queue[k], 0), v_ev_persist,   /* 0444 */\n"
         "                        COALESCE((SELECT s.ev_kw FROM lab.ev_shape s WHERE s.slot = floor(v_hf * 2)::int), 0));"
         "   /* lab what-if: a typical day's shape */")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from-db", required=True, help="the finished lab day whose EV charging is the shape")
    ap.add_argument("--out")
    a = ap.parse_args()
    with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=a.from_db) as c:
        run = c.execute("SELECT sim_run_id FROM ottoq_sim_runs WHERE run_by = 'ab_harness' "
                        "ORDER BY started_at DESC LIMIT 1").fetchone()[0]
        rows = c.execute("""SELECT floor((EXTRACT(HOUR FROM s.timestamp AT TIME ZONE 'America/Chicago') * 60
                                          + EXTRACT(MINUTE FROM s.timestamp AT TIME ZONE 'America/Chicago')) / 30)::int,
                                   round(avg(COALESCE(s.total_ev_charging_kw, 0))::numeric, 1)
                              FROM site_energy_snapshots s
                             WHERE s.sim_run_id = %s AND s.depot_id = %s
                             GROUP BY 1 ORDER BY 1""", (run, TWIN)).fetchall()
    out = a.out or os.path.join(HERE, f"whatif_ev_shape_{a.from_db.removeprefix('ottoq_cap_')}.sql")
    values = ",\n  ".join(f"({slot}, {kw})" for slot, kw in rows)
    anchor_sql = ANCHOR.replace("'", "''")
    patch_sql = PATCH.replace("'", "''")
    with open(out, "w") as f:
        f.write(f"""-- What-if for a lab day only (capacity_day.py --lab-sql), written by make_shape_whatif.py from {a.from_db}
-- (run {run}): the battery's day plan sees a typical day's shape of EV charging, the EV kW that day drew in each half
-- hour of the local day, as a fourth floor under its forecast. Nothing else in the plan changes.
CREATE SCHEMA IF NOT EXISTS lab;
CREATE TABLE IF NOT EXISTS lab.ev_shape (slot int PRIMARY KEY, ev_kw numeric NOT NULL);
TRUNCATE lab.ev_shape;
INSERT INTO lab.ev_shape (slot, ev_kw) VALUES
  {values};
DO $whatif$
DECLARE v_def text := pg_get_functiondef('public.ottoq_bess_day_plan'::regproc);
BEGIN
  IF (length(v_def) - length(replace(v_def, '{anchor_sql}', ''))) / length('{anchor_sql}') <> 1 THEN
    RAISE EXCEPTION 'what-if anchor not found exactly once in ottoq_bess_day_plan';
  END IF;
  EXECUTE replace(v_def, '{anchor_sql}', '{patch_sql}');
END
$whatif$;
""")
    print(out, len(rows), "half hours")


if __name__ == "__main__":
    main()
