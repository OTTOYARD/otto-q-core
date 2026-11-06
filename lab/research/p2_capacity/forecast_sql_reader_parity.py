"""Usage (repo root): python -I lab/research/p2_capacity/forecast_sql_reader_parity.py REPLICA MODEL_JSON. The SQL forecast reader (ottoq_bess_learned_forecast) against battery_lp.py's _learned_fc on one replica's state (LAB ONLY)."""
import json, sys, datetime as dt
sys.path.insert(0, "lab/research/p2_capacity")
import psycopg
from battery_lp import BatteryLP
TWIN = "11111111-1111-1111-1111-111111111111"
db, model_path = sys.argv[1], sys.argv[2]
with psycopg.connect(host="/var/tmp", port=55433, user="postgres", dbname=db) as c:
    run = c.execute("SELECT sim_run_id::text FROM ottoq_sim_runs WHERE run_by = 'ab_harness' ORDER BY started_at DESC LIMIT 1").fetchone()[0]
    py = json.load(open(model_path))
    mid = c.execute("""INSERT INTO ottoq_bess_forecast_models (depot_id, note, usable, quantile, lam, fold_by, runs, n_folds,
                         n_examples, features, per_half_hour) VALUES (%s, 'the Python model', true, 0.8, 10, 'run', '{}', 5, 0,
                         %s, %s) RETURNING model_id""", (TWIN, py["features"], json.dumps(py["per_half_hour"]))).fetchone()[0]
    lp = BatteryLP(c, run, 5.0, 432, [0.0] * 432, learned=model_path)
    clk0 = c.execute("SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s", (run,)).fetchone()[0]
    worst = 0.0
    for back_h in (0, 3, 7, 11, 15, 19):   # the evaluator at several clocks over the run's last day (sessions as they stand)
        clk = clk0 - dt.timedelta(hours=back_h)
        c.execute("UPDATE ottoq_sim_runs SET sim_clock_current = %s WHERE sim_run_id = %s", (clk, run))
        pyfc = lp._learned_fc(0, [0.0] * 48)
        pyhh = [pyfc[6 * h] for h in range(8)]
        sq = c.execute("SELECT public.ottoq_bess_learned_forecast(%s, %s, %s, NULL, %s)", (run, TWIN, clk, mid)).fetchone()[0]
        d = max(abs(a - b) for a, b in zip(pyhh, sq["pre_upper_kw"]))
        worst = max(worst, d)
        print(clk, "python", [round(x) for x in pyhh], "sql", [round(x) for x in sq["pre_upper_kw"]], f"max diff {d:.2f} kW")
    c.rollback()
    print(f"largest difference {worst:.2f} kW")
