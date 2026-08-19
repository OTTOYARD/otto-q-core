"""C8 Site Alpha harness — multi-tenant, CRN-paired, byte-reproducible.

Extends the C5 discipline (one seeded draw shared by every policy and
configuration) to the shared multi-tenant site: three tenants with duty-cycle-
shaped arrivals, class-capable points (a DCFC serves robotaxi|yard_tractor, an
AMR pad serves AMRs only), battery swap as the yard-tractor alternative to
charge, and the C7 failure scenarios as declarative transforms.

Honesty notes, stated once:
  * This is the OFFLINE harness (packs are data). The live twin hosts only the
    robotaxi pack today; running Site Alpha ON the kernel is C11's conformance
    job. Numbers here compare POLICIES under identical worlds; they are not
    live-twin throughput claims.
  * fifo/greedy do not model the site power cap (that is the point of having
    them as baselines): under power-loss scenarios their degradation appears as
    cap_violation_kw_min, while cap-aware policies degrade in tardiness instead.
    Both columns are reported; neither is hidden.
  * 'tug_unavailable' is not applicable to the packs on this site and is
    reported as such, never silently skipped.
"""

from __future__ import annotations

import hashlib
import json
import math
import random
from dataclasses import dataclass, field, replace
from pathlib import Path

HERE = Path(__file__).parent
SITE = HERE / "site_alpha.json"


# ---------------------------------------------------------------------------
# World generation (CRN: everything below is a pure function of the seed)
# ---------------------------------------------------------------------------

@dataclass
class Visit:
    vid: str
    tenant: str
    cls: str
    arrival: int
    soc: int
    target_soc: int
    ready_by: int
    cold: bool
    needs_wash: bool
    needs_calibration: bool
    parallel_ops: list = field(default_factory=list)
    refused_recall: bool = False
    immobile_extra_min: int = 0


def load_site(path=SITE) -> dict:
    return json.loads(Path(path).read_text())


def generate_visits(site: dict, tenants: list[str] | None = None,
                    phase_shift: dict[str, int] | None = None) -> list[Visit]:
    rng = random.Random(site["seed"])
    shift = phase_shift or {}
    out = []
    menu = sorted(site["parallel_ops_menu"].keys())
    # draw for EVERY tenant in config order regardless of inclusion, so the
    # random stream is identical across configurations (CRN across configs)
    for tname in sorted(site["tenants"]):
        t = site["tenants"][tname]
        n_visits = t["assets"] * t.get("visits_per_asset", 1)
        for i in range(n_visits):
            if "arrival_waves_min" in t:
                w0, wlen = t["arrival_waves_min"][i % len(t["arrival_waves_min"])]
                arrival = w0 + rng.randrange(0, wlen)
            else:
                a0, a1 = t["arrival_window_min"]
                arrival = rng.randrange(a0, a1)
            soc = rng.randrange(*t["soc_range"])
            ready = arrival + rng.randrange(*t["ready_delta_min"])
            cold = rng.random() < t["cold_p"]
            wash = rng.random() < t["needs_wash_p"]
            calib = rng.random() < t["needs_calibration_p"]
            pops = [op for op in menu if rng.random() < t["parallel_ops_p"]]
            if tenants is not None and tname not in tenants:
                continue
            arrival = min(site["horizon_min"] - 60, arrival + shift.get(tname, 0))
            out.append(Visit(
                vid=f"{tname[:4].upper()}-{i:02d}", tenant=tname, cls=t["class"],
                arrival=arrival, soc=soc, target_soc=t.get("target_soc", 90),
                ready_by=ready + shift.get(tname, 0),
                cold=cold, needs_wash=wash, needs_calibration=calib, parallel_ops=pops))
    return sorted(out, key=lambda v: (v.arrival, v.vid))


def charge_segments(site, visit: Visit, point) -> list[dict]:
    """Piecewise segments (C4 physics) OR a fixed-duration swap at a swap dock."""
    cls = site["asset_classes"][visit.cls]
    if point["kind"] == "swap_dock":
        return [{"kw": 0, "minutes": cls.get("swap_minutes", 10), "swap": True}]
    curve = sorted(cls["energy_curve"], key=lambda s: s["above_soc_pct"])
    breaks = [s["above_soc_pct"] for s in curve[1:]] + [100]
    segs, lo = [], visit.soc
    for edge, seg in zip(breaks, curve):
        hi = min(visit.target_soc, edge)
        if hi <= lo:
            continue
        kw = max(1, int(min(point["kw"], cls["max_charge_kw"]) * seg["accept_frac"]))
        minutes = max(1, math.ceil(60.0 * cls["battery_kwh"] * (hi - lo) / 100.0 / kw))
        segs.append({"kw": kw, "minutes": minutes})
        lo = hi
        if lo >= visit.target_soc:
            break
    if segs and visit.cold:
        segs[0] = {**segs[0], "minutes": segs[0]["minutes"] + site["site"]["cold_start_penalty_min"]}
    return segs


