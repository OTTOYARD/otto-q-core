"""C4 CP-SAT prototype tests — plain-assert scripts, house style.

Run:  python3 solvers/cpsat/test_cpsat_prototype.py
"""
import json
import math
import re
import multiprocessing as mp
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from model import (  # noqa: E402
    DEFAULT_REJECTION_PENALTY, build_and_solve, charge_segments, load_scenario,
    materialize,
)
import ortools  # noqa: E402
from ortools.sat.python import cp_model  # noqa: E402

SC_PATH = Path(__file__).parent / "scenario_canonical.json"


def overlapping(a, b):
    return a["start"] < b["end"] and b["start"] < a["end"]


def pinned_ortools_version() -> str:
    """The pinned OR-Tools version, read from requirements.txt — the one file that carries it.

    Parsed rather than duplicated on purpose: a constant here would be a second copy of a number
    whose whole job is to be singular, and the two would drift the first time one was bumped.
    """
    req = (Path(__file__).parents[2] / "requirements.txt").read_text()
    m = re.search(r"^ortools==(\S+)\s*$", req, re.M)
    assert m, "requirements.txt no longer pins ortools with =="
    return m.group(1)


def _variant(*, charge_points: int, horizon_min: int, churn: int = 0,
             assets: int | None = None) -> dict:
    """The canonical scenario with its charge capacity and horizon squeezed.

    Built in memory via `materialize` rather than written to a file, so the
    committed scenarios stay the only committed scenarios.
    """
    sc = json.loads(SC_PATH.read_text())
    charge = [p for p in sc["service_points"] if p["kind"] in ("dcfc", "l2")][:charge_points]
    other = [p for p in sc["service_points"] if p["kind"] not in ("dcfc", "l2")]
    sc["service_points"] = charge + other
    sc["horizon_min"] = horizon_min
    if churn:
        sc["objective_weights"]["churn_per_change"] = churn
    if assets is not None:
        sc["assets_spec"]["count"] = assets
    return sc


def _charge_points(plan) -> dict:
    return {a["aid"]: next((o["point"] for o in a["ops"] if o["op"] == "charge"), None)
            for a in plan["assets"]}


def _resolve_pair(churn: int, blocked: set[str]):
    """Solve, then re-solve an hour in with a point out of service.

    Returns (first, again, moved) where `moved` names the assets that changed
    charge point between the two.
    """
    sc = json.loads(SC_PATH.read_text())
    if churn:
        sc["objective_weights"]["churn_per_change"] = churn
    first = build_and_solve(materialize(json.loads(json.dumps(sc))))
    again = build_and_solve(materialize(json.loads(json.dumps(sc))), t_now=60,
                            previous_plan=first, blocked_points=set(blocked))
    a, b = _charge_points(first), _charge_points(again)
    return first, again, [k for k in sorted(a) if a[k] != b[k]]


def _burners() -> int:
    """Enough busy processes to contend every core, oversubscribed so the load
    is real even on a single-core runner."""
    return max(2, (os.cpu_count() or 2) + 1)


def _spin(stop):
    x = 0
    while not stop.is_set():
        x = (x * 1103515245 + 12345) % (2**61 - 1)


def _solve_under_load(det_budget_s: float) -> dict:
    procs, stop = [], mp.Event()
    for _ in range(_burners()):
        pr = mp.Process(target=_spin, args=(stop,), daemon=True)
        pr.start()
        procs.append(pr)
    time.sleep(0.3)                       # let the load actually land
    try:
        return build_and_solve(load_scenario(SC_PATH), det_budget_s=det_budget_s)
    finally:
        stop.set()
        for pr in procs:
            pr.join(timeout=5)


def _capture_params(call):
    """Run `call` and hand back the CpSolverParameters it actually used."""
    seen, real = {}, cp_model.CpSolver.Solve

    def spy(self, model, *a, **k):
        seen["params"] = self.parameters
        return real(self, model, *a, **k)

    cp_model.CpSolver.Solve = spy
    try:
        call()
    finally:
        cp_model.CpSolver.Solve = real
    return seen["params"]


