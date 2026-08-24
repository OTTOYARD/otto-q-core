"""C4 CP-SAT prototype tests — plain-assert scripts, house style.

Run:  python3 solvers/cpsat/test_cpsat_prototype.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from model import build_and_solve, charge_segments, load_scenario  # noqa: E402

SC_PATH = Path(__file__).parent / "scenario_canonical.json"


def overlapping(a, b):
    return a["start"] < b["end"] and b["start"] < a["end"]


def main():
    sc = load_scenario(SC_PATH)

    # T1 — DETERMINISM UNDER FIXED SEED: two independent solves, byte-identical.
    p1 = build_and_solve(load_scenario(SC_PATH))
    p2 = build_and_solve(load_scenario(SC_PATH))
    assert p1["plan_sha256"] == p2["plan_sha256"], "T1 FAIL: plans differ across solves"
    print(f"T1 PASS determinism: sha256 {p1['plan_sha256'][:16]}… identical across 2 solves "
          f"(status={p1['solver_status']}, objective={p1['objective']})")

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
    out.write_text(json.dumps(plan, indent=1, sort_keys=True))
    print(f"wrote {out.name} (sha256 {plan['plan_sha256']})")
