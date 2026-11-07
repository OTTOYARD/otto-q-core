#!/usr/bin/env python3
"""The production battery planner's end-to-end lab template (LAB ONLY; run from the repository root).

ottoq_lab_0804 is the 0801 template with 0799, 0803 and 0804 applied in order. This copies it to ottoq_lab_0804m and gives
it what production would have learned: every in-tick row of 0803's forecast log from the six 36-hour base days run with the
log on (<seed>_b36log, each car for car its b36 base day), and one model per seed fitted on the other five seeds' rows
(ottoq_bess_forecast_refit, folds by run, the 80th percentile, lambda 10), so a day never reads a forecast that saw it.
Then it writes the job list: each seed's 36-hour day with the planner asked every tick through the lab's stand-in for the
edge function (capacity_day.py --planner-service, a local ottoq-intelligence) and followed under 0799's rules, on its own
held-out model (--bess-forecast-model), billed from 6 PM day 1 against its b36 base day.

Usage: python -I lab/research/p2_capacity/planner_e2e_template.py [--service http://127.0.0.1:8088] [--tag p36e2e]
                                                                  [--beyond 0|1]
"""
from __future__ import annotations

import argparse
import json

import psycopg

HOST, PORT = "/var/tmp", 55433
TWIN = "11111111-1111-1111-1111-111111111111"
SEEDS = ["171717", "424242", "616161", "818181", "919191", "373737"]
COLS = ("depot_id, sim_run_id, run_by, data_source, tick_seq, sim_clock, snapshot_at, ev_drawn_kw, site_base_kw, "
        "site_solar_kw, grid_kw, ev_persist_kw, on_charger_kw, known_kw, queue_kw, base_kw, solar_kw, rule_ev_kw, logged_at")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--service", default="http://127.0.0.1:8088")
    ap.add_argument("--tag", default="p36e2e")
    ap.add_argument("--beyond", type=int, choices=(0, 1), default=0)
    ap.add_argument("--template", default="ottoq_lab_0804m")
    ap.add_argument("--log-from", metavar="DB",
                    help="copy the six in-tick logs from this database (a template or a replica cloned from one) instead of "
                         "the b36log replicas; each seed's run is the one its held-out model left out")
    a = ap.parse_args()
    with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname="postgres", autocommit=True) as admin:
        if not admin.execute("SELECT 1 FROM pg_database WHERE datname = %s", (a.template,)).fetchone():
            admin.execute(f"CREATE DATABASE {a.template} TEMPLATE ottoq_lab_0804")
    runs, models = {}, {}
    with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=a.template, autocommit=True) as dst:
        have = {str(r[0]) for r in dst.execute("SELECT DISTINCT sim_run_id FROM ottoq_bess_forecast_log")}
        if a.log_from:
            with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=a.log_from) as src:
                every = {str(r[0]) for r in src.execute("SELECT DISTINCT sim_run_id FROM ottoq_bess_forecast_log")}
                for note, fit_runs in src.execute("""SELECT note, runs FROM ottoq_bess_forecast_models
                                                    WHERE note LIKE 'lab: the six in-tick 36-hour logs less %%'"""):
                    left = every - {str(x) for x in fit_runs}
                    if len(left) == 1:
                        runs[note.rsplit(" ", 1)[1]] = left.pop()
                if not have:
                    rows = src.execute(f"SELECT {COLS} FROM ottoq_bess_forecast_log ORDER BY sim_run_id, sim_clock").fetchall()
                    with dst.cursor() as cur:
                        cur.executemany(f"INSERT INTO ottoq_bess_forecast_log ({COLS}) VALUES ({', '.join(['%s'] * 19)})", rows)
                    print(f"copied {len(rows)} in-tick rows from {a.log_from}; runs by seed {runs}")
        for s in ([] if a.log_from else SEEDS):
            with psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=f"ottoq_cap_normal_day_116_{s}_b36log") as src:
                rows = src.execute(f"SELECT {COLS} FROM ottoq_bess_forecast_log ORDER BY sim_clock").fetchall()
            runs[s] = str(rows[0][1])
            if runs[s] in have:
                continue
            with dst.cursor() as cur:
                cur.executemany(f"INSERT INTO ottoq_bess_forecast_log ({COLS}) VALUES ({', '.join(['%s'] * 19)})", rows)
            print(f"{s}: {len(rows)} in-tick rows from run {runs[s][:8]}")
        for s in SEEDS:
            note = f"lab: the six in-tick 36-hour logs less {s}"
            got = dst.execute("SELECT model_id FROM ottoq_bess_forecast_models WHERE note = %s ORDER BY model_id DESC LIMIT 1",
                              (note,)).fetchone()
            if got:
                models[s] = got[0]
                continue
            res = dst.execute("SELECT public.ottoq_bess_forecast_refit(%s, 0.8, 10, '28 days', %s, %s::uuid[], 'run')",
                              (TWIN, note, [runs[o] for o in SEEDS if o != s])).fetchone()[0]
            models[s] = res["model_id"]
            m = dst.execute("SELECT per_half_hour FROM ottoq_bess_forecast_models WHERE model_id = %s", (models[s],)).fetchone()[0]
            print(f"less {s}: model {models[s]} usable {res['usable']}, {res['examples']} examples; out of sample h0 "
                  f"{m[0]['cv']['mae_kw']} kW (the rule {m[0]['cv']['rule_mae_kw']}), h7 {m[7]['cv']['mae_kw']} kW, "
                  f"band h0 {m[0]['offset_kw']:.0f} kW")
    lines = [
        f"# The production battery planner end to end in the lab (2026-11-06; LAB ONLY; LAB_DB={a.template}: the 0801 template",
        "# + 0799 + 0803 + 0804, the six in-tick 36-hour logs and one held-out model per seed). Each day asks the planner every tick",
        "# (bess_planner_enabled) through capacity_day.py's stand-in for the edge function (a local ottoq-intelligence carrying",
        "# POST /optimize/battery-plan), follows a landed plan under 0799 (energy_mpc_follow), and is set against its b36 base day",
        f"# car for car, billed from 6 PM day 1. Beyond the forecast's 4 hours: the learned day's {'quantile' if a.beyond else 'mean'}.",
    ]
    for s in SEEDS:
        lines.append(f"normal_day_116_{s}_{a.tag}|--fleet 116 --scenario normal_day --seed {s} --ticks 432 --run-hours 36 "
                     f"--dial bess_plan_bill_from_min=720 --dial bess_planner_enabled=1 --dial energy_mpc_follow=1 "
                     f"--dial bess_planner_beyond={a.beyond} --planner-service {a.service} "
                     f"--bess-forecast-model {models[s]} --tag {a.tag}")
    path = f"lab/research/p2_capacity/jobs_2026-11-06_{a.tag}.txt"
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {path}: {json.dumps(models)}")


if __name__ == "__main__":
    main()
