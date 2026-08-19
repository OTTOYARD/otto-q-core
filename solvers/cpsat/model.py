"""C4 CP-SAT prototype — the deterministic scheduling core as a PROPOSER.

Run 2 / Phase C4 (CLAUDE.md). This models the reduced canonical scenario as the
resource-constrained flexible flow shop of 2.3 and honors every 2.5 modeling
requirement:

  * piecewise charging demand above ~70% SoC  -> charge = a chain of segment
    intervals, duration and kW per segment from the class energy_curve
    (the same curve 0043 put on ottoq_vehicle_classes.energy_curve)
  * DCFC cooldown as a minimum gap on the SERVICE POINT (18 min)
    -> the point-side occupancy interval is the charge chain + cooldown;
       the asset-side intervals carry the true duration
  * cold-start as a duration modifier -> +cold_start_penalty_min on the first
    charge segment when pack_temp_c < cold_start_below_c
  * multi-term objective with exposed weights -> tardiness, on-peak energy
    (kW-minutes of charge overlapping the tariff window), peak-kW excursion
    above the soft site target (exact, via an IntVar cumulative capacity),
    inter-point moves
  * concurrency within a service point -> parallel ops (sensor clean, interior
    tidy, software update) are scheduled INSIDE the charge window at the same
    point, serialized per asset (one tech per car), consuming no extra point
  * inter-point moves as scheduled operations -> every charge->wash / ->inspect
    transition is a move interval with real duration consuming a shared path
    resource (capacity 2)
  * rolling re-solve with previous-feasible retention -> resolve(prev, t_now,
    blocked_points): started work is pinned, the rest is warm-started from the
    previous plan; if the solver fails, the previous plan is returned unchanged
    (the site is never without a schedule)
  * determinism under fixed seed -> fixed random_seed, single worker, stable
    build order; test_cpsat_prototype.py asserts byte-identical plans

The prototype DISPOSES nothing. Its output is a proposal batch in the exact
shape of ottoq_external_proposals (source='cpsat'), entering the live engine
under the same right-of-first-refusal pattern cuOpt uses (recommendation (b)
in SOLVER_STATE.md). The local decide path remains the named policy.
"""

from __future__ import annotations

import hashlib
import json
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

from ortools.sat.python import cp_model

# ----------------------------------------------------------------------------
# Scenario loading and deterministic asset generation
# ----------------------------------------------------------------------------


@dataclass
class Asset:
    aid: str
    cls: str
    arrival_min: int
    soc: int
    target_soc: int
    ready_by_min: int
    pack_temp_c: int
    needs_wash: bool
    needs_inspect: bool
    parallel_ops: list[str] = field(default_factory=list)


def load_scenario(path: str | Path) -> dict:
    sc = json.loads(Path(path).read_text())
    sc["assets"] = _generate_assets(sc)
    return sc


def _generate_assets(sc: dict) -> list[Asset]:
    rng = random.Random(sc["seed"])
    classes = sorted(sc["asset_classes"].keys())
    menu = sorted(sc["parallel_ops_menu"].keys())
    out = []
    for i in range(sc["assets_spec"]["count"]):
        cls = classes[i % len(classes)]
        arrival = rng.randrange(0, 180)
        soc = rng.randrange(12, 55)
        ready_by = arrival + rng.randrange(150, 330)
        out.append(
            Asset(
                aid=f"AV-{i:02d}",
                cls=cls,
                arrival_min=arrival,
                soc=soc,
                target_soc=90,
                ready_by_min=ready_by,
                pack_temp_c=(-2 if rng.random() < 0.25 else 18),
                needs_wash=(rng.random() < 0.5),
                needs_inspect=(i == 7),
                parallel_ops=[op for op in menu if rng.random() < 0.6],
            )
        )
    return out


# ----------------------------------------------------------------------------
# Charge physics: piecewise segments from the class energy curve
# ----------------------------------------------------------------------------


