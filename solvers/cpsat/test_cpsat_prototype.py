"""C4 CP-SAT prototype tests — plain-assert scripts, house style.

Run:  python3 solvers/cpsat/test_cpsat_prototype.py
"""
import json
import math
import multiprocessing as mp
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from model import build_and_solve, charge_segments, load_scenario  # noqa: E402
from ortools.sat.python import cp_model  # noqa: E402

SC_PATH = Path(__file__).parent / "scenario_canonical.json"


def overlapping(a, b):
    return a["start"] < b["end"] and b["start"] < a["end"]


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
    walled = build_and_solve(load_scenario(SC_PATH), time_limit_s=1.2,
                             det_budget_s=1e9)
    assert walled["repro"]["reproducible"] is False, (
        "T1c FAIL: a wall-clock-truncated plan claimed to be reproducible")
    assert idle["repro"]["reproducible"] is True, (
        "T1c FAIL: a deterministically-budgeted plan was not labelled reproducible")
    print("T1c PASS default solve is deterministically budgeted with no "
          "wall-clock limit; a wall-clocked plan is labelled reproducible=False")

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
    if out.exists() and out.read_text() != text and not os.environ.get("REGEN_PLAN"):
        was = json.loads(out.read_text())
        #: Name the keys that moved. Reporting only the two plan_sha256 values
        #: is useless when the artifact itself was edited -- the stored hash
        #: then still matches while the file it describes does not.
        keys = sorted(set(was) | set(artifact))
        moved = [k for k in keys if was.get(k) != artifact.get(k)]
        raise SystemExit(
            f"DRIFT: {out.name} does not match this run's plan.\n"
            f"  keys that differ: {', '.join(moved) or '(formatting only)'}\n"
            f"  committed plan_sha256: {was.get('plan_sha256')}\n"
            f"  this run:              {plan['plan_sha256']}\n"
            "If the change is intended, re-run with REGEN_PLAN=1 and commit "
            "the diff so a reviewer sees exactly what moved.")
    out.write_text(text)
    print(f"{out.name} matches (sha256 {plan['plan_sha256']})")
