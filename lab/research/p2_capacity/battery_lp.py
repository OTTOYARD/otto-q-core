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

LAB ONLY. Each new plan marks the earlier ones superseded, so the orchestrator finds one plan 'ready' (a day run in one
transaction, `capacity_day.py --one-transaction`, gives every plan the same created_at, so the newest cannot be told by its
time).
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
                 dr_window: tuple[float, float] = (14.0, 20.0), wear: float = 0.02, amort: float = 30.0,
                 guard: bool = True, blend: bool = False, learned: str | None = None):
        self.conn, self.run, self.step_h, self.n = conn, run, step_min / 60.0, ticks
        self.shape, self.dr_kwh, self.dr_window, self.wear, self.amort = shape, dr_kwh, dr_window, wear, amort
        # the two guards the first lab day showed it needs (2026-11-06): planned to the edge of the peak already billed
        # on a forecast 250-400 kW low at midday, it charged into every half hour it thought had room and the billed peak
        # ratcheted from 1,128 to 1,457 kW. So (a) the next 30 minutes are never forecast under what the depot drew last
        # (a forecast is a shape, not a promise), and (b) a half hour wholly in the future is planned to stay a margin under
        # the plan's peak, max(100 kW, 10% of the peak already billed), the margin the day plan keeps under its level.
        self.guard = guard
        # blend (2026-11-06): the shape is another day's; the engine knows this day's near term (sessions under way, cars
        # coming home, the queue on site: the day plan's own forecast terms, ottoq_bess_day_plan's 'forecast'). With blend,
        # each step is forecast at least at what the engine knows is coming, base + max(known, queue) - solar, without
        # the day plan's persistence floor (the last hour's draw held for the whole horizon, which would hold the
        # forecast up all day). On the call day the shape came in 126 kW under the morning (G519's lab record).
        self.blend = blend
        # learned (2026-11-06): the EV charging of the next four hours predicted by a model fitted on other lab days
        # (forecast_learn.py --save: a ridge per half hour ahead on the day plan's own terms and the hour), the building
        # and the sun as the day plan forecasts them, and the shape beyond the model's four hours
        self.learned = None
        if learned:
            with open(learned) as fh:
                self.learned = json.load(fh)
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

    def _learned_fc(self, k: int, fc: list[float]) -> list[float]:
        """The pre-battery load of the next half hours from the learned EV model, the shape beyond."""
        c = self.conn
        clk = c.execute("SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s", (self.run,)).fetchone()[0]
        dp = c.execute("SELECT public.ottoq_bess_day_plan(%s, %s, %s, NULL)", (self.run, TWIN, clk)).fetchone()[0] or {}
        f = dp.get("forecast") or {}
        arr = lambda key: [float(x) for x in (f.get(key) or [])]
        base, known, queue, solar = arr("base_kw"), arr("ev_known_kw"), arr("ev_queue_kw"), arr("solar_kw")
        persist = float(dp.get("ev_persist_kw") or 0)
        nb = min(len(base), len(known), len(queue), len(solar), len(self.learned["per_half_hour"]))
        act = [0.0] * nb      # the cars on a charger now, held at their starting rate (the known term's first loop)
        for rate, kwh in c.execute("""
                SELECT GREATEST(ottoq_sim_compute_charge_rate(
                         p_soc_pct := v.current_soc, p_battery_temp_c := COALESCE(s.ambient_temp_c,22)+5,
                         p_ambient_temp_c := COALESCE(s.ambient_temp_c,22), p_charger_max_kw := ch.max_kw,
                         p_vehicle_max_kw := v.inlet_max_kw, p_battery_capacity_kwh := v.battery_capacity_kwh,
                         p_battery_soh_pct := 95, p_noise_seed := 1, p_noise_salt := s.vehicle_id::text), 1),
                       GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-v.current_soc)/100.0
                                  *COALESCE(v.battery_capacity_kwh,75))
                  FROM ocpp_sessions s JOIN stalls st ON st.id=s.stall_id
                  JOIN ottoq_ocpp_chargers ch ON ch.charger_id=st.ocpp_charger_id
                  JOIN vehicles v ON v.id=s.vehicle_id
                 WHERE s.status='active' AND s.sim_run_id=%s""", (self.run,)).fetchall():
            dur = float(kwh) / float(rate) * 60.0
            for h in range(nb):
                if h * 30.0 < dur:
                    act[h] += float(rate)
        pre = []
        for h in range(nb):
            m = self.learned["per_half_hour"][h]
            lt = (clk + __import__("datetime").timedelta(minutes=30 * h)).astimezone(CT)
            hr = lt.hour + lt.minute / 60.0
            x = [act[h], known[h] - act[h], queue[h], persist, base[h], solar[h],
                 math.sin(2 * math.pi * hr / 24), math.cos(2 * math.pi * hr / 24), max(act[h], queue[h], persist)]
            z = [1.0] + [(xi - mu) / sd for xi, mu, sd in zip(x, m["mu"], m["sd"])]
            ev = max(0.0, sum(wi * zi for wi, zi in zip(m["w"], z)))
            pre.append(max(0.0, base[h] + ev - solar[h]))
        per = max(1, int(round(0.5 / self.step_h)))
        return [pre[j // per] if j // per < len(pre) else x for j, x in enumerate(fc)]

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
        if self.blend:
            clk = c.execute("SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s", (self.run,)).fetchone()[0]
            f = c.execute("SELECT public.ottoq_bess_day_plan(%s, %s, %s, NULL) -> 'forecast'", (self.run, TWIN, clk)).fetchone()[0]
            if f:
                arr = lambda key: [float(x) for x in (f.get(key) or [])]
                base, known, queue, solar = arr("base_kw"), arr("ev_known_kw"), arr("ev_queue_kw"), arr("solar_kw")
                nb = min(len(base), len(known), len(queue), len(solar))
                eng = [max(0.0, base[i] + max(known[i], queue[i]) - solar[i]) for i in range(nb)]
                per = max(1, int(round(0.5 / self.step_h)))          # this plan's steps in the day plan's half hour
                fc = [max(x, eng[j // per]) if j // per < nb else x for j, x in enumerate(fc)]
        if self.learned is not None:
            fc = self._learned_fc(k, fc)
        if self.guard:
            fc = [max(x, last_pre) if j < self.win else x for j, x in enumerate(fc)]
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
        sunk = max((sum(grid_hist[i:i + self.win]) / self.win for i in range(0, k - self.win + 1)), default=0.0)
        margin = max(100.0, 0.10 * sunk) if self.guard else 0.0
        for i0 in range(max(0, k - self.win + 1), self.n - self.win + 1):  # every 30-minute window not wholly past
            past = sum(grid_hist[i] for i in range(i0, min(k, i0 + self.win)))
            fut = [g[i - k] for i in range(max(i0, k), i0 + self.win)]
            s.Add(p30 - (margin if i0 >= k else 0.0) >= (past + sum(fut)) * (1.0 / self.win))
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