def charge_segments(sc: dict, asset: Asset, point_kw: int) -> list[dict]:
    """Split [soc, target] at the curve breakpoints; per-segment kW and minutes.

    Returns [{from_soc, to_soc, kw, minutes}], cold-start modifier applied to
    the FIRST segment (a duration modifier, exactly like the tested live fn).
    """
    cls = sc["asset_classes"][asset.cls]
    curve = sorted(cls["energy_curve"], key=lambda s: s["above_soc_pct"])
    breaks = [s["above_soc_pct"] for s in curve[1:]] + [100]
    segs = []
    lo = asset.soc
    for edge, seg in zip(breaks, curve):
        hi = min(asset.target_soc, edge)
        if hi <= lo:
            continue
        kw = max(1, int(min(point_kw, cls["max_charge_kw"]) * seg["accept_frac"]))
        kwh = cls["battery_kwh"] * (hi - lo) / 100.0
        minutes = max(1, math.ceil(60.0 * kwh / kw))
        segs.append({"from_soc": lo, "to_soc": hi, "kw": kw, "minutes": minutes})
        lo = hi
        if lo >= asset.target_soc:
            break
    if segs and asset.pack_temp_c < sc["site"]["cold_start_below_c"]:
        segs[0] = {**segs[0], "minutes": segs[0]["minutes"] + sc["site"]["cold_start_penalty_min"],
                   "cold_start": True}
    return segs


# ----------------------------------------------------------------------------
# The model
# ----------------------------------------------------------------------------


