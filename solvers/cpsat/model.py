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
    build order, and -- the part that is easy to get wrong -- a DETERMINISTIC
    work budget rather than a wall-clock one. CP-SAT's max_time_in_seconds is
    measured against the machine's clock, so a search cut off by it depends on
    how fast the box was that day: the same seed on a loaded runner returns a
    different plan. max_deterministic_time counts solver work units instead and
    cuts off at the same place on every machine. This file therefore sets a
    deterministic budget by default and leaves max_time_in_seconds unset.
    A caller may still pass time_limit_s to bound wall-clock, but the plan then
    carries plan["repro"]["reproducible"] = False unless it proved OPTIMAL
    (optimality is limit-independent; a truncated search is not).
    test_cpsat_prototype.py asserts byte-identical plans, including across
    processes and under CPU contention -- see T1 and T1b.

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

import ortools
from ortools.sat.python import cp_model

#: What a rejection costs when a scenario does not price one itself. Deliberately
#: an order of magnitude above the worst single-asset tardiness this horizon can
#: produce, so the solver rejects ONLY when the alternative is infeasibility --
#: never as a cheap way to duck a hard asset. A scenario that wants a different
#: trade sets objective_weights.rejection_penalty and owns the consequence.
DEFAULT_REJECTION_PENALTY = 100_000

#: What one asset moving to a different point between re-solves costs. ZERO by
#: default, and the term is then not built at all -- see the churn block in
#: build_and_solve for why "add it with weight 0" would not be equivalent.
DEFAULT_CHURN_PENALTY = 0


def _exactly_one_if_served(m, lits, served):
    """Exactly one of `lits`, or none at all when the asset is not served.

    With rejection off (`served is None`) this is literally AddExactlyOne, so the
    model is unchanged. With it on, a rejected asset must not still be handed a
    wash bay or an inspection slot -- points it would occupy for a service that
    is not happening.
    """
    if served is None:
        m.AddExactlyOne(lits)
    else:
        m.Add(sum(lits) == 1).OnlyEnforceIf(served)
        m.Add(sum(lits) == 0).OnlyEnforceIf(served.Not())


def _det_time(solver) -> float:
    """Deterministic work consumed by the solve.

    CpSolver only grew a `deterministic_time` accessor around 9.15; on 9.11 and
    earlier the number exists solely on the response proto. Reading just the
    accessor turns an older ortools into an AttributeError mid-solve instead of
    a clear version complaint -- and CI installs from a range, so "older" is a
    thing that can actually happen. The response field is present in both.
    """
    v = getattr(solver, "deterministic_time", None)
    if v is None:
        v = solver.response_proto.deterministic_time
    return float(v)


#: Deterministic work budget, in CP-SAT's machine-independent work units.
#: The four committed scenarios all prove OPTIMAL at <= 0.70 units (deck, the
#: 48-asset one, at 0.52), so this is ~7x headroom over anything shipped and
#: the limit is not expected to bind. It exists so an unexpectedly hard
#: instance terminates in bounded WORK rather than bounded time.
DET_BUDGET_S = 5.0

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
    return materialize(sc)


def materialize(sc: dict) -> dict:
    """Populate a scenario DICT's fleet -- the entry point for callers that
    build scenarios in memory (the production proposer bridge) rather than
    loading them from a committed file. Same function either way, so an
    in-memory world and a file world are indistinguishable to the solver."""
    sc["assets"] = _generate_assets(sc)
    return sc


