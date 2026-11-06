"""The battery planned as a linear program over the rest of the day, inside a lab day: the build G517 and the battery bound
point to, measured with the twin's own engine instead of a replay.

Every tick, before the engine runs it, `plan_now` solves the rest of the day (OR-Tools GLOP, 9.15, the CP-SAT service's
pin): the battery's charge and discharge at every 5-minute step, to minimise the energy bill, the demand charge on the
highest 30-minute average the run will be billed for (the past steps' real draw included), and $0.02 a discharged kWh of
wear, less the energy left in the battery at the day's end at the day plan's own replacement cost (so the plan neither
hoards nor dumps at the end). It sees the day so far as it happened and the rest through a forecast: another day's load
before the battery, step by step (`load_shape`), the current step included (the plan is made before the tick, as
an outside service's would be, and cannot see the step's own load). It holds the
battery's power, floor, ceiling and round trip, and the 600 kWh demand-response reserve from 2 PM as the day plan's
(declining to nothing at 8 PM), so a call never slows a car. The plan is written to ottoq_energy_plan as the energy
orchestrator's MPC bridge reads it (`energy_mpc_follow` = 1, FR-1): the engine follows the first step, inside its own
limits, exactly as it would follow the production bridge's plan. The cars' charging is never touched: they charge against
the installed service limit and demand-response calls (`ottoq_effective_charge_cap_kw`, 0136).

LAB ONLY. One lab day runs in one transaction, so `now()` and the plan's created_at default are the same for every plan of
the day; each new plan therefore marks the earlier ones superseded, and the orchestrator finds one plan 'ready'.
"""
from __future__ import annotations

import json
import math
from zoneinfo import ZoneInfo

from ortools.linear_solver import pywraplp

TWIN = "11111111-1111-1111-1111-111111111111"
CT = ZoneInfo("America/Chicago")


def load_shape(path: str) -> list[float]:
    with open(path) as f:
        return [float(x) for x in json.load(f)["pre_kw"]]