# ---------------------------------------------------------------------------
# Failure-scenario transforms (declarative; each returns a world modifier)
# ---------------------------------------------------------------------------

def apply_scenario(site: dict, visits: list[Visit], scenario: str):
    """Returns (visits, blocked: {point_id: (from_min, to_min)}, cap_windows,
    path_block_windows, note)."""
    rng = random.Random(site["seed"] * 31 + 7)   # scenario stream, seed-keyed
    blocked, caps, path_blocks, note = {}, [], [], ""
    H = site["horizon_min"]
    if scenario == "baseline":
        note = "no failure injected"
    elif scenario == "blocked_point":
        blocked = {"SA-DCFC-03": (0, H), "SA-WASH-01": (0, H)}
        note = "one DCFC + one wash bay blocked for the whole horizon"
    elif scenario == "overstay":
        vs = []
        for v in visits:
            if v.tenant == "robotaxi_operator_A" and rng.random() < 0.30:
                vs.append(replace(v, arrival=min(H - 60, v.arrival + 45),
                                  ready_by=v.ready_by + 45))
            else:
                vs.append(v)
        visits, note = vs, "30% of tenant-A returns overstay by 45 min (seeded pick)"
    elif scenario == "immobile_asset":
        vs, hit = [], 0
        for v in visits:
            if v.cls != "amr_pallet_2025" and hit < 2 and rng.random() < 0.08:
                vs.append(replace(v, immobile_extra_min=120)); hit += 1
            else:
                vs.append(v)
        visits, note = vs, f"{hit} assets immobile on-point (+120 min point hold)"
    elif scenario == "mid_session_charger_fault":
        blocked = {f"SA-DCFC-{i:02d}": (1100, H) for i in (1, 2, 4)}
        note = "3 DCFC fault at t=1100 (mid-surge) and stay down; sessions may not cross the fault"
    elif scenario == "zone_power_loss":
        caps = [(1050, 1230, 350)]
        note = "charging zone loses a feeder 1050-1230 (mid-surge): 350 kW available (cap-aware policies re-plan; cap-blind ones violate)"
    elif scenario == "human_path_crossing":
        path_blocks = [(1100, 1160)]
        note = "yard path closed 1100-1160 (mid-surge); move-ins may not cross the closure"
    elif scenario == "swap_dock_jam":
        blocked = {"SA-SWAP-01": (400, 700)}
        note = "swap dock jammed 400-700; tractors fall back to DCFC (their alternative)"
    elif scenario == "tug_unavailable":
        return visits, blocked, caps, path_blocks, "NOT APPLICABLE: no tug resource in the packs on this site (vertiport paper pack, H3/C11)"
    elif scenario == "work_side_recall_refusal":
        vs = []
        for v in visits:
            if v.tenant == "robotaxi_operator_A" and rng.random() < 0.25:
                vs.append(replace(v, arrival=min(H - 60, v.arrival + 90),
                                  ready_by=v.ready_by + 90, refused_recall=True))
            else:
                vs.append(v)
        visits, note = vs, "25% of tenant-A recalls refused; asset returns 90 min late (first-class handling = C9)"
    else:
        raise ValueError(scenario)
    return visits, blocked, caps, path_blocks, note


# ---------------------------------------------------------------------------
# The engine: class-capable point booking with blocking windows
# ---------------------------------------------------------------------------