def build_and_solve(
    sc: dict,
    t_now: int = 0,
    previous_plan: dict | None = None,
    blocked_points: set[str] | None = None,
    time_limit_s: float = 20.0,
) -> dict:
    """Solve the scenario; returns the plan dict (see _extract).

    previous_plan + t_now implement previous-feasible retention: any op in the
    previous plan that STARTED before t_now is pinned to its point and start;
    everything else is hinted. On failure the previous plan is returned.
    """
    blocked = blocked_points or set()
    m = cp_model.CpModel()
    site = sc["site"]
    H = sc["horizon_min"]
    W = sc["objective_weights"]

    points = [p for p in sc["service_points"]]
    charge_points = {"dcfc": [p for p in points if p["kind"] == "dcfc"],
                     "l2": [p for p in points if p["kind"] == "l2"]}
    wash_points = [p for p in points if p["kind"] == "wash_bay"]
    svc_points = [p for p in points if p["kind"] == "service_bay"]

    per_point_intervals: dict[str, list] = {p["id"]: [] for p in points}
    power_intervals, power_demands = [], []          # hard site cap
    soft_intervals, soft_demands = [], []            # soft target (same set)
    path_intervals = []                              # move resource
    obj_terms = []
    plan_vars = {}
    onpeak_terms = []
    move_count_vars = []

    pinned = {}
    if previous_plan:
        for a in previous_plan["assets"]:
            for op in a["ops"]:
                if op["start"] < t_now:
                    pinned[(a["aid"], op["op"])] = op

    for asset in sc["assets"]:
        # ---- charge: choose ONE point among capable charge points ------------
        cands = []
        for kind in ("dcfc", "l2"):
            for p in charge_points[kind]:
                if p["id"] in blocked and (asset.aid, "charge") not in pinned:
                    continue
                cands.append((kind, p))
        lits, chains = [], []
        for kind, p in cands:
            segs = charge_segments(sc, asset, p["kw"])
            if not segs:
                continue
            lit = m.NewBoolVar(f"{asset.aid}@{p['id']}")
            starts, ends, asset_side = [], [], []
            prev_end = None
            for si, seg in enumerate(segs):
                s = m.NewIntVar(asset.arrival_min, H, f"{asset.aid}.{p['id']}.s{si}")
                e = m.NewIntVar(asset.arrival_min, H, f"{asset.aid}.{p['id']}.e{si}")
                iv = m.NewOptionalIntervalVar(s, seg["minutes"], e, lit,
                                              f"{asset.aid}.{p['id']}.seg{si}")
                if prev_end is not None:
                    m.Add(s == prev_end).OnlyEnforceIf(lit)  # contiguous chain
                prev_end = e
                asset_side.append((iv, seg))
                starts.append(s); ends.append(e)
                # site power (hard + soft) — only while this candidate is chosen
                power_intervals.append(iv); power_demands.append(seg["kw"])
                soft_intervals.append(iv); soft_demands.append(seg["kw"])
                # on-peak overlap in kW-minutes (exact for one window)
                w0, w1 = site["onpeak_window_min"]
                ov_lo = m.NewIntVar(0, H, f"ovlo.{asset.aid}.{p['id']}.{si}")
                ov_hi = m.NewIntVar(0, H, f"ovhi.{asset.aid}.{p['id']}.{si}")
                m.AddMaxEquality(ov_lo, [s, m.NewConstant(w0)])
                m.AddMinEquality(ov_hi, [e, m.NewConstant(w1)])
                raw = m.NewIntVar(-H, H, f"ovraw.{asset.aid}.{p['id']}.{si}")
                m.Add(raw == ov_hi - ov_lo)
                ov = m.NewIntVar(0, H, f"ov.{asset.aid}.{p['id']}.{si}")
                m.AddMaxEquality(ov, [raw, m.NewConstant(0)])
                gated = m.NewIntVar(0, H, f"ovg.{asset.aid}.{p['id']}.{si}")
                m.Add(gated == ov).OnlyEnforceIf(lit)
                m.Add(gated == 0).OnlyEnforceIf(lit.Not())
                onpeak_terms.append(seg["kw"] * gated)
            # point-side occupancy: chain + cooldown (DCFC only) — the 2.5
            # min-gap ON THE POINT, exactly
            cool = site["dcfc_cooldown_min"] if kind == "dcfc" else 0
            occ_e = m.NewIntVar(0, H + cool, f"occend.{asset.aid}.{p['id']}")
            m.Add(occ_e == prev_end + cool).OnlyEnforceIf(lit)
            total = sum(seg["minutes"] for seg in segs) + cool
            occ = m.NewOptionalIntervalVar(starts[0], total, occ_e, lit,
                                           f"occ.{asset.aid}.{p['id']}")
            per_point_intervals[p["id"]].append(occ)
            chains.append((lit, kind, p, segs, starts, ends))
            lits.append(lit)
        m.AddExactlyOne(lits)

        # pin / hint from the previous plan (previous-feasible retention)
        key = (asset.aid, "charge")
        if key in pinned:
            prev = pinned[key]
            for lit, kind, p, segs, starts, ends in chains:
                if p["id"] == prev["point"]:
                    m.Add(lit == 1)
                    m.Add(starts[0] == prev["start"])
        elif previous_plan:
            prev_ops = {o["op"]: o for a in previous_plan["assets"]
                        if a["aid"] == asset.aid for o in a["ops"]}
            if "charge" in prev_ops:
                for lit, kind, p, segs, starts, ends in chains:
                    m.AddHint(lit, 1 if p["id"] == prev_ops["charge"]["point"] else 0)

        charge_start = m.NewIntVar(0, H, f"cs.{asset.aid}")
        charge_end = m.NewIntVar(0, H, f"ce.{asset.aid}")
        for lit, kind, p, segs, starts, ends in chains:
            m.Add(charge_start == starts[0]).OnlyEnforceIf(lit)
            m.Add(charge_end == ends[-1]).OnlyEnforceIf(lit)
        m.Add(charge_start >= asset.arrival_min)

        # ---- parallel ops INSIDE the charge window, serialized per asset -----
        par_ivs = []
        for op in asset.parallel_ops:
            d = sc["parallel_ops_menu"][op]["dur_min"]
            s = m.NewIntVar(0, H, f"{asset.aid}.{op}.s")
            e = m.NewIntVar(0, H, f"{asset.aid}.{op}.e")
            iv = m.NewIntervalVar(s, d, e, f"{asset.aid}.{op}")
            m.Add(s >= charge_start)
            m.Add(e <= charge_end)  # concurrency within the point: free throughput
            par_ivs.append((op, iv, s, e))
        if len(par_ivs) > 1:
            m.AddNoOverlap([iv for _, iv, _, _ in par_ivs])  # one tech per car

        # ---- wash (separate bay) + the move to it ---------------------------
        finish_candidates = [charge_end]
        n_moves = 0
        wash_tuple = insp_tuple = None
        if asset.needs_wash:
            wl = []
            ws = m.NewIntVar(0, H, f"{asset.aid}.wash.s")
            we = m.NewIntVar(0, H, f"{asset.aid}.wash.e")
            for p in wash_points:
                if p["id"] in blocked and (asset.aid, "wash") not in pinned:
                    continue
                lit = m.NewBoolVar(f"{asset.aid}.wash@{p['id']}")
                iv = m.NewOptionalIntervalVar(ws, 12, we, lit, f"{asset.aid}.wash.{p['id']}")
                per_point_intervals[p["id"]].append(iv)
                wl.append((lit, p))
            m.AddExactlyOne([l for l, _ in wl])
            ms = m.NewIntVar(0, H, f"{asset.aid}.mv1.s")
            me = m.NewIntVar(0, H, f"{asset.aid}.mv1.e")
            mv = m.NewIntervalVar(ms, site["move_duration_min"], me, f"{asset.aid}.mv1")
            path_intervals.append(mv)
            m.Add(ms >= charge_end)
            m.Add(ws >= me)
            n_moves += 1
            finish_candidates.append(we)
            wash_tuple = (ws, we, wl)
            key = (asset.aid, "wash")
            if key in pinned:
                m.Add(ws == pinned[key]["start"])
                for l, p in wl:
                    if p["id"] == pinned[key]["point"]:
                        m.Add(l == 1)

        # ---- inspect (service bay) after wash/charge ------------------------
        if asset.needs_inspect:
            isv = m.NewIntVar(0, H, f"{asset.aid}.insp.s")
            iev = m.NewIntVar(0, H, f"{asset.aid}.insp.e")
            il = []
            for p in svc_points:
                lit = m.NewBoolVar(f"{asset.aid}.insp@{p['id']}")
                iv = m.NewOptionalIntervalVar(isv, 20, iev, lit, f"{asset.aid}.insp.{p['id']}")
                per_point_intervals[p["id"]].append(iv)
                il.append((lit, p))
            m.AddExactlyOne([l for l, _ in il])
            ms = m.NewIntVar(0, H, f"{asset.aid}.mv2.s")
            me = m.NewIntVar(0, H, f"{asset.aid}.mv2.e")
            mv = m.NewIntervalVar(ms, site["move_duration_min"], me, f"{asset.aid}.mv2")
            path_intervals.append(mv)
            m.Add(ms >= (wash_tuple[1] if wash_tuple else charge_end))
            m.Add(isv >= me)
            n_moves += 1
            finish_candidates.append(iev)
            insp_tuple = (isv, iev, il)

        # ---- tardiness vs required-ready-time -------------------------------
        finish = m.NewIntVar(0, H, f"fin.{asset.aid}")
        m.AddMaxEquality(finish, finish_candidates)
        tardy = m.NewIntVar(0, H, f"tardy.{asset.aid}")
        m.Add(tardy >= finish - asset.ready_by_min)
        obj_terms.append(W["tardiness_per_min"] * tardy)
        move_count_vars.append(n_moves)

        plan_vars[asset.aid] = dict(chains=chains, charge_start=charge_start,
                                    charge_end=charge_end, par=par_ivs,
                                    wash=wash_tuple, insp=insp_tuple,
                                    finish=finish, tardy=tardy)

    # ---- resources ----------------------------------------------------------
    for pid, ivs in per_point_intervals.items():
        if ivs:
            m.AddNoOverlap(ivs)                       # a point serves one asset
    if path_intervals:
        m.AddCumulative(path_intervals, [1] * len(path_intervals),
                        site["path_capacity"])        # moves consume the yard path
    m.AddCumulative(power_intervals, power_demands, site["power_cap_kw_hard"])
    peak_excess = m.NewIntVar(0, site["power_cap_kw_hard"], "peak_excess_kw")
    m.AddCumulative(soft_intervals, soft_demands,
                    site["power_soft_target_kw"] + peak_excess)
    obj_terms.append(W["peak_excess_per_kw"] * peak_excess)
    obj_terms.extend([W["onpeak_kw_min"] * t for t in onpeak_terms])
    obj_terms.append(W["per_move"] * sum(move_count_vars))

    m.Minimize(sum(obj_terms))

    solver = cp_model.CpSolver()
    solver.parameters.random_seed = sc["seed"] % (2**31)
    solver.parameters.num_search_workers = 1          # determinism
    solver.parameters.max_time_in_seconds = time_limit_s
    status = solver.Solve(m)

    if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        # THE SITE IS NEVER WITHOUT A SCHEDULE: hand back the previous plan.
        if previous_plan is not None:
            return {**previous_plan, "retained_previous": True,
                    "solver_status": solver.StatusName(status)}
        raise RuntimeError(f"no schedule and no previous plan: {solver.StatusName(status)}")

    return _extract(sc, solver, status, plan_vars, peak_excess)


