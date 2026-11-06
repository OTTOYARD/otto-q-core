#!/usr/bin/env python3
"""E5, the battery's half: the cheapest energy bill the depot could have had on a finished lab day, with perfect foresight.

On a day the lab ran to its end, the depot's load before the battery is known minute by minute (site_energy_snapshots:
the cars' charging, the building, the lights, less the solar). Given that load, a linear program (OR-Tools GLOP, 9.15)
chooses the battery's charge and discharge at every step to minimise the day's bill, priced exactly as the battery's
own day plan prices it (0435: the TOU rate of the step from twin.ottoq_sim_current_tariff, the demand charge on the
highest 30-minute average spread over 30 days, $0.02 per kWh of wear), within the battery's limits (power, its SoC
floor and ceiling, round-trip efficiency), ending the day no emptier than the real battery did. It is a bound: no
battery policy, however clever, beats it on this day's load. Beside it, the bill the battery's real plan ran up and the
bill with no battery at all. The gap between the real plan and the bound is what perfect forward planning is worth on
this day; the gap between no battery and the real plan is what the battery earned. And a ladder: rolling plans that
see the true load 1, 2 or 4 hours ahead (persistence beyond), so the prize can be read as what a forecast of each
horizon would capture.

WHAT IT IS NOT. The load is held as it happened: the cars' charging is not moved (the vehicles' needs set the load,
CLAUDE.md rule 13), so this measures the battery's planning only. Demand is read on 30-minute averages of the step
samples, and the day's demand charge counts only the part of the peak above what the month had already billed.

Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_perfect_day/bound_energy.py --db ottoq_cap_normal_day_116_171717
Nothing here touches production.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from zoneinfo import ZoneInfo

import psycopg
from ortools.linear_solver import pywraplp

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
TWIN = "11111111-1111-1111-1111-111111111111"
HERE = os.path.dirname(os.path.abspath(__file__))

SNAP_SQL = """
SELECT s.timestamp, COALESCE(s.total_ev_charging_kw, 0), COALESCE(s.building_load_kw, 0), COALESCE(s.lighting_load_kw, 0),
       COALESCE(s.solar_generation_kw, 0), COALESCE(s.bess_output_kw, 0), COALESCE(s.grid_import_kw, 0),
       COALESCE(s.grid_export_kw, 0), s.billing_period_peak_kw,
       (SELECT t.out_rate_usd_kwh FROM twin.ottoq_sim_current_tariff(%(depot)s, s.timestamp) t)
  FROM site_energy_snapshots s
 WHERE s.sim_run_id = %(run)s AND s.depot_id = %(depot)s
 ORDER BY s.timestamp
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--run")
    ap.add_argument("--out", default=os.path.join(HERE, "bound_energy.jsonl"))
    ap.add_argument("--billed-before", type=float, default=0.0,
                    help="kW of the month's peak already billed before this day (0: the day pays for its own peak)")
    ap.add_argument("--forecast-db", action="append", default=[],
                    help="another finished lab day whose load before the battery, step by step, is the forecast of this "
                         "day's (several: their mean): a plan made from a typical day's shape")
    ap.add_argument("--dr-reserve-kwh", type=float, default=0.0,
                    help="deliverable kWh every plan must hold in summer through the demand-response window, declining "
                         "across it as the day plan's does (bess_plan_dr_reserve_kwh, 600 at the twin depot, so a call "
                         "does not slow the cars' charging), but needed only from the window's start: a plan may spend "
                         "it earlier and must refill it by then. The day plan holds it from the start of the day; that "
                         "form is a ratchet a linear program cannot hold exactly, and is measured by the lab's what-if "
                         "days instead. 0: none (the earlier results)")
    ap.add_argument("--dr-window", default="14,20", help="the call window in local hours (the plan's defaults)")
    ap.add_argument("--window-start-h", type=float,
                    help="bill only the snapshots after this many hours from the run's start, the battery taken as it stood "
                         "then (a long lab day billed over its last 24 hours, so the 6 AM start-up, the whole fleet at the "
                         "depot at once, is not what the bill pays for)")
    ap.add_argument("--no-ladder", action="store_true",
                    help="skip the rolling-forecast ladder (720 solves): the bill as the day ran it, no battery and "
                         "perfect foresight only, which is all a what-if day's row needs")
    a = ap.parse_args()
    conn = psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=a.db)
    run = a.run or conn.execute("SELECT sim_run_id::text FROM ottoq_sim_runs WHERE run_by = 'ab_harness' "
                                "ORDER BY started_at DESC LIMIT 1").fetchone()[0]
    t0, t1 = conn.execute("SELECT sim_clock_start, sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s",
                          (run,)).fetchone()
    rows = conn.execute(SNAP_SQL, {"run": run, "depot": TWIN}).fetchall()
    b = conn.execute("""SELECT capacity_kwh, max_charge_kw, max_discharge_kw, roundtrip_efficiency_pct,
                               soc_min_floor_pct, soc_max_ceiling_pct FROM ottoq_bess_units WHERE depot_id = %s""",
                     (TWIN,)).fetchone()
    soc = conn.execute("""SELECT timestamp, soc_percent FROM bess_snapshots WHERE depot_id = %s
                           AND timestamp BETWEEN %s AND %s ORDER BY timestamp""", (TWIN, t0, t1)).fetchall()
    month = t0.month
    d_rate, d_season = conn.execute("""SELECT demand_first_block_usd_kw, season FROM ottoq_depot_tariffs
                              WHERE depot_id = %s AND active AND %s = ANY(season_months)
                              ORDER BY effective_from DESC LIMIT 1""", (TWIN, month)).fetchone()
    d_rate = float(d_rate)
    amort = 30.0
    wear = 0.02
    conn.close()
    if len(rows) < 12:
        raise SystemExit(f"only {len(rows)} energy snapshots for run {run}")
    cap, pc, pd, rte, floor_pct, ceil_pct = (float(x) for x in b)
    eff = math.sqrt(rte if rte <= 1 else rte / 100.0)         # per direction (0435 §1(d): the column is a fraction)
    lo_e, hi_e = cap * floor_pct / 100.0, cap * ceil_pct / 100.0
    if a.window_start_h is not None:      # the window: its snapshots, and the battery as it stood at its start
        import datetime as _dt
        tw = t0 + _dt.timedelta(hours=a.window_start_h)
        rows = [r for r in rows if r[0] > tw]
        before = [x for x in soc if x[0] <= tw]
        soc = (before[-1:] if before else []) + [x for x in soc if x[0] > tw]
    e0 = cap * float(soc[0][1]) / 100.0 if soc else cap * 0.5
    e_end = cap * float(soc[-1][1]) / 100.0 if soc else e0
    ts = [r[0] for r in rows]
    dts = [max((ts[i + 1] - ts[i]).total_seconds() / 3600.0, 1e-6) for i in range(len(ts) - 1)]
    dts.append(dts[-1])
    pre = [float(r[1]) + float(r[2]) + float(r[3]) - float(r[4]) for r in rows]   # load before the battery
    real_grid = [float(r[6]) - float(r[7]) for r in rows]
    real_out = [float(r[5]) for r in rows]                                          # + discharge, - charge
    rate = [float(r[9] if r[9] is not None else 0.07) for r in rows]
    # the peak already billed this month before the day began: a lab day starts a fresh run, whose billed peak (0600's
    # completed 30-minute windows of this run's own draw) is nothing at its start, so every policy on every day is
    # charged for its own highest half hour. (An earlier cut read the first snapshot's billing_period_peak_kw, which
    # already holds the first tick's draw: a policy that drew hard in that tick had its own peak hidden.)
    billed_before = float(a.billed_before)
    n = len(rows)
    win = max(1, int(round(0.5 / (sum(dts) / n))))                                  # steps in 30 minutes
    # the demand-response reserve (0435's v_res, summer only), needed from the window's start: deliverable kWh as a lower
    # bound on the battery's stored energy at the start of each step in the window, declining to nothing at its end.
    dr_ws, dr_we = (float(x) for x in a.dr_window.split(","))

    def dr_res(i: int) -> float:
        if a.dr_reserve_kwh <= 0 or d_season != "summer":
            return 0.0
        lt = ts[i].astimezone(ZoneInfo("America/Chicago"))
        h = lt.hour + lt.minute / 60.0
        return a.dr_reserve_kwh * (dr_we - h) / (dr_we - dr_ws) if dr_ws <= h < dr_we else 0.0
    e_min = [min(hi_e, lo_e + dr_res(i) / eff) for i in range(n)]

    def bill(grid: list[float], discharge_kwh: float) -> dict:
        energy = sum(max(g, 0) * rate[i] * dts[i] for i, g in enumerate(grid))
        means = [sum(grid[i:i + win]) / len(grid[i:i + win]) for i in range(0, n - win + 1)] if n >= win else [max(grid)]
        i_pk = max(range(len(means)), key=lambda i: means[i])
        peak30 = means[i_pk]
        demand = d_rate / amort * max(peak30 - billed_before, 0)
        # the half hour that set the peak, by its last snapshot (local time): which part of the day the bill paid for
        at = ts[min(i_pk + win - 1, n - 1)].astimezone(ZoneInfo("America/Chicago")).strftime("%H:%M")
        return {"energy_usd": round(energy, 2), "peak30_kw": round(peak30, 1), "peak30_ends_ct": at,
                "demand_usd": round(demand, 2),
                "wear_usd": round(wear * discharge_kwh, 2), "total_usd": round(energy + demand + wear * discharge_kwh, 2)}

    real = bill(real_grid, sum(max(o, 0) * dts[i] for i, o in enumerate(real_out)))
    none = bill([max(p, 0) for p in pre], 0.0)

    s = pywraplp.Solver.CreateSolver("GLOP")
    c = [s.NumVar(0, pc, f"c{i}") for i in range(n)]
    d = [s.NumVar(0, pd, f"d{i}") for i in range(n)]
    e = [s.NumVar(lo_e, hi_e, f"e{i}") for i in range(n + 1)]
    g = [s.NumVar(0, s.infinity(), f"g{i}") for i in range(n)]
    spill = [s.NumVar(0, s.infinity(), f"x{i}") for i in range(n)]   # solar the site cannot use (no export credit)
    p30 = s.NumVar(0, s.infinity(), "p30")
    s.Add(e[0] == min(max(e0, lo_e), hi_e))
    for i in range(n):
        if e_min[i] > lo_e:
            s.Add(e[i] >= e_min[i])
        s.Add(e[i + 1] == e[i] + (eff * c[i] - d[i] / eff) * dts[i])
        s.Add(g[i] == pre[i] + c[i] - d[i] + spill[i])
    s.Add(e[n] >= min(max(e_end, lo_e), hi_e))
    for i in range(0, n - win + 1):
        s.Add(p30 >= sum(g[i:i + win]) * (1.0 / win))
    over = s.NumVar(0, s.infinity(), "over")
    s.Add(over >= p30 - billed_before)
    s.Minimize(sum(rate[i] * g[i] * dts[i] for i in range(n)) + (d_rate / amort) * over
               + wear * sum(d[i] * dts[i] for i in range(n)))
    st = s.Solve()
    best_grid = [g[i].solution_value() for i in range(n)]
    best = bill(best_grid, sum(d[i].solution_value() * dts[i] for i in range(n)))
    # ── how much of the prize a forecast of the next H hours would capture: a rolling plan that re-solves every step
    #    seeing the true load H hours ahead and holding the current load flat beyond it (persistence, as the real plan's
    #    floor does), applying only its first step. H = the whole day reproduces the bound (a check on the method).
    def rolling(h_hours: float | None, shape: list[float] | None = None) -> dict:
        """A rolling plan: the true load for h hours ahead; beyond it, the shape if one is given (another day's load,
        step by step), else the load now held flat."""
        hs = n if h_hours is None else max(1, int(round(h_hours * win * 2)))     # win steps = 30 min
        e_t = min(max(e0, lo_e), hi_e)
        grid_hist, dis_kwh = [], 0.0
        for t in range(n):
            fc = [pre[i] if i < t + hs else (shape[i] if shape is not None and i < len(shape) else pre[t])
                  for i in range(t, n)]
            m = len(fc)
            r = pywraplp.Solver.CreateSolver("GLOP")
            cc = [r.NumVar(0, pc, "") for _ in range(m)]
            dd = [r.NumVar(0, pd, "") for _ in range(m)]
            ee = [r.NumVar(lo_e, hi_e, "") for _ in range(m + 1)]
            gg = [r.NumVar(0, r.infinity(), "") for _ in range(m)]
            xx = [r.NumVar(0, r.infinity(), "") for _ in range(m)]
            pp = r.NumVar(0, r.infinity(), "")
            r.Add(ee[0] == e_t)
            for k in range(m):
                if k > 0 and e_min[t + k] > lo_e:
                    r.Add(ee[k] >= e_min[t + k])
                r.Add(ee[k + 1] == ee[k] + (eff * cc[k] - dd[k] / eff) * dts[t + k])
                r.Add(gg[k] == fc[k] + cc[k] - dd[k] + xx[k])
            r.Add(ee[m] >= min(max(e_end, lo_e), hi_e))
            for i0 in range(max(0, t - win + 1), n - win + 1):       # every 30-minute window that is not all past
                past = sum(grid_hist[i] for i in range(i0, min(t, i0 + win)))
                fut = [gg[i - t] for i in range(max(i0, t), i0 + win)]
                r.Add(pp >= (past + sum(fut)) * (1.0 / win))
            sunk = max((sum(grid_hist[i:i + win]) / win for i in range(0, t - win + 1)), default=0.0)
            r.Add(pp >= sunk)
            ov = r.NumVar(0, r.infinity(), "")
            r.Add(ov >= pp - billed_before)
            r.Minimize(sum(rate[t + k] * gg[k] * dts[t + k] for k in range(m)) + (d_rate / amort) * ov
                       + wear * sum(dd[k] * dts[t + k] for k in range(m)))
            if r.Solve() not in (pywraplp.Solver.OPTIMAL, pywraplp.Solver.FEASIBLE):
                c0, d0 = 0.0, 0.0
            else:
                c0, d0 = cc[0].solution_value(), dd[0].solution_value()
            # the step as it really happens: the true load, the battery's chosen power, within its energy limits
            e_next = min(max(e_t + (eff * c0 - d0 / eff) * dts[t], lo_e), hi_e)
            net = (e_next - e_t) / dts[t]
            c_eff, d_eff = (net / eff, 0.0) if net >= 0 else (0.0, -net * eff)
            grid_hist.append(max(pre[t] + c_eff - d_eff, 0.0))
            dis_kwh += d_eff * dts[t]
            e_t = e_next
        b_ = bill(grid_hist, dis_kwh)
        b_["end_soc_kwh"] = round(e_t, 1)
        return b_

    ladder = {}
    for label, h in (() if a.no_ladder else
                     (("persistence_only", 0.0), ("next_1h", 1.0), ("next_2h", 2.0), ("next_4h", 4.0), ("whole_day", None))):
        ladder[label] = rolling(h if h else 1.0 / (2 * win)) if h is not None else rolling(None)
    # a typical day's shape as the forecast: another lab day's load before the battery, step by step
    if a.forecast_db:
        shapes = []
        for fdb in a.forecast_db:
            fc = psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=fdb)
            frun = fc.execute("SELECT sim_run_id::text FROM ottoq_sim_runs WHERE run_by = 'ab_harness' "
                              "ORDER BY started_at DESC LIMIT 1").fetchone()[0]
            fr = fc.execute(SNAP_SQL, {"run": frun, "depot": TWIN}).fetchall()
            fc.close()
            shapes.append([float(r[1]) + float(r[2]) + float(r[3]) - float(r[4]) for r in fr])
        m_ = min(len(x) for x in shapes)
        shape = [sum(x[i] for x in shapes) / len(shapes) for i in range(m_)]
        err = [abs(shape[i] - pre[i]) for i in range(min(m_, n))]
        ladder["typical_day_shape"] = rolling(1.0 / (2 * win), shape)
        ladder["typical_day_shape"]["forecast_mae_kw"] = round(sum(err) / len(err), 1)
        ladder["typical_day_shape"]["forecast_from"] = a.forecast_db
        ladder["next_1h_then_shape"] = rolling(1.0, shape)
    out = {"db": a.db, "run": run, "steps": n, "step_h": round(sum(dts) / n, 4), "status": int(st),
           "window_start_h": a.window_start_h,
           "battery": {"capacity_kwh": cap, "max_kw": pd, "rte": rte, "soc_start_kwh": round(e0, 1),
                       "soc_end_kwh": round(e_end, 1)},
           "billed_before_kw": billed_before, "demand_usd_kw_month": float(d_rate), "demand_season": d_season,
           "dr_reserve": {"kwh": a.dr_reserve_kwh, "needed_from": "window_start", "window": a.dr_window}
                         if a.dr_reserve_kwh > 0 else None,
           "load_kwh": round(sum(max(p, 0) * dts[i] for i, p in enumerate(pre)), 1),
           "no_battery": none, "real_plan": real, "perfect_foresight": best,
           "battery_earned_usd": round(none["total_usd"] - real["total_usd"], 2),
           "foresight_prize_usd": round(real["total_usd"] - best["total_usd"], 2),
           "forecast_ladder": ladder}
    with open(a.out, "a") as f:
        f.write(json.dumps(out, default=str) + "\n")
    print(json.dumps({k: out[k] for k in ("db", "load_kwh", "no_battery", "real_plan", "perfect_foresight",
                                          "battery_earned_usd", "foresight_prize_usd", "forecast_ladder")}, indent=1))


if __name__ == "__main__":
    main()