class BatteryLP:
    def __init__(self, conn, run: str, step_min: float, ticks: int, shape: list[float], dr_kwh: float = 600.0,
                 dr_window: tuple[float, float] = (14.0, 20.0), wear: float = 0.02, amort: float = 30.0):
        self.conn, self.run, self.step_h, self.n = conn, run, step_min / 60.0, ticks
        self.shape, self.dr_kwh, self.dr_window, self.wear, self.amort = shape, dr_kwh, dr_window, wear, amort
        b = conn.execute("""SELECT capacity_kwh, max_charge_kw, max_discharge_kw, roundtrip_efficiency_pct,
                                   COALESCE(soc_min_floor_pct, 10), COALESCE(soc_max_ceiling_pct, 90)
                              FROM ottoq_bess_units WHERE depot_id = %s ORDER BY bess_id LIMIT 1""", (TWIN,)).fetchone()
        self.cap, self.pc, self.pd = float(b[0]), float(b[1]), float(b[2])
        rte = float(b[3])
        self.eff = math.sqrt(rte if rte <= 1 else rte / 100.0)
        self.lo, self.hi = self.cap * float(b[4]) / 100.0, self.cap * float(b[5]) / 100.0
        self.t0 = conn.execute("SELECT sim_clock_start FROM ottoq_sim_runs WHERE sim_run_id = %s", (run,)).fetchone()[0]
        month = self.t0.astimezone(CT).month
        d = conn.execute("""SELECT demand_first_block_usd_kw, season FROM ottoq_depot_tariffs
                             WHERE depot_id = %s AND active AND %s = ANY(season_months)
                             ORDER BY effective_from DESC LIMIT 1""", (TWIN, month)).fetchone()
        self.d_rate, self.summer = float(d[0]), d[1] == "summer"
        # the day's prices, step by step (the twin's own lookup, as the day plan and the bill read them)
        import datetime as dt
        self.times = [self.t0 + dt.timedelta(minutes=step_min * (i + 1)) for i in range(ticks)]
        self.rate = [float(conn.execute("SELECT t.out_rate_usd_kwh FROM twin.ottoq_sim_current_tariff(%s, %s) t",
                                        (TWIN, t)).fetchone()[0] or 0.07) for t in self.times]
        mn = min(self.rate)
        self.c_rep = mn / (self.eff * self.eff)        # a stored kWh's replacement cost, as the day plan prices it
        self.win = max(1, int(round(0.5 / self.step_h)))
        self.plans = 0

    def _reserve(self, i: int) -> float:
        if self.dr_kwh <= 0 or not self.summer:
            return 0.0
        lt = self.times[i].astimezone(CT)
        h = lt.hour + lt.minute / 60.0
        ws, we = self.dr_window
        return self.dr_kwh * (we - h) / (we - ws) if ws <= h < we else 0.0

    def plan_now(self, k: int) -> dict:
        """Before tick k (0-based) runs: solve steps k..n-1 and write the plan the orchestrator will read at step k."""
        c = self.conn
        soc = float(c.execute("SELECT current_soc_pct FROM ottoq_bess_units WHERE depot_id = %s ORDER BY bess_id LIMIT 1",
                              (TWIN,)).fetchone()[0])
        e0 = min(max(self.cap * soc / 100.0, self.lo), self.hi)
        hist = c.execute("""SELECT GREATEST(COALESCE(grid_import_kw, 0) - COALESCE(grid_export_kw, 0), 0),
                                   COALESCE(total_ev_charging_kw, 0) + COALESCE(building_load_kw, 0)
                                   + COALESCE(lighting_load_kw, 0) - COALESCE(solar_generation_kw, 0)
                              FROM site_energy_snapshots WHERE sim_run_id = %s AND depot_id = %s
                             ORDER BY timestamp""", (self.run, TWIN)).fetchall()
        grid_hist = [float(h[0]) for h in hist][:k]
        last_pre = float(hist[-1][1]) if hist else (self.shape[0] if self.shape else 0.0)
        m = self.n - k
        # the forecast, the current step included: the engine dispatches after this tick's sessions start, which this
        # plan (made before the tick, as an outside service's would be) cannot see; the shape knows the day's surges
        fc = [self.shape[k + j] if k + j < len(self.shape) else last_pre for j in range(m)]
        s = pywraplp.Solver.CreateSolver("GLOP")
        ch = [s.NumVar(0, self.pc, "") for _ in range(m)]
        dis = [s.NumVar(0, self.pd, "") for _ in range(m)]
        e = [s.NumVar(self.lo, self.hi, "") for _ in range(m + 1)]
        g = [s.NumVar(0, s.infinity(), "") for _ in range(m)]
        sp = [s.NumVar(0, s.infinity(), "") for _ in range(m)]          # solar the site cannot use (no export credit)
        p30 = s.NumVar(0, s.infinity(), "")
        s.Add(e[0] == e0)
        for j in range(m):
            s.Add(e[j + 1] == e[j] + (self.eff * ch[j] - dis[j] / self.eff) * self.step_h)
            s.Add(g[j] == fc[j] + ch[j] - dis[j] + sp[j])
            r = self._reserve(k + j)
            if j > 0 and r > 0:
                s.Add(e[j] >= min(self.hi, self.lo + r / self.eff))
        for i0 in range(max(0, k - self.win + 1), self.n - self.win + 1):  # every 30-minute window not wholly past
            past = sum(grid_hist[i] for i in range(i0, min(k, i0 + self.win)))
            fut = [g[i - k] for i in range(max(i0, k), i0 + self.win)]
            s.Add(p30 >= (past + sum(fut)) * (1.0 / self.win))
        sunk = max((sum(grid_hist[i:i + self.win]) / self.win for i in range(0, k - self.win + 1)), default=0.0)
        s.Add(p30 >= sunk)
        s.Minimize(sum(self.rate[k + j] * g[j] * self.step_h for j in range(m))
                   + (self.d_rate / self.amort) * p30
                   + self.wear * sum(dis[j] * self.step_h for j in range(m))
                   - self.c_rep * e[m])
        st = s.Solve()
        if st not in (pywraplp.Solver.OPTIMAL, pywraplp.Solver.FEASIBLE):
            return {"k": k, "status": int(st)}
        setp = [dis[j].solution_value() - ch[j].solution_value() for j in range(m)]
        # one plan 'ready' at a time (the day's transaction gives every plan the same created_at)
        c.execute("UPDATE ottoq_energy_plan SET plan_state = 'superseded' WHERE sim_run_id = %s AND plan_state = 'ready'",
                  (self.run,))
        c.execute("""INSERT INTO ottoq_energy_plan (sim_run_id, depot_id, plan_start_clock, tick_minutes, horizon_steps,
                                                    bess_setpoint_kw, forecast_load_kw, predicted_peak_kw, solver, status,
                                                    source, plan_state, detail)
                     VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'glop', 'optimal', 'lab_lp', 'ready', %s)""",
                  (self.run, TWIN, self.times[k], self.step_h * 60.0, m, [round(x, 1) for x in setp],
                   [round(x, 1) for x in fc], round(p30.solution_value(), 1),
                   json.dumps({"k": k, "e0_kwh": round(e0, 1), "sunk_peak_kw": round(sunk, 1)})))
        self.plans += 1
        return {"k": k, "status": int(st), "setpoint_now_kw": round(setp[0], 1), "p30_kw": round(p30.solution_value(), 1)}
