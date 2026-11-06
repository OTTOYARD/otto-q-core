"""Usage (repo root): python -I lab/research/p2_capacity/forecast_sql_refit_parity.py DB. Set the SQL refit (ottoq_bess_forecast_refit) against forecast_learn.py's saved models, seed by seed (LAB ONLY)."""
import json, sys
import psycopg
TWIN = "11111111-1111-1111-1111-111111111111"
D = "lab/research/p2_capacity"
rows = [json.loads(l) for l in open(f"{D}/forecast_audit_36h.jsonl") if l.strip()]
runs = {}
for r in rows:
    runs[r["db"].split("_")[-2]] = r["run"]
out = {}
with psycopg.connect(host="/var/tmp", port=55433, user="postgres", dbname=sys.argv[1], autocommit=True) as c:
    for seed in sorted(runs):
        others = [runs[s] for s in runs if s != seed]
        res = c.execute("SELECT public.ottoq_bess_forecast_refit(%s, 0.8, 10, '28 days', %s, %s::uuid[], 'run')",
                        (TWIN, f"lab: the 36-hour base days less {seed}", others)).fetchone()[0]
        m = c.execute("SELECT per_half_hour, n_examples, usable FROM ottoq_bess_forecast_models WHERE model_id = %s",
                      (res["model_id"],)).fetchone()
        py = json.load(open(f"{D}/forecast_model_36h_q80cv_ex{seed}.json"))
        worst = {"w": 0, "mu": 0, "sd": 0, "off": 0, "n": 0}
        for a, b in zip(m[0], py["per_half_hour"]):
            worst["n"] = max(worst["n"], abs(a["n"] - b["n"]))
            for k in ("w", "mu", "sd"):
                worst[k] = max(worst[k], max(abs(x - y) for x, y in zip(a[k], b[k])))
            worst["off"] = max(worst["off"], abs(a["offset_kw"] - b["offset_kw"]))
        out[seed] = res["model_id"]
        print(f"ex {seed}: model {res['model_id']} usable {m[2]} examples {m[1]}; largest differences from the Python fit: "
              f"n {worst['n']}, w {worst['w']:.2e}, mu {worst['mu']:.2e}, sd {worst['sd']:.2e}, offset {worst['off']:.2e} kW")
print(json.dumps(out))