def _extract(sc, solver, status, plan_vars, peak_excess) -> dict:
    assets_out, proposals = [], []
    for asset in sc["assets"]:
        pv = plan_vars[asset.aid]
        ops = []
        for lit, kind, p, segs, starts, ends in pv["chains"]:
            if solver.Value(lit):
                ops.append({"op": "charge", "point": p["id"], "kind": kind,
                            "start": solver.Value(starts[0]),
                            "end": solver.Value(ends[-1]),
                            "segments": [
                                {"kw": seg["kw"], "minutes": seg["minutes"],
                                 "start": solver.Value(s), "end": solver.Value(e),
                                 **({"cold_start": True} if seg.get("cold_start") else {})}
                                for seg, (s, e) in zip(segs, zip(starts, ends))]})
                proposals.append({
                    "source": "cpsat", "action_context": "stall_assignment",
                    "entity_type": "vehicle", "entity_id": asset.aid,
                    "proposal": {"stall_id": p["id"], "stall_type": kind,
                                 "requested_kw": segs[0]["kw"], "abstain": False},
                })
        for op, iv, s, e in pv["par"]:
            ops.append({"op": op, "point": ops[0]["point"], "parallel": True,
                        "start": solver.Value(s), "end": solver.Value(e)})
        if pv["wash"]:
            ws, we, wl = pv["wash"]
            pid = next(p["id"] for l, p in wl if solver.Value(l))
            ops.append({"op": "wash", "point": pid,
                        "start": solver.Value(ws), "end": solver.Value(we)})
        if pv["insp"]:
            isv, iev, il = pv["insp"]
            pid = next(p["id"] for l, p in il if solver.Value(l))
            ops.append({"op": "inspect", "point": pid,
                        "start": solver.Value(isv), "end": solver.Value(iev)})
        assets_out.append({"aid": asset.aid, "class": asset.cls,
                           "ready_by": asset.ready_by_min,
                           "finish": solver.Value(pv["finish"]),
                           "tardy_min": solver.Value(pv["tardy"]),
                           "ops": sorted(ops, key=lambda o: (o["start"], o["op"]))})
    plan = {
        "scenario": sc["name"], "seed": sc["seed"],
        "solver_status": ("OPTIMAL" if status == cp_model.OPTIMAL else "FEASIBLE"),
        "objective": int(solver.ObjectiveValue()),
        "peak_excess_kw": solver.Value(peak_excess),
        "assets": sorted(assets_out, key=lambda a: a["aid"]),
        "proposals": sorted(proposals, key=lambda p: p["entity_id"]),
    }
    plan["plan_sha256"] = hashlib.sha256(
        json.dumps(plan, sort_keys=True).encode()).hexdigest()
    return plan