class World:
    def __init__(self, site, blocked, caps, path_blocks):
        self.site = site
        self.blocked = blocked
        self.caps = caps
        self.path_blocks = path_blocks
        self.free = {p["id"]: 0 for p in site["service_points"]}
        self.points = {p["id"]: p for p in site["service_points"]}
        self.segments = {}
        self.charge_end = {}
        self.booked_point = {}
        self.turns = 0

    def charge_candidates(self, visit: Visit):
        kinds = self.site["asset_classes"][visit.cls]["charge_kinds"]
        return [p for p in self.site["service_points"]
                if p["kind"] in kinds and visit.cls in p["classes"]]

    def window_ok(self, pid, start, end):
        if pid in self.blocked:
            b0, b1 = self.blocked[pid]
            if start < b1 and b0 < end:
                return False
        return True

    def move_gate(self, start):
        """A booking's move-in occupies [start - move, start]; it may not cross
        a path closure. Returns the earliest legal start >= the given one."""
        mv = self.site["site"]["move_duration_min"]
        for (p0, p1) in self.path_blocks:
            if start - mv < p1 and p0 < start:
                start = p1 + mv
        return start

    def earliest(self, visit, point):
        t = self.move_gate(max(visit.arrival, self.free[point["id"]]))
        dur = sum(s["minutes"] for s in charge_segments(self.site, visit, point))
        dur += visit.immobile_extra_min
        if pid_blocked := self.blocked.get(point["id"]):
            b0, b1 = pid_blocked
            if t < b1 and b0 < t + dur:      # would overlap the outage: wait it out
                t = self.move_gate(b1)
        return t, dur

    def book(self, visit, point, start):
        segs, t = [], start
        for s in charge_segments(self.site, visit, point):
            segs.append({**s, "start": t, "end": t + s["minutes"]})
            t += s["minutes"]
        t += visit.immobile_extra_min
        cool = self.site["site"]["dcfc_cooldown_min"] if point["kind"] == "dcfc" else 0
        assert start >= self.free[point["id"]], f"double-booking {point['id']}"
        assert self.window_ok(point["id"], start, t), f"booked into outage on {point['id']}"
        assert start == self.move_gate(start), f"move-in crosses a path closure at {start}"
        self.free[point["id"]] = t + cool
        self.segments[visit.vid] = segs
        self.charge_end[visit.vid] = t
        self.booked_point[visit.vid] = point["id"]
        self.turns += 1
        return t


# ---------------------------------------------------------------------------
# Policies (the C5 four, class-capable). cpsat_alpha honors caps + path blocks.
# ---------------------------------------------------------------------------

def policy_fifo(world, visits):
    for v in visits:
        cands = world.charge_candidates(v)
        best = min(cands, key=lambda p: (world.earliest(v, p)[0], p["id"]))
        world.book(v, best, world.earliest(v, best)[0])


def policy_greedy(world, visits):
    for v in visits:
        cands = world.charge_candidates(v)
        best = min(cands, key=lambda p: (sum(world.earliest(v, p)), p["id"]))
        world.book(v, best, world.earliest(v, best)[0])