def _generate_assets(sc: dict) -> list[Asset]:
    """Build the fleet. Two paths, both pure functions of the scenario file:

    - `assets_spec.explicit`: a DECLARED list of assets, verbatim. This is how a
      multimodal scenario states exactly which eVTOLs, drones and ground vehicles
      arrive when -- no generator opinions involved.
    - the legacy seeded generator, byte-for-byte what it always was (every magic
      number below is the historical default, kept so the committed artifacts
      regenerate identically; a scenario overrides them as data, never here).
    """
    spec = sc["assets_spec"]
    menu = sorted(sc["parallel_ops_menu"].keys())

    if "explicit" in spec:
        return [Asset(
            aid=a["aid"], cls=a["cls"], arrival_min=int(a["arrival_min"]),
            soc=int(a["soc"]), target_soc=int(a.get("target_soc", 90)),
            ready_by_min=int(a["ready_by_min"]),
            pack_temp_c=int(a.get("pack_temp_c", 18)),
            needs_wash=bool(a.get("needs_wash", False)),
            needs_inspect=bool(a.get("needs_inspect", False)),
            parallel_ops=list(a.get("parallel_ops", [])),
        ) for a in spec["explicit"]]

    rng = random.Random(sc["seed"])
    classes = sorted(sc["asset_classes"].keys())
    aw = spec.get("arrival_window_min", [0, 180])
    rd = spec.get("ready_delta_min", [150, 330])
    sr = spec.get("soc_range", [12, 55])
    target = spec.get("target_soc", 90)
    out = []
    for i in range(spec["count"]):
        cls = classes[i % len(classes)]
        arrival = rng.randrange(aw[0], aw[1])
        soc = rng.randrange(sr[0], sr[1])
        ready_by = arrival + rng.randrange(rd[0], rd[1])
        out.append(
            Asset(
                aid=f"AV-{i:02d}",
                cls=cls,
                arrival_min=arrival,
                soc=soc,
                target_soc=target,
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
    time_limit_s: float | None = None,
    det_budget_s: float = DET_BUDGET_S,
    objective_mode: str = "weighted",
    max_tardy_total: int | None = None,
    allow_rejection: bool = False,
) -> dict:
    """Solve the scenario; returns the plan dict (see _extract).

    previous_plan + t_now implement previous-feasible retention: any op in the
    previous plan that STARTED before t_now is pinned to its point and start;
    everything else is hinted. On failure the previous plan is returned.

    objective_mode selects what is minimized. The DEFAULT is byte-for-byte the
    original weighted objective -- T1-T8 and the committed C5 comparison depend on
    that and must not move. The other two modes exist for the lexicographic solve
    in policies/forward.py:

      "weighted"  -- the original multi-term objective (default; unchanged).
      "min_tardy" -- minimize total tardiness alone. Pass 1 of the lexicographic
                     solve: find T*, the best achievable service level.
      "min_peak"  -- minimize the site's instantaneous peak kW, subject to
                     sum(tardy) <= max_tardy_total (required in this mode).
                     Pass 2: hold service at T*, then spend every remaining
                     degree of freedom on flattening the load.

    Why instantaneous peak and not the billed interval-average: the billed peak
    is the mean over the tariff's demand interval, and modelling per-bucket
    averages would add O(assets x points x segments x buckets) overlap variables.
    The instantaneous peak is an UPPER BOUND on every interval average, so
    minimizing it can only over-serve the bill, never cheat it -- and the bill
    reported downstream is always computed from the actual curve by the real
    tariff (sites/tariff.py), not from this proxy.
    """
    if objective_mode not in ("weighted", "min_tardy", "min_peak"):
        raise ValueError(f"unknown objective_mode {objective_mode!r}")
    if objective_mode == "min_peak" and max_tardy_total is None:
        raise ValueError("min_peak requires max_tardy_total -- an unconstrained "
                         "peak minimization would buy flatness with unbounded "
                         "lateness, which is not a schedule anyone asked for")
    blocked = blocked_points or set()
    m = cp_model.CpModel()
    site = sc["site"]
    H = sc["horizon_min"]
    W = sc["objective_weights"]

    points = [p for p in sc["service_points"]]
    #: Charge-capable point kinds are DATA: an asset class declares charge_kinds
    #: (an ordered list -- candidate enumeration order is part of determinism),
    #: and points of those kinds are its candidates. The default is the legacy
    #: robotaxi pair so committed scenarios regenerate byte-identically. This is
    #: what lets an eVTOL pad, a swap dock or a mining refuel bay be a first-
    #: class point without editing solver code -- the kernel-purity test.
    def _charge_kinds(asset) -> tuple[str, ...]:
        return tuple(sc["asset_classes"][asset.cls].get("charge_kinds",
                                                        ("dcfc", "l2")))

    points_by_kind: dict[str, list] = {}
    for p in points:
        points_by_kind.setdefault(p["kind"], []).append(p)
    wash_points = [p for p in points if p["kind"] == "wash_bay"]
    svc_points = [p for p in points if p["kind"] == "service_bay"]
    #: Wash/inspect are the legacy finishing ops; their durations were literals
    #: (12 / 20) baked into the kernel until the separation audit flagged them.
    #: Now scenario data with the historical defaults. Their full generalization
    #: -- an arbitrary declared finishing chain -- is a known remaining step; it
    #: is vocabulary debt, not simulation bleed (SEPARATION.md).
    wash_min = int(site.get("wash_min", 12))
    inspect_min = int(site.get("inspect_min", 20))

    per_point_intervals: dict[str, list] = {p["id"]: [] for p in points}
    power_intervals, power_demands = [], []          # hard site cap
    soft_intervals, soft_demands = [], []            # soft target (same set)
    path_intervals = []                              # move resource
    obj_terms = []
    plan_vars = {}
    onpeak_terms = []
    move_count_vars = []
    served_vars = {}                                 # rejection: aid -> BoolVar
    reject_terms = []                                # rejection: the price of each
    churn_terms = []                                 # stability vs previous_plan
    churn_w = W.get("churn_per_change", DEFAULT_CHURN_PENALTY)

    pinned = {}
    if previous_plan:
        for a in previous_plan["assets"]:
            for op in a["ops"]:
                if op["start"] < t_now:
                    pinned[(a["aid"], op["op"])] = op

    for asset in sc["assets"]:
        #: When the asset leaves its charge point. Charging AND its parallel ops
        #: must both be done: an asset whose ops outlast the charge stays on the
        #: point the extra minutes rather than being forced onto a slower charger
        #: whose window happens to be long enough. Constrained below to
        #: max(charge_end, every parallel-op end).
        stay_end = m.NewIntVar(0, H, f"stay.{asset.aid}")

        # ---- charge: choose ONE point among capable charge points ------------
        cands = []
        for kind in _charge_kinds(asset):
            for p in points_by_kind.get(kind, []):
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
            #: Minimum gap ON THE POINT (CLAUDE.md 2.5). Declared per point as
            #: min_gap_min (a pad's turnaround separation, a swap dock's reload);
            #: the legacy default keeps DCFC cooldown exactly as it was.
            cool = int(p.get("min_gap_min",
                             site["dcfc_cooldown_min"] if kind == "dcfc" else 0))
            occ_e = m.NewIntVar(0, H + cool, f"occend.{asset.aid}.{p['id']}")
            #: 0069-fix analogue in the model: occupancy runs to stay_end (charge
            #: AND parallel ops), not merely to the end of the charge chain. The
            #: interval size is therefore variable, not the fixed chain length.
            m.Add(occ_e == stay_end + cool).OnlyEnforceIf(lit)
            occ_size = m.NewIntVar(0, H + cool, f"occsz.{asset.aid}.{p['id']}")
            occ = m.NewOptionalIntervalVar(starts[0], occ_size, occ_e, lit,
                                           f"occ.{asset.aid}.{p['id']}")
            per_point_intervals[p["id"]].append(occ)
            chains.append((lit, kind, p, segs, starts, ends))
            lits.append(lit)

        #: REJECTION (allow_rejection=True). Without it every asset MUST take a
        #: point, so a site that cannot serve everyone yields INFEASIBLE and the
        #: whole plan is lost -- the decide path then falls back to the previous
        #: schedule or raises. That is the wrong failure: a site under pressure
        #: should return a plan that serves most, and SAY WHO IT COULD NOT SERVE.
        #: A rejected asset surfaces as abstain=True in the proposal batch, which
        #: is a field ottoq_external_proposals already carries and the dispose
        #: path already understands -- no new vocabulary.
        #: OFF by default: the exactly-one below is then byte-for-byte the
        #: original constraint with no extra variables, so committed plans and
        #: the C5 comparison cannot move.
        if allow_rejection:
            served = m.NewBoolVar(f"served.{asset.aid}")
            m.Add(sum(lits) == 1).OnlyEnforceIf(served)
            m.Add(sum(lits) == 0).OnlyEnforceIf(served.Not())
        else:
            served = None
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
                #: CHURN. The hint above merely SUGGESTS the previous point; nothing
                #: PRICES leaving it, so a rolling re-solve will move an asset across
                #: the site for a one-minute objective gain. In the yard that is a
                #: real vehicle making a real trip for nothing, and it is the thing
                #: operators notice first about a scheduler they cannot trust.
                #: Built only when a weight is actually set -- "add the term with
                #: weight 0" is NOT equivalent, because the extra variable changes
                #: the search and can land on a different equally-optimal plan
                #: (measured across ortools versions: same objective, different
                #: schedule -- SOLVER_STATE.md 6.2). Absent weight, absent term.
                if churn_w > 0:
                    stay = next((lit for lit, kind, p, segs, starts, ends in chains
                                 if p["id"] == prev_ops["charge"]["point"]), None)
                    if stay is not None:
                        churn_terms.append(stay.Not())

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
            #: Ops run in parallel with the charge and MAY outlast it -- the asset
            #: then simply stays on the point until they finish (stay_end). The
            #: previous form here (e <= charge_end) silently required every op to
            #: fit INSIDE the charge window, which forced assets with more ops
            #: minutes than fast-charge minutes onto slow chargers: AV-05 (41 min
            #: of ops, 28 min of DCFC) was pushed to a 407-minute L2 session and
            #: ate 118 phantom tardy-minutes. CLAUDE.md 2.3 says ops run DURING
            #: charging for throughput; it does not say a car may never sit an
            #: extra 13 minutes to let its interior reset finish.
            par_ivs.append((op, iv, s, e))
        if len(par_ivs) > 1:
            m.AddNoOverlap([iv for _, iv, _, _ in par_ivs])  # one tech per car
        m.AddMaxEquality(stay_end,
                         [charge_end] + [e for _, _, _, e in par_ivs])

        # ---- wash (separate bay) + the move to it ---------------------------
        finish_candidates = [stay_end]
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
                iv = m.NewOptionalIntervalVar(ws, wash_min, we, lit, f"{asset.aid}.wash.{p['id']}")
                per_point_intervals[p["id"]].append(iv)
                wl.append((lit, p))
            #: A rejected asset does not get a wash bay either.
            _exactly_one_if_served(m, [l for l, _ in wl], served)
            ms = m.NewIntVar(0, H, f"{asset.aid}.mv1.s")
            me = m.NewIntVar(0, H, f"{asset.aid}.mv1.e")
            mv = m.NewIntervalVar(ms, site["move_duration_min"], me, f"{asset.aid}.mv1")
            path_intervals.append(mv)
            m.Add(ms >= stay_end)
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
                iv = m.NewOptionalIntervalVar(isv, inspect_min, iev, lit, f"{asset.aid}.insp.{p['id']}")
                per_point_intervals[p["id"]].append(iv)
                il.append((lit, p))
            _exactly_one_if_served(m, [l for l, _ in il], served)
            ms = m.NewIntVar(0, H, f"{asset.aid}.mv2.s")
            me = m.NewIntVar(0, H, f"{asset.aid}.mv2.e")
            mv = m.NewIntervalVar(ms, site["move_duration_min"], me, f"{asset.aid}.mv2")
            path_intervals.append(mv)
            m.Add(ms >= (wash_tuple[1] if wash_tuple else stay_end))
            m.Add(isv >= me)
            n_moves += 1
            finish_candidates.append(iev)
            insp_tuple = (isv, iev, il)

        # ---- tardiness vs required-ready-time -------------------------------
        finish = m.NewIntVar(0, H, f"fin.{asset.aid}")
        m.AddMaxEquality(finish, finish_candidates)
        tardy = m.NewIntVar(0, H, f"tardy.{asset.aid}")
        m.Add(tardy >= finish - asset.ready_by_min)
        if served is None:
            charged = tardy
            move_count_vars.append(n_moves)
        else:
            #: REJECTION HAS EXACTLY ONE PRICE. An unserved asset's finish/tardy
            #: vars still float (its parallel-op intervals are not optional and
            #: start no earlier than arrival), so without this it would pay the
            #: rejection penalty AND tardiness for work nobody did -- which makes
            #: rejection look dearer than it is and biases the solver back toward
            #: the infeasibility this feature exists to avoid.
            #:
            #: NOT DONE BY CONSTRAINING `tardy`. The first version of this line was
            #: `m.Add(tardy == 0).OnlyEnforceIf(served.Not())`, and it is a bug:
            #: combined with `tardy >= finish - ready_by` it forces
            #: finish <= ready_by for a REJECTED asset, which its own parallel-op
            #: durations can make impossible. Measured on the tight scenario with
            #: ready_delta_min [5, 12]: the model went INFEASIBLE -- rejection
            #: enabled, and still no plan. A price must be removed from the
            #: OBJECTIVE, never imposed as a constraint on an asset nobody is
            #: serving. Found by trying to falsify the guard rather than trusting
            #: it; T9b now pins the case.
            charged = m.NewIntVar(0, H, f"tardyc.{asset.aid}")
            m.Add(charged == tardy).OnlyEnforceIf(served)
            m.Add(charged == 0).OnlyEnforceIf(served.Not())
            mv = m.NewIntVar(0, n_moves, f"mv.{asset.aid}")
            m.Add(mv == n_moves).OnlyEnforceIf(served)
            m.Add(mv == 0).OnlyEnforceIf(served.Not())
            move_count_vars.append(mv)
            reject_terms.append(W.get("rejection_penalty", DEFAULT_REJECTION_PENALTY)
                                * served.Not())
            served_vars[asset.aid] = served
        obj_terms.append(W["tardiness_per_min"] * charged)

        plan_vars[asset.aid] = dict(served=served, charged_tardy=charged,
                                    chains=chains, charge_start=charge_start,
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

    #: CHARGED tardiness, not raw: the lexicographic passes must not bill a
    #: rejected asset either, and min_peak's `sum(all_tardy) <= max_tardy_total`
    #: would otherwise spend T* on assets nobody is serving.
    all_tardy = [pv["charged_tardy"] for pv in plan_vars.values()]
    #: CHURN AND REJECTION RIDE IN EVERY OBJECTIVE MODE, and they are kept out of
    #: obj_terms to make that possible. The lexicographic passes in
    #: policies/forward.py minimize tardiness alone and then peak alone -- they
    #: never read obj_terms -- so a rejection priced there would be free in pass 2,
    #: which could drop an asset while holding its tardiness target and report the
    #: same T*. `side` is zero-valued and zero-variable when neither feature is
    #: on, which is what keeps the default path byte-identical.
    side = sum(reject_terms) + (churn_w * sum(churn_terms) if churn_terms else 0)
    if objective_mode == "weighted":
        obj_terms.append(W["peak_excess_per_kw"] * peak_excess)
        obj_terms.extend([W["onpeak_kw_min"] * t for t in onpeak_terms])
        obj_terms.append(W["per_move"] * sum(move_count_vars))
        m.Minimize(sum(obj_terms) + side)
    elif objective_mode == "min_tardy":
        m.Minimize(sum(all_tardy) + side)
    else:  # min_peak
        m.Add(sum(all_tardy) <= max_tardy_total)
        #: peak_var IS the instantaneous site peak: a cumulative capacity the
        #: solver pays to raise. Same mechanism the soft target already uses.
        peak_var = m.NewIntVar(0, site["power_cap_kw_hard"], "site_peak_kw")
        m.AddCumulative(power_intervals, power_demands, peak_var)
        m.Minimize(peak_var + side)

    solver = cp_model.CpSolver()
    solver.parameters.random_seed = sc["seed"] % (2**31)
    solver.parameters.num_search_workers = 1          # determinism
    #: THE BINDING LIMIT IS DETERMINISTIC WORK, NOT WALL-CLOCK TIME.
    #: max_deterministic_time counts solver work units, so a search truncated
    #: by it truncates at the same node on every machine. max_time_in_seconds
    #: does not: under CPU contention the same seed yields a different plan
    #: (measured -- see test T1b). It is set ONLY if a caller explicitly asks
    #: for a wall-clock bound, and doing so is recorded in the plan.
    solver.parameters.max_deterministic_time = det_budget_s
    if time_limit_s is not None:
        solver.parameters.max_time_in_seconds = time_limit_s
    status = solver.Solve(m)

    if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        # THE SITE IS NEVER WITHOUT A SCHEDULE: hand back the previous plan.
        if previous_plan is not None:
            #: The retained plan is only as reproducible as the plan it came
            #: from -- AND, if a wall clock was set, the decision to retain at
            #: all may itself have been the clock's, so say so.
            prev_repro = dict(previous_plan.get("repro") or {})
            if time_limit_s is not None:
                prev_repro["reproducible"] = False
            return {**previous_plan, "retained_previous": True,
                    "solver_status": solver.StatusName(status),
                    **({"repro": prev_repro} if prev_repro else {})}
        raise RuntimeError(f"no schedule and no previous plan: {solver.StatusName(status)}")

    repro = {
        #: WHICH ORTOOLS PRODUCED THIS PLAN. Measured across 9.11 vs 9.15: every
        #: objective value is identical (the solver is not worse on either), but
        #: all four committed plans differ -- the two versions break ties among
        #: equally-optimal schedules differently, so WHICH asset goes to WHICH
        #: point at WHICH minute moves. The schedule ships; the objective is
        #: just a number about it. Reproducing a run therefore requires the
        #: version, which is why CI pins it and why it is recorded here.
        "ortools_version": ortools.__version__,
        "det_budget_s": det_budget_s,
        "deterministic_time": round(_det_time(solver), 6),
        "wall_limit_s": time_limit_s,
        #: TRUE means this plan is a function of (scenario, seed, config) alone.
        #: An OPTIMAL proof is limit-independent, so it holds whatever the
        #: limits were. Otherwise the search was truncated, and only a purely
        #: deterministic budget truncates it in the same place every time.
        "reproducible": status == cp_model.OPTIMAL or time_limit_s is None,
    }
    return _extract(sc, solver, status, plan_vars, peak_excess, repro)


def _extract(sc, solver, status, plan_vars, peak_excess, repro=None) -> dict:
    assets_out, proposals = [], []
    rejected = []
    for asset in sc["assets"]:
        pv = plan_vars[asset.aid]
        #: A REJECTED ASSET IS REPORTED, NEVER DROPPED. It leaves the plan with an
        #: empty op list and enters the proposal batch as abstain=True -- the field
        #: ottoq_external_proposals already carries for exactly this. A rejection
        #: that vanished from the output would be indistinguishable from an asset
        #: nobody asked about, which is the whole distinction cuopt_invocation_log
        #: exists to preserve on the other proposer.
        if pv["served"] is not None and not solver.Value(pv["served"]):
            rejected.append(asset.aid)
            proposals.append({
                "source": "cpsat", "action_context": "stall_assignment",
                "entity_type": "vehicle", "entity_id": asset.aid,
                "proposal": {"stall_id": None, "stall_type": None,
                             "requested_kw": None, "abstain": True,
                             "reason": "no feasible point within the site's capacity"},
            })
            assets_out.append({"aid": asset.aid, "class": asset.cls,
                               "ready_by": asset.ready_by_min, "served": False,
                               "finish": None, "tardy_min": None, "ops": []})
            continue
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
                           #: Only when rejection is ENABLED, so the default plan
                           #: dict -- and therefore plan_sha256 -- does not move.
                           **({"served": True} if pv["served"] is not None else {}),
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
        **({"rejected": sorted(rejected)} if any(
            pv["served"] is not None for pv in plan_vars.values()) else {}),
    }
    plan["plan_sha256"] = hashlib.sha256(
        json.dumps(plan, sort_keys=True).encode()).hexdigest()
    #: DELIBERATELY AFTER THE HASH. plan_sha256 is the identity of the SCHEDULE;
    #: it must not move because the box was slower today. The repro record is
    #: provenance about how that schedule was reached, so it rides alongside.
    if repro is not None:
        plan["repro"] = repro
    return plan