def main():
    print(f"ortools {ortools.__version__}")
    sc = load_scenario(SC_PATH)

    # T1 — DETERMINISM UNDER FIXED SEED: two independent solves, byte-identical.
    p1 = build_and_solve(load_scenario(SC_PATH))
    p2 = build_and_solve(load_scenario(SC_PATH))
    assert p1["plan_sha256"] == p2["plan_sha256"], "T1 FAIL: plans differ across solves"
    print(f"T1 PASS determinism: sha256 {p1['plan_sha256'][:16]}… identical across 2 solves "
          f"(status={p1['solver_status']}, objective={p1['objective']})")
    #: T1 ON ITS OWN PROVES ALMOST NOTHING, and it is worth being blunt about
    #: why. This scenario reaches OPTIMAL, so no budget ever binds and the two
    #: solves agree for a reason that has nothing to do with the budget being
    #: sound. The determinism question only has teeth when the search is CUT
    #: OFF -- that is T1b.
    assert p1["solver_status"] == "OPTIMAL", "T1 assumption changed: see T1b"

    # T1b — THE BUDGET IS DETERMINISTIC WORK, NOT WALL-CLOCK TIME.
    # A truncating budget, solved twice: once idle, once with every core
    # contended. CP-SAT's max_time_in_seconds is measured against the machine's
    # clock, so a search it truncates depends on how loaded the box was --
    # measured on this scenario at a 1.2s wall limit: objective 7311 idle vs
    # 10261 loaded, same seed, same config, different plan. max_deterministic_time
    # counts solver work units and cuts off at the same node on any machine.
    # This is the test that decides whether "no number ships without a run ID"
    # is true or decorative.
    tiny = 0.06
    idle = build_and_solve(load_scenario(SC_PATH), det_budget_s=tiny)
    assert idle["solver_status"] != "OPTIMAL", (
        f"T1b FAIL: det budget {tiny} did not truncate the search "
        "(status OPTIMAL) -- the test proves nothing; lower the budget")
    loaded = _solve_under_load(tiny)
    assert idle["plan_sha256"] == loaded["plan_sha256"], (
        "T1b FAIL: a truncated solve returned different plans idle vs under "
        f"CPU contention -- {idle['plan_sha256'][:16]} (obj {idle['objective']}) "
        f"vs {loaded['plan_sha256'][:16]} (obj {loaded['objective']}). "
        "The binding limit is not machine-independent.")
    print(f"T1b PASS truncated solve (status={idle['solver_status']}, det budget "
          f"{tiny}) byte-identical idle vs {_burners()} contending processes: "
          f"sha256 {idle['plan_sha256'][:16]}…")

    # T1c — THE POSTURE THAT MAKES T1b HOLD, asserted directly so it cannot
    # regress quietly: a default solve sets a deterministic budget and sets NO
    # wall-clock limit. A plan whose search a wall clock may have decided is
    # labelled non-reproducible, because it is not a function of
    # (scenario, seed, config) alone.
    params = _capture_params(lambda: build_and_solve(load_scenario(SC_PATH)))
    #: CP-SAT's own default for both limits is +inf, so "finite" IS "set".
    #: Read that way rather than via protobuf presence, which this build of
    #: ortools does not expose on its parameters wrapper.
    assert math.isfinite(params.max_deterministic_time), (
        "T1c FAIL: no deterministic budget set")
    assert math.isinf(params.max_time_in_seconds), (
        "T1c FAIL: build_and_solve set a wall-clock limit by default "
        f"({params.max_time_in_seconds}s) -- that is the T1b failure mode")
    assert params.num_search_workers == 1, "T1c FAIL: not single-worker"
    #: A WALL CLOCK IS MACHINE-DEPENDENT BY CONSTRUCTION -- that is T1b's whole
    #: point -- so no fixed wall limit can be relied on to truncate THIS scenario
    #: on every runner. Measured: 1.2 s truncated it (FEASIBLE) on a box that
    #: solves it in 2.6 s, and reached OPTIMAL on a CI runner (PR #144,
    #: 2026-09-02), where the old assertion then accused a correctly-labelled
    #: OPTIMAL plan of lying. The label is asserted on whichever branch this
    #: machine produced, and the clock-decided path is pinned deterministically
    #: below through the retained-plan route with a limit no machine can beat.
    walled = build_and_solve(load_scenario(SC_PATH), time_limit_s=1.2,
                             det_budget_s=1e9)
    if walled["solver_status"] == "OPTIMAL":
        assert walled["repro"]["reproducible"] is True, (
            "T1c FAIL: an OPTIMAL plan was labelled non-reproducible -- "
            "optimality is limit-independent")
        print("T1c note: the 1.2 s wall clock did not bind on this machine "
              "(OPTIMAL); the truncated branch is exercised via the retained-plan route")
    else:
        assert walled["repro"]["reproducible"] is False, (
            "T1c FAIL: a wall-clock-truncated plan claimed to be reproducible")
    #: 1 ms cannot finish presolve on this scenario: the solver returns UNKNOWN,
    #: the previous plan is retained, and the retention itself was the clock's
    #: decision -- so the retained plan must be labelled non-reproducible even
    #: though the plan it came from (idle, T1b) is reproducible.
    clocked = build_and_solve(load_scenario(SC_PATH), time_limit_s=0.001,
                              det_budget_s=1e9, previous_plan=idle)
    assert clocked["solver_status"] != "OPTIMAL", (
        "T1c FAIL: a 1 ms wall clock reached OPTIMAL -- the test proves nothing "
        "on this machine; lower the limit")
    assert clocked["repro"]["reproducible"] is False, (
        "T1c FAIL: a plan whose truncation or retention a wall clock decided "
        f"claimed to be reproducible (status={clocked['solver_status']}, "
        f"retained={clocked.get('retained_previous', False)})")
    assert idle["repro"]["reproducible"] is True, (
        "T1c FAIL: a deterministically-budgeted plan was not labelled reproducible")
    print("T1c PASS default solve is deterministically budgeted with no "
          f"wall-clock limit; wall-clocked plans are labelled reproducible=False "
          f"(1.2 s: {walled['solver_status']}; 1 ms: {clocked['solver_status']}, "
          f"retained={clocked.get('retained_previous', False)})")

    # T1d — ACROSS PROCESSES, not just twice in one. Repeat solves in a single
    # process can agree through warmed state that a fresh process would not have.
    fresh = subprocess.run(
        [sys.executable, "-c",
         "import sys,json;sys.path.insert(0,%r);"
         "from model import build_and_solve, load_scenario;"
         "print(build_and_solve(load_scenario(%r))['plan_sha256'])"
         % (str(Path(__file__).parent), str(SC_PATH))],
        capture_output=True, text=True, check=True).stdout.strip()
    assert fresh == p1["plan_sha256"], (
        f"T1d FAIL: fresh process solved to {fresh[:16]}, this one to "
        f"{p1['plan_sha256'][:16]}")
    print(f"T1d PASS fresh-process solve matches: sha256 {fresh[:16]}…")

    # T2 — POINT EXCLUSIVITY + DCFC COOLDOWN (18 min) ON THE POINT.
    cool = sc["site"]["dcfc_cooldown_min"]
    by_point = {}
    for a in p1["assets"]:
        for op in a["ops"]:
            if op.get("parallel"):
                continue
            by_point.setdefault(op["point"], []).append(op)
    for pid, ops in by_point.items():
        kind = next(p["kind"] for p in sc["service_points"] if p["id"] == pid)
        ops = sorted(ops, key=lambda o: o["start"])
        for x, y in zip(ops, ops[1:]):
            assert not overlapping(x, y), f"T2 FAIL: overlap on {pid}"
            if kind == "dcfc":
                gap = y["start"] - x["end"]
                assert gap >= cool, f"T2 FAIL: {pid} gap {gap} < cooldown {cool}"
    print(f"T2 PASS point exclusivity + {cool}-min DCFC cooldown held on every point")

    # T3 — SITE POWER CAP (hard) never exceeded; peak excess reported vs soft target.
    events = []
    for a in p1["assets"]:
        for op in a["ops"]:
            if op["op"] == "charge":
                for seg in op["segments"]:
                    events.append((seg["start"], seg["kw"]))
                    events.append((seg["end"], -seg["kw"]))
    events.sort()
    load, peak = 0, 0
    for _, d in events:
        load += d
        peak = max(peak, load)
    assert peak <= sc["site"]["power_cap_kw_hard"], f"T3 FAIL: peak {peak} kW over hard cap"
    assert peak <= sc["site"]["power_soft_target_kw"] + p1["peak_excess_kw"], \
        "T3 FAIL: reported peak_excess understates the true peak"
    print(f"T3 PASS site power: true peak {peak} kW <= hard cap "
          f"{sc['site']['power_cap_kw_hard']} kW; excess over soft target = {p1['peak_excess_kw']} kW")

    # T4 — PIECEWISE CHARGING: any asset crossing 70% has >=2 segments with
    # strictly decreasing kW; cold packs carry the cold-start duration modifier.
    saw_piecewise = saw_cold = False
    for a in p1["assets"]:
        for op in a["ops"]:
            if op["op"] != "charge":
                continue
            kws = [s["kw"] for s in op["segments"]]
            if len(kws) >= 2:
                assert all(x > y for x, y in zip(kws, kws[1:])), \
                    f"T4 FAIL: non-decreasing segment kW {kws} on {a['aid']}"
                saw_piecewise = True
            if any(s.get("cold_start") for s in op["segments"]):
                saw_cold = True
    assert saw_piecewise, "T4 FAIL: no piecewise charge in scenario (raise SoC spread)"
    assert saw_cold, "T4 FAIL: no cold-start modifier exercised"
    print("T4 PASS piecewise segments taper above 70% SoC; cold-start modifier applied")

    # T5 — CONCURRENCY WITHIN A POINT: parallel ops start during the asset's time
    # on its charge point and MAY outlast the charge (the asset then stays on the
    # point until they finish); serialized per asset; MOVES are scheduled ops with
    # duration and depart only after charge AND ops are done. The earlier form of
    # this test asserted ops END inside the charge window -- that was the
    # over-constraint itself (it forced AV-05, with 41 min of ops and 28 min of
    # DCFC, onto a 407-minute L2 session for 118 phantom tardy-minutes), so it
    # was rewritten deliberately when the model was fixed, not relaxed casually.
    mv = sc["site"]["move_duration_min"]
    for a in p1["assets"]:
        charge = next(o for o in a["ops"] if o["op"] == "charge")
        pars = [o for o in a["ops"] if o.get("parallel")]
        stay_end = max([charge["end"]] + [x["end"] for x in pars])
        for x in pars:
            assert x["start"] >= charge["start"], \
                f"T5 FAIL: parallel op starts before the asset is on-point on {a['aid']}"
            assert x["point"] == charge["point"], \
                f"T5 FAIL: parallel op on a different point on {a['aid']}"
        for x, y in zip(sorted(pars, key=lambda o: o["start"]),
                        sorted(pars, key=lambda o: o["start"])[1:]):
            assert not overlapping(x, y), f"T5 FAIL: parallel ops overlap on {a['aid']}"
        wash = [o for o in a["ops"] if o["op"] == "wash"]
        if wash:
            assert wash[0]["start"] >= stay_end + mv, \
                f"T5 FAIL: wash starts before charge+ops end plus the {mv}-min move on {a['aid']}"
    print(f"T5 PASS concurrency-in-point (ops may outlast the charge; departure "
          f"waits for both) + {mv}-min moves as scheduled operations")

    # T6 — ROLLING RE-SOLVE WITH PREVIOUS-FEASIBLE RETENTION: block a DCFC at
    # t=120; every op already started keeps its point and start, and the new
    # plan routes nobody NEW to the blocked point after t_now.
    t_now, blocked = 120, {"NASH-DCFC-02"}
    p3 = build_and_solve(load_scenario(SC_PATH), t_now=t_now,
                         previous_plan=p1, blocked_points=blocked)
    prev_started = {(a["aid"], o["op"]): o for a in p1["assets"]
                    for o in a["ops"] if o["start"] < t_now and not o.get("parallel")}
    new_ops = {(a["aid"], o["op"]): o for a in p3["assets"] for o in a["ops"]}
    for k, prev in prev_started.items():
        cur = new_ops[k]
        assert cur["point"] == prev["point"] and cur["start"] == prev["start"], \
            f"T6 FAIL: started op {k} was moved by re-solve"
    for a in p3["assets"]:
        for op in a["ops"]:
            if op.get("parallel"):
                # in-car work rides the vehicle at its (possibly pinned) point;
                # a blocked charger takes no NEW sessions but doesn't eject cars
                continue
            if op["point"] in blocked and op["start"] >= t_now:
                assert (a["aid"], op["op"]) in prev_started, \
                    f"T6 FAIL: new work routed to blocked point {op['point']}"
    assert not p3.get("retained_previous"), "T6: expected a fresh feasible re-solve"
    print(f"T6 PASS re-solve at t={t_now} with {blocked} blocked: "
          f"{len(prev_started)} started ops retained, no new work on the blocked point")

    # T7 — PROPOSE, NEVER DISPOSE: output is ottoq_external_proposals-shaped.
    for pr in p1["proposals"]:
        assert pr["source"] == "cpsat" and pr["action_context"] == "stall_assignment"
        assert set(pr["proposal"]) >= {"stall_id", "stall_type", "requested_kw", "abstain"}
    assert len(p1["proposals"]) == len(sc["assets"])
    print(f"T7 PASS {len(p1['proposals'])} proposals in ottoq_external_proposals shape "
          "(source='cpsat'); nothing in the plan writes state")

    # T8 — segment math sanity against the class curve.
    segs = charge_segments(sc, sc["assets"][0], 150)
    assert segs[0]["kw"] > segs[-1]["kw"] or len(segs) == 1
    print("T8 PASS charge_segments derives from the class energy_curve")

    # T9 — REJECTION: a site that cannot serve everyone plans for those it can.
    # Without it every asset MUST take a point, so an over-subscribed site returns
    # INFEASIBLE and the decide path is left with no schedule at all. That is the
    # wrong failure mode for a site under pressure, and the wrong one for a
    # contested one: "serve ten of twelve and name the two" beats "serve nobody".
    tight = _variant(charge_points=2, horizon_min=300)
    try:
        build_and_solve(materialize(json.loads(json.dumps(tight))))
        raise AssertionError("T9 FAIL: the tight scenario is no longer infeasible by "
                             "default — the test proves nothing; tighten it further")
    except RuntimeError as e:
        assert "INFEASIBLE" in str(e), f"T9 FAIL: unexpected default failure: {e}"

    rej = build_and_solve(materialize(json.loads(json.dumps(tight))), allow_rejection=True)
    served = [a for a in rej["assets"] if a["served"]]
    assert rej["rejected"], "T9 FAIL: rejection enabled but nothing was rejected"
    assert len(served) == len(rej["assets"]) - len(rej["rejected"])
    #: Every rejection is REPORTED, as an abstention in the shape the dispose path
    #: already reads. A drop that vanished from the output would be
    #: indistinguishable from an asset nobody asked about.
    abstained = sorted(p["entity_id"] for p in rej["proposals"] if p["proposal"]["abstain"])
    assert abstained == sorted(rej["rejected"]), (
        f"T9 FAIL: rejected {rej['rejected']} but abstained {abstained}")
    for a in rej["assets"]:
        if not a["served"]:
            #: ONE PRICE. A rejected asset must not also accrue tardiness for work
            #: nobody performed — double-charging biases the solver back toward
            #: infeasibility, which is the behaviour this feature exists to end.
            assert a["ops"] == [] and a["tardy_min"] is None, f"T9 FAIL: {a['aid']}"
    #: PINNED, because everything above this line turned out to be a weak guard.
    #: Mutation-tested: gating the wash/inspect exactly-one on `served` (so a
    #: rejected asset does not hold a bay) and zeroing its tardiness (so rejection
    #: has one price) BOTH pass every assertion above — the first silently changed
    #: which two assets were dropped, the second silently changed the objective,
    #: and neither was visible. The number is what sees them. Same rule as the
    #: committed plan artifact: a behaviour you cannot name is a behaviour you
    #: cannot notice changing.
    assert rej["rejected"] == ["AV-03", "AV-07"], (
        f"T9 FAIL: rejected {rej['rejected']}, expected ['AV-03', 'AV-07']")
    assert rej["objective"] == 206130, (
        f"T9 FAIL: objective {rej['objective']}, expected 206130 "
        f"(= 2 x {DEFAULT_REJECTION_PENALTY} + 6130 of served-side cost)")
    #: and the penalty dominates by design: rejection is a last resort, never a
    #: cheap way to duck a hard asset.
    assert rej["objective"] - 2 * DEFAULT_REJECTION_PENALTY < DEFAULT_REJECTION_PENALTY
    print(f"T9 PASS rejection: a site that returns INFEASIBLE by default serves "
          f"{len(served)}/{len(rej['assets'])} and names {rej['rejected']} as abstentions "
          f"(objective {rej['objective']}, pinned)")

    # T9b — REJECTION MUST NOT CONSTRAIN AN ASSET IT IS NOT SERVING.
    # The first implementation excused a rejected asset from tardiness with
    # `m.Add(tardy == 0).OnlyEnforceIf(served.Not())`. That reads as a price being
    # removed; it is a CONSTRAINT being imposed — combined with
    # `tardy >= finish - ready_by` it forces finish <= ready_by for an asset nobody
    # is serving, and its own parallel-op durations can make that impossible.
    # Measured here: the model went INFEASIBLE with rejection ENABLED, which is
    # precisely the failure the feature exists to prevent. The fix removes the term
    # from the OBJECTIVE instead.
    #
    # This scenario is the one that exposes it — ready almost on arrival, so a
    # rejected asset's ops alone push its finish past its deadline. The canonical
    # scenario is far too slack to show it, which is why the first version passed
    # every other assertion.
    urgent = _variant(charge_points=2, horizon_min=300)
    urgent["assets_spec"]["ready_delta_min"] = [5, 12]
    u = build_and_solve(materialize(json.loads(json.dumps(urgent))),
                        allow_rejection=True, objective_mode="min_tardy")
    assert u["rejected"], "T9b FAIL: nothing rejected — the scenario is not tight enough"
    #: min_tardy's objective IS sum(charged tardiness) + the rejection price, so
    #: this arithmetic says directly that no rejected asset was billed.
    billed = u["objective"] - len(u["rejected"]) * DEFAULT_REJECTION_PENALTY
    assert billed == sum(a["tardy_min"] for a in u["assets"] if a["served"]), (
        f"T9b FAIL: objective bills {billed} tardy-minutes but the served assets "
        f"account for {sum(a['tardy_min'] for a in u['assets'] if a['served'])}")
    print(f"T9b PASS a rejected asset is excused from the objective, not constrained: "
          f"{len(u['rejected'])} rejected, {billed} tardy-min billed, all of it on served assets")

    # T10 — CHURN: a re-solve does not move an asset across the site for nothing.
    # The previous-plan HINT only suggests the old point; without a price, a
    # rolling re-solve will relocate an asset for a one-minute objective gain — a
    # real vehicle making a real trip, and the first thing that makes operators
    # distrust a scheduler.
    BLOCKED = {"NASH-DCFC-03"}
    free_first, free_again, free_moved = _resolve_pair(0, BLOCKED)
    _, held_again, held_moved = _resolve_pair(500, BLOCKED)
    assert len(held_moved) < len(free_moved), (
        f"T10 FAIL: churn weight changed nothing — {len(free_moved)} moved unpriced, "
        f"{len(held_moved)} moved at weight 500")

    # A FORCED MOVE MUST BE FREE. NASH-DCFC-03 is out of service, so whoever was on
    # it has no choice; charging for that would price the site's own failure to the
    # asset and push the solver toward worse plans elsewhere to avoid a cost it
    # cannot escape. Asserted as arithmetic: at weight w the objective rises by
    # exactly w per DISCRETIONARY move, and the forced ones cost nothing.
    W = 50
    _, mid_again, _ = _resolve_pair(W, BLOCKED)
    #: FORCED is a STRUCTURAL property, not a behavioural one: an asset is forced
    #: iff the point it held is the one taken out of service, so no "stay" literal
    #: exists for it and no churn term is built. Defining it as "moved anyway at
    #: weight W" would be circular — an asset can move at weight W simply because
    #: moving is worth more than W, and it pays for that.
    first_points = _charge_points(free_first)
    forced = [aid for aid in free_moved if first_points[aid] in BLOCKED]
    discretionary = [aid for aid in free_moved if first_points[aid] not in BLOCKED]
    assert forced, "T10 FAIL: no asset was actually displaced by the blocked point"
    assert mid_again["objective"] - free_again["objective"] == W * len(discretionary), (
        f"T10 FAIL: objective rose {mid_again['objective'] - free_again['objective']} "
        f"at weight {W}; expected {W} x {len(discretionary)} discretionary moves")
    print(f"T10 PASS churn: unpriced re-solve moves {len(free_moved)} assets, priced moves "
          f"{len(held_moved)}; the {len(forced)} forced by the blocked point cost nothing")

    # T11 — A TARIFF WINDOW OUTSIDE THE HORIZON IS NOT AN INFEASIBLE SITE.
    # The on-peak overlap held max(charge_start, window_start) in a variable
    # bounded by the horizon, so a window starting AFTER the horizon ended was
    # unrepresentable and the whole model returned INFEASIBLE — blaming the site
    # for an input inconsistency. It is ordinary input for the production bridge:
    # plan the next two hours at 08:00 against a 16:00–19:00 on-peak window.
    #
    # Found while testing rejection, and worth separating from it: at first this
    # looked like "rejection enabled and still no plan", which is exactly the
    # failure rejection exists to prevent. It was not. ONE asset on ONE free point
    # was infeasible too — which is what proved it had nothing to do with capacity.
    #: H=200 is deliberate: past the [0, 180] arrival window (an asset arriving
    #: after the plan ends is a different, genuinely inconsistent input, and it
    #: fails as MODEL_INVALID rather than INFEASIBLE) but short of the on-peak
    #: window's 240. That gap is exactly where this bug lived.
    #: ONE asset against the full point set, so ANY failure here is the window and
    #: nothing else. A larger fleet at this horizon is genuinely capacity-bound,
    #: and a test that cannot tell a real limit from a modelling bug is the kind
    #: that sends you looking in the wrong place -- which is exactly what happened
    #: the first time, when this looked like rejection failing.
    late = _variant(charge_points=6, horizon_min=200, assets=1)
    w0, w1 = late["site"]["onpeak_window_min"]
    assert w0 > late["horizon_min"], (
        f"T11 assumption changed: window starts at {w0}, inside the horizon")
    lp = build_and_solve(materialize(json.loads(json.dumps(late))))
    assert lp["solver_status"] in ("OPTIMAL", "FEASIBLE")
    #: and a window wholly outside the horizon costs nothing, because no charge
    #: can run in it — every interval ends by H.
    assert lp["peak_excess_kw"] >= 0
    served_ops = sum(1 for a in lp["assets"] for o in a["ops"] if o["op"] == "charge")
    assert served_ops == len(lp["assets"]), "T11 FAIL: not every asset was scheduled"
    print(f"T11 PASS an on-peak window at [{w0}, {w1}] outside a {late['horizon_min']}-min "
          f"horizon solves ({lp['solver_status']}, {served_ops} charges) instead of "
          "reporting the site infeasible")

    # T12 — THE PIN IS SINGULAR, AND CI USES IT.
    # It used to live only in verify.yml while solvers/cpsat/README.md told developers to
    # `pip install ortools` unpinned. Given §6.2 — 9.11 and 9.15 give identical objectives and
    # different plans — a developer on another build running REGEN_PLAN=1 would rewrite the
    # committed artifact with a foreign plan. The drift gate would catch it in CI, after the fact;
    # the guard below refuses to write it at all. This test stops the pin becoming two numbers.
    pinned = pinned_ortools_version()
    workflow = (Path(__file__).parents[2] / ".github" / "workflows" / "verify.yml").read_text()
    assert "pip install -r requirements.txt" in workflow, (
        "T12 FAIL: CI no longer installs from requirements.txt, so the pin has forked")
    assert "ortools==" not in workflow, (
        "T12 FAIL: verify.yml carries its own ortools pin again — that is the second copy this "
        "test exists to prevent")
    print(f"T12 PASS the OR-Tools pin lives in requirements.txt alone ({pinned}); CI installs from it")

    print("ALL TESTS PASS")
    return p1


