"""The service's battery planner (ottoq-intelligence app/optimizers/battery_planner.py) against the lab's battery_lp.py on
the same state: battery_lp plans tick k on a kept replica (its plan written, then rolled back); the inputs it planned on are
rebuilt line for line and handed to plan_battery; the setpoints and the objective must agree (LAB ONLY)."""
import json, os, sys, math, importlib.util
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psycopg
from ortools.linear_solver import pywraplp
import battery_lp as BL
spec = importlib.util.spec_from_file_location("battery_planner", os.path.join(os.environ.get("OTTOQ_INTEL_ROOT", "/home/user/ottoq-intelligence"), "app/optimizers/battery_planner.py"))
BP = importlib.util.module_from_spec(spec); sys.modules["battery_planner"] = BP; spec.loader.exec_module(BP)
TWIN = BL.TWIN
db, shape_path, model_path, k = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
captured = {}
orig = pywraplp.Solver.CreateSolver
def spy(name):
    s = orig(name); captured["s"] = s; return s
with psycopg.connect(host="/var/tmp", port=55433, user="postgres", dbname=db) as c:
    run = c.execute("SELECT sim_run_id::text FROM ottoq_sim_runs WHERE run_by='ab_harness' ORDER BY started_at DESC LIMIT 1").fetchone()[0]
    lp = BL.BatteryLP(c, run, 5.0, 432, BL.load_shape(shape_path), learned=model_path, bill_from_min=720)
    c.execute("UPDATE ottoq_sim_runs SET sim_clock_current = sim_clock_start + make_interval(mins => 5 * %s) WHERE sim_run_id = %s", (k, run))
    # the inputs plan_now(k) plans on, rebuilt line for line
    soc = float(c.execute("SELECT current_soc_pct FROM ottoq_bess_units WHERE depot_id = %s ORDER BY bess_id LIMIT 1", (TWIN,)).fetchone()[0])
    e0 = min(max(lp.cap * soc / 100.0, lp.lo), lp.hi)
    hist = c.execute("""SELECT GREATEST(COALESCE(grid_import_kw, 0) - COALESCE(grid_export_kw, 0), 0),
                               COALESCE(total_ev_charging_kw, 0) + COALESCE(building_load_kw, 0)
                               + COALESCE(lighting_load_kw, 0) - COALESCE(solar_generation_kw, 0)
                          FROM site_energy_snapshots WHERE sim_run_id = %s AND depot_id = %s ORDER BY timestamp""", (run, TWIN)).fetchall()
    grid_hist = [float(h[0]) for h in hist][:k]
    last_pre = float(hist[-1][1]) if hist else 0.0
    m = lp.n - k
    fc = [lp.shape[k + j] if k + j < len(lp.shape) else last_pre for j in range(m)]
    fc = lp._learned_fc(k, fc)
    fc = [max(x, last_pre) if j < lp.win else x for j, x in enumerate(fc)]
    win = lp.win; bf = lp.bill_from
    periods = []
    for plo, phi in ([(0, bf), (bf, lp.n)] if 0 < bf < lp.n else [(0, lp.n)]):
        if phi <= k:
            continue
        sunk = max((sum(grid_hist[i:i + win]) / win for i in range(plo, min(k, phi) - win + 1)), default=0.0)
        periods.append(BP.Period(start=plo - k, end=phi - k, sunk_kw=sunk, margin_kw=max(100.0, 0.10 * sunk)))
    floor = []
    for j in range(m):
        r = lp._reserve(k + j)
        floor.append(min(lp.hi, lp.lo + r / lp.eff) if r > 0 else lp.lo)
    res = BP.plan_battery(load_kw=fc, price_usd_kwh=lp.rate[k:], step_min=5.0,
                          battery=BP.Battery(e0, lp.lo, lp.hi, lp.pc, lp.pd, lp.eff),
                          demand_usd_kw=lp.d_rate / lp.amort, periods=periods,
                          past_grid_kw=grid_hist[max(0, k - (win - 1)):k], window_steps=win,
                          soc_floor_kwh=floor, wear_usd_kwh=lp.wear, terminal_usd_kwh=lp.c_rep)
    # the lab's own plan of the same tick
    pywraplp.Solver.CreateSolver = staticmethod(spy)
    out = lp.plan_now(k)
    pywraplp.Solver.CreateSolver = orig
    lab_obj = captured["s"].Objective().Value()
    lab_set = c.execute("SELECT bess_setpoint_kw, predicted_peak_kw FROM ottoq_energy_plan WHERE sim_run_id = %s AND plan_state = 'ready' ORDER BY created_at DESC LIMIT 1", (run,)).fetchone()
    lab_sp = [float(x) for x in lab_set[0]]
    svc_sp = [round(x, 1) for x in res.setpoint_kw]
    diff = max(abs(a - b) for a, b in zip(lab_sp, svc_sp))
    print(f"k {k}: {m} steps, {len(periods)} periods (sunk {[round(p.sunk_kw) for p in periods]}); lab objective {lab_obj:.6f}, "
          f"service {res.objective_usd:.6f} ({res.status}, {res.solve_ms:.0f} ms); setpoints differ by at most {diff:.2f} kW; "
          f"peak lab {float(lab_set[1]):.1f} service {res.peak_kw[-1]:.1f}")
    fixture = {"k": k, "inputs": {"load_kw": fc, "price_usd_kwh": lp.rate[k:], "step_min": 5.0,
               "battery": {"soc_kwh": e0, "floor_kwh": lp.lo, "ceiling_kwh": lp.hi, "max_charge_kw": lp.pc,
                           "max_discharge_kw": lp.pd, "eff_one_way": lp.eff},
               "demand_usd_kw": lp.d_rate / lp.amort,
               "periods": [{"start": p.start, "end": p.end, "sunk_kw": p.sunk_kw, "margin_kw": p.margin_kw} for p in periods],
               "past_grid_kw": grid_hist[max(0, k - (win - 1)):k], "window_steps": win, "soc_floor_kwh": floor,
               "wear_usd_kwh": lp.wear, "terminal_usd_kwh": lp.c_rep},
               "lab": {"objective_usd": lab_obj, "setpoint_kw": lab_sp, "peak_kw": float(lab_set[1])}}
    if len(sys.argv) > 5:
        json.dump(fixture, open(sys.argv[5], "w"))
    c.rollback()