def policy_otto_q_asis(world, visits):
    # the live cursor's ordering: urgency (refused recalls are immediate on
    # return), lowest SoC, id; dcfc-first below the plug target
    for v in sorted(visits, key=lambda v: (v.arrival // 60, not v.refused_recall, v.soc, v.vid)):
        cands = world.charge_candidates(v)
        fast = [p for p in cands if p["kind"] in ("dcfc", "amr_pad")]
        slow = [p for p in cands if p["kind"] not in ("dcfc", "amr_pad")]
        pref = (fast + slow) if v.soc < 55 else (slow + fast) if slow else fast
        best = min(pref, key=lambda p: (world.earliest(v, p)[0], p["id"]))
        world.book(v, best, world.earliest(v, best)[0])


CPSAT_SLOT_MIN = 5          # model granularity; durations round UP -> decoded
                            # minute-resolution schedule can only be looser
CPSAT_DTIME = 10.0          # deterministic-time budget: reproducible cutoff for
                            # a pinned ortools build, unlike wall-clock


def policy_cpsat_alpha(world, visits):
    from ortools.sat.python import cp_model
    site = world.site
    G = CPSAT_SLOT_MIN
    m = cp_model.CpModel()
    H = site["horizon_min"]
    Hg = H // G + 200
    per_point, hard_int, hard_dem = {pid: [] for pid in world.points}, [], []
    caps = world.caps
    chosen = {}
    obj = []
    for v in visits:
        lits = []
        for p in world.charge_candidates(v):
            segs = charge_segments(site, v, p)
            dur = sum(s["minutes"] for s in segs) + v.immobile_extra_min
            dur_g = -(-dur // G)
            lit = m.NewBoolVar(f"{v.vid}@{p['id']}")
            s0 = m.NewIntVar(-(-v.arrival // G), Hg, f"{v.vid}.{p['id']}.s")
            occ = dur + (site["site"]["dcfc_cooldown_min"] if p["kind"] == "dcfc" else 0)
            occ_g = -(-occ // G)
            e0 = m.NewIntVar(0, Hg + occ_g, f"{v.vid}.{p['id']}.e")
            iv = m.NewOptionalIntervalVar(s0, occ_g, e0, lit, f"occ.{v.vid}.{p['id']}")
            per_point[p["id"]].append(iv)
            if p["id"] in world.blocked:
                b0, b1 = world.blocked[p["id"]]
                # outside the outage entirely (conservative rounding): end at or
                # before floor(b0/G), or start at or after ceil(b1/G)
                before = m.NewBoolVar(f"b.{v.vid}.{p['id']}")
                m.Add(s0 + dur_g <= b0 // G).OnlyEnforceIf([lit, before])
                m.Add(s0 >= -(-b1 // G)).OnlyEnforceIf([lit, before.Not()])
            for bi, (p0, p1) in enumerate(world.path_blocks):
                # move-in [start-move, start] may not cross a path closure:
                # start at or before the closure opens, or move in after it
                mv = site["site"]["move_duration_min"]
                pb = m.NewBoolVar(f"pb{bi}.{v.vid}.{p['id']}")
                m.Add(s0 <= p0 // G).OnlyEnforceIf([lit, pb])
                m.Add(s0 >= -(-(p1 + mv) // G)).OnlyEnforceIf([lit, pb.Not()])
            kwmax = max((s["kw"] for s in segs), default=0)
            if kwmax > 0:
                piv = m.NewOptionalIntervalVar(s0, dur_g, m.NewIntVar(0, Hg + dur_g, f"pe.{v.vid}.{p['id']}"),
                                               lit, f"pow.{v.vid}.{p['id']}")
                hard_int.append(piv); hard_dem.append(kwmax)
            chosen[(v.vid, p["id"])] = (lit, s0, dur, dur_g, segs)
            lits.append(lit)
        m.AddExactlyOne(lits)
        # finish in real MINUTES (start slot * G + exact duration), so the
        # tardiness objective stays minute-true despite the coarse grid
        fin = m.NewIntVar(0, (Hg + 200) * G, f"fin.{v.vid}")
        for p in world.charge_candidates(v):
            lit, s0, dur, _, _ = chosen[(v.vid, p["id"])]
            m.Add(fin == s0 * G + dur).OnlyEnforceIf(lit)
        tardy = m.NewIntVar(0, (Hg + 200) * G, f"tardy.{v.vid}")
        m.Add(tardy >= fin - v.ready_by)
        obj.append(site["objective_weights"]["tardiness_per_min"] * tardy)
    for pid, ivs in per_point.items():
        if ivs:
            m.AddNoOverlap(ivs)
    m.AddCumulative(hard_int, hard_dem, int(site["site"]["power_cap_kw_hard"]))
    for (c0, c1, ckw) in caps:
        # reduced cap enforced across the (conservatively widened) window via a
        # dedicated cumulative on an activity-gated copy of powered intervals
        w0, w1 = c0 // G, -(-c1 // G)
        cap_ints, cap_dem = [], []
        for (vid, pid), (lit, s0, dur, dur_g, segs) in chosen.items():
            kwmax = max((s["kw"] for s in segs), default=0)
            if kwmax == 0:
                continue
            inwin = m.NewBoolVar(f"w.{vid}.{pid}.{c0}")
            m.Add(s0 < w1).OnlyEnforceIf(inwin)
            m.Add(s0 + dur_g > w0).OnlyEnforceIf(inwin)
            outa = m.NewBoolVar(f"wo.{vid}.{pid}.{c0}")
            m.Add(s0 + dur_g <= w0).OnlyEnforceIf([inwin.Not(), outa])
            m.Add(s0 >= w1).OnlyEnforceIf([inwin.Not(), outa.Not()])
            act = m.NewBoolVar(f"wa.{vid}.{pid}.{c0}")
            m.AddBoolAnd([lit, inwin]).OnlyEnforceIf(act)
            m.AddBoolOr([lit.Not(), inwin.Not()]).OnlyEnforceIf(act.Not())
            iv = m.NewOptionalIntervalVar(s0, dur_g, m.NewIntVar(0, Hg + dur_g, f"we.{vid}.{pid}.{c0}"),
                                          act, f"wiv.{vid}.{pid}.{c0}")
            cap_ints.append(iv); cap_dem.append(kwmax)
        if cap_ints:
            m.AddCumulative(cap_ints, cap_dem, int(ckw))
    m.Minimize(sum(obj))
    # warm start from the as-is schedule (hints need not be feasible on the
    # coarse grid; they steer the first descent)
    hint_world = World(site, world.blocked, caps, world.path_blocks)
    policy_otto_q_asis(hint_world, visits)
    for (vid, pid), (lit, s0, dur, dur_g, segs) in chosen.items():
        if hint_world.booked_point.get(vid) == pid:
            m.AddHint(lit, 1)
            m.AddHint(s0, min(Hg, -(-hint_world.segments[vid][0]["start"] // G)))
    solver = cp_model.CpSolver()
    solver.parameters.random_seed = site["seed"] % (2 ** 31)
    solver.parameters.num_search_workers = 1
    solver.parameters.max_deterministic_time = CPSAT_DTIME
    solver.parameters.max_time_in_seconds = 600.0   # hang backstop only
    status = solver.Solve(m)
    name = solver.StatusName(status)
    if name not in ("OPTIMAL", "FEASIBLE"):
        raise RuntimeError(f"cpsat_alpha: {name}")
    picks = []
    for v in visits:
        for p in world.charge_candidates(v):
            lit, s0, dur, dur_g, _ = chosen[(v.vid, p["id"])]
            if solver.Value(lit):
                picks.append((solver.Value(s0) * G, v, p))
    for start, v, p in sorted(picks, key=lambda x: (x[0], x[1].vid)):
        world.book(v, p, start)
    return name


POLICIES = ["fifo", "greedy", "otto_q_asis", "cpsat_alpha"]


# ---------------------------------------------------------------------------
# Metrics + runner
# ---------------------------------------------------------------------------

def run_cell(site, scenario, policy, tenants=None, phase_shift=None):
    visits = generate_visits(site, tenants=tenants, phase_shift=phase_shift)
    visits, blocked, caps, path_blocks, note = apply_scenario(site, visits, scenario)
    visits = sorted(visits, key=lambda v: (v.arrival, v.vid))  # transforms shift arrivals
    if note.startswith("NOT APPLICABLE"):
        return {"scenario": scenario, "policy": policy, "status": "not_applicable", "note": note}
    world = World(site, blocked, caps, path_blocks)
    status = "ok"
    if policy == "fifo":
        policy_fifo(world, visits)
    elif policy == "greedy":
        policy_greedy(world, visits)
    elif policy == "otto_q_asis":
        policy_otto_q_asis(world, visits)
    elif policy == "cpsat_alpha":
        status = policy_cpsat_alpha(world, visits)
    # metrics
    events = []
    per = {}
    for v in visits:
        segs = world.segments[v.vid]
        for s in segs:
            if s["kw"] > 0:
                events.append((s["start"], s["kw"])); events.append((s["end"], -s["kw"]))
        wait = segs[0]["start"] - v.arrival
        fin = world.charge_end[v.vid]
        per[v.vid] = {"tenant": v.tenant, "wait": wait, "tardy": max(0, fin - v.ready_by)}
    events.sort()
    load = peak = 0
    cap_viol = 0
    tl = sorted(set([e[0] for e in events] + [c for w in world.caps for c in w[:2]]))
    # exact stepwise load for peak + cap violation kW-min
    stepload, prev_t, cur = [], None, 0
    for t, d in events:
        if prev_t is not None and t > prev_t:
            stepload.append((prev_t, t, cur))
        cur += d; peak = max(peak, cur); prev_t = t
    for (a, b, kw) in stepload:
        for (c0, c1, ckw) in world.caps:
            ov = max(0, min(b, c1) - max(a, c0))
            if ov > 0 and kw > ckw:
                cap_viol += (kw - ckw) * ov
    waits = sorted(p["wait"] for p in per.values())
    p95 = waits[max(0, int(round(0.95 * len(waits))) - 1)] if waits else 0
    return {
        "scenario": scenario, "policy": policy, "status": status,
        "seed": site["seed"], "visits": len(visits), "note": note,
        "metrics": {
            "total_tardy_min": sum(p["tardy"] for p in per.values()),
            "p95_wait_min": p95,
            "peak_site_kw": peak,
            "cap_violation_kw_min": int(cap_viol),
            "turns": world.turns,
        },
        "per_tenant_tardy": {t: sum(p["tardy"] for p in per.values() if p["tenant"] == t)
                             for t in sorted({p["tenant"] for p in per.values()})},
    }


def run_id_of(cell) -> str:
    return "SA-" + hashlib.sha256(json.dumps(cell, sort_keys=True).encode()).hexdigest()[:12]
