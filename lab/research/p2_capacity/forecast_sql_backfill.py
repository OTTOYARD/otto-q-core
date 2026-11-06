"""Usage (repo root): python -I lab/research/p2_capacity/forecast_sql_backfill.py AUDIT.jsonl TEMPLATE_DB. Backfill ottoq_bess_forecast_log in a lab template from the 36-hour audit (forecast_audit_36h.jsonl) and each day's kept
replica's site snapshots, so the SQL refit can be set against forecast_learn.py on the same examples (LAB ONLY)."""
import json, sys
import psycopg
TWIN = "11111111-1111-1111-1111-111111111111"
audit, target = sys.argv[1], sys.argv[2]
rows = [json.loads(l) for l in open(audit) if l.strip()]
snaps = {}
for db in sorted({r["db"] for r in rows}):
    with psycopg.connect(host="/var/tmp", port=55433, user="postgres", dbname=db) as c:
        for run, t, ev, base, solar, grid, ds in c.execute("""
                SELECT sim_run_id, timestamp, COALESCE(total_ev_charging_kw,0), COALESCE(building_load_kw,0)+COALESCE(lighting_load_kw,0),
                       COALESCE(solar_generation_kw,0), COALESCE(grid_import_kw,0)-COALESCE(grid_export_kw,0), data_source
                  FROM site_energy_snapshots WHERE depot_id = %s ORDER BY timestamp""", (TWIN,)):
            snaps.setdefault(str(run), []).append((t, ev, base, solar, grid, ds))
n = 0
with psycopg.connect(host="/var/tmp", port=55433, user="postgres", dbname=target) as c:
    for r in rows:
        import datetime as dt
        clk = dt.datetime.fromisoformat(r["clock"])
        s = [x for x in snaps[r["run"]] if x[0] <= clk]
        s = s[-1] if s else (None,) * 6
        c.execute("""INSERT INTO ottoq_bess_forecast_log (depot_id, sim_run_id, data_source, tick_seq, sim_clock, snapshot_at,
                       ev_drawn_kw, site_base_kw, site_solar_kw, grid_kw, ev_persist_kw, on_charger_kw, known_kw, queue_kw,
                       base_kw, solar_kw, rule_ev_kw) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                  (TWIN, r["run"], s[5], r["k"], clk, s[0], s[1], s[2], s[3], s[4], r.get("ev_persist_kw"),
                   (r.get("ev_active_kw") or [])[:16], (r.get("ev_known_kw") or [])[:16], (r.get("ev_queue_kw") or [])[:16],
                   (r.get("base_kw") or [])[:16], (r.get("solar_kw") or [])[:16], (r.get("ev_kw") or [])[:16]))
        n += 1
print(f"backfilled {n} rows into {target}")