if __name__ == "__main__":
    plan = main()
    out = Path(__file__).parent / "plan_seed424242.json"
    #: repro.deterministic_time is a MEASUREMENT and the one field that could
    #: legitimately move between ortools builds; it stays out of the artifact
    #: so this file gates the SCHEDULE. The posture (which budget bound,
    #: whether the plan is reproducible at all) does belong in it.
    artifact = {k: v for k, v in plan.items() if k != "repro"}
    artifact["repro"] = {k: v for k, v in plan["repro"].items()
                         if k != "deterministic_time"}
    text = json.dumps(artifact, indent=1, sort_keys=True)
    #: THE COMMITTED ARTIFACT IS THE REPRODUCIBILITY CLAIM, so it is compared,
    #: not overwritten. Before this, the battery rewrote it on every run and
    #: nothing in CI ever read it -- a proof that regenerated itself out of any
    #: disagreement. Regenerate deliberately with REGEN_PLAN=1 and commit the
    #: diff, which is then reviewable.
    #: REGENERATING ON AN UNPINNED BUILD IS REFUSED, not merely detected later. REGEN_PLAN is the
    #: one path that deliberately overwrites the reproducibility artifact, so it is the one path
    #: where running the wrong OR-Tools silently commits a foreign schedule. CI would catch it on
    #: the next run; by then it is in the history and someone has to work out why.
    if os.environ.get("REGEN_PLAN") and ortools.__version__ != pinned_ortools_version():
        raise SystemExit(
            f"REFUSING TO REGENERATE {out.name} on ortools {ortools.__version__}.\n"
            f"  requirements.txt pins {pinned_ortools_version()}, and the version is part of the\n"
            "  plan's identity: releases break ties among equally-optimal schedules differently,\n"
            "  so this would commit a different schedule under the same seed (SOLVER_STATE.md 6.2).\n"
            "  Install the pin first:  pip install -r requirements.txt")
    if out.exists() and out.read_text() != text and not os.environ.get("REGEN_PLAN"):
        was = json.loads(out.read_text())
        #: Name the keys that moved. Reporting only the two plan_sha256 values
        #: is useless when the artifact itself was edited -- the stored hash
        #: then still matches while the file it describes does not.
        keys = sorted(set(was) | set(artifact))
        moved = [k for k in keys if was.get(k) != artifact.get(k)]
        was_ver = (was.get("repro") or {}).get("ortools_version")
        #: The likeliest cause by far, so lead with it. Two ortools releases
        #: break ties among equally-optimal schedules differently: measured on
        #: 9.11 vs 9.15, every objective matched and every plan differed.
        why = ("\n  LIKELY CAUSE: ortools version. This artifact was generated "
               f"on {was_ver}; you are running {ortools.__version__}. Different "
               "releases break ties among equally-optimal schedules differently "
               "-- same objective, different schedule. CI pins the version; "
               "match it before regenerating."
               if was_ver and was_ver != ortools.__version__ else "")
        raise SystemExit(
            f"DRIFT: {out.name} does not match this run's plan.\n"
            f"  keys that differ: {', '.join(moved) or '(formatting only)'}\n"
            f"  committed plan_sha256: {was.get('plan_sha256')}\n"
            f"  this run:              {plan['plan_sha256']}" + why + "\n"
            "If the change is intended, re-run with REGEN_PLAN=1 and commit "
            "the diff so a reviewer sees exactly what moved.")
    out.write_text(text)
    print(f"{out.name} matches (sha256 {plan['plan_sha256']})")
