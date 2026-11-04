"""lab/safety/replay.py -- replay a recorded post trace through a synthesized supervisor (E3 v0).

monitor.py checks R1 and R2 directly on the trace's times. This script asks the other question the frontier plan's E3
names: would the SYNTHESIZED supervisor have allowed what the engine did? Each car's visit to the post is mapped to the
model's events and replayed through the controlled system's explicit state space (synthesis/<variant>.statespace.cif,
written by cifexplorer; ESCET is not needed to replay). The first recorded step the controlled system does not allow is
reported with the model state and the requirement(s) that forbid it there; the visit's replay stops at that step.

    python3 -I lab/safety/replay.py --all lab/safety/fixtures/8c0b2e04 [--variant post_cell|post_cell_pre0792|...]

THE MAPPING, recorded event -> model events. Steps the engine does not record are filled in, and each fill is an
assumption stated here (README.md lists them too):
  car_arrived       c_admit
  mate_started      c_mate_start                      (the session opens with the mate: twin.ottoq_sim_start_charge_session)
  mate_latched      u_at_inlet, u_latched             (the arm's approach is not recorded separately)
  clean_started     c_clean_start, and c_clean_enter at the first point the controlled system allows it (the renderer's
                    arm waits at doors_open until the charge arm is still; the engine has no such step)
  session_completed u_charge_complete
  charger_faulted   u_fault
  demate_started    c_unlatch
  demate_cleared    u_unlatched, u_extracted, u_cleared   (the demate's phases are not recorded as events)
  emergency_release c_emergency_release
  clean_done        u_clean_finished, u_clean_home    (the arm's return is not recorded: taken as immediate)
  clean_cancelled   c_clean_abort, u_clean_home       (likewise)
  car_left          c_release (after u_tick if the sweep had held the car), or nothing after an emergency release
  every tick        while the car is on the post with its demate tether expired and it does not leave at that tick,
                    the sweep kept it: c_hold; at the next tick u_tick
Rows at the run's stop instant are the reset (twin.sim_stopped_and_reset), not cell events, and are not replayed. Each
visit starts from the model's initial state (charger Available). A car that arrives while the post is still out of
service by monitor.py's derived repair is reported as skipped, not replayed (no such visit on run 8c0b2e04).
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # sibling modules; `python3 -I` does not put the script's directory on sys.path

import analyze_synthesis as az  # noqa: E402
import monitor as mon  # noqa: E402

MAP = {
    "car_arrived": ["c_admit"],
    "mate_started": ["c_mate_start"],
    "mate_latched": ["u_at_inlet", "u_latched"],
    "session_completed": ["u_charge_complete"],
    "charger_faulted": ["u_fault"],
    "demate_started": ["c_unlatch"],
    "demate_cleared": ["u_unlatched", "u_extracted", "u_cleared"],
    "emergency_release": ["c_emergency_release"],
    "clean_done": ["u_clean_finished", "u_clean_home"],
    "clean_cancelled": ["c_clean_abort", "u_clean_home"],
}


class Stop(Exception):
    pass


def load_space(variant: str):
    ss = az.load_statespace(az.SYN / f"{variant}.statespace.cif")
    nxt: dict = {}
    for a, ev, b in ss["trans"]:
        if (a, ev) in nxt and nxt[(a, ev)] != b:
            raise ValueError(f"{variant}: nondeterministic on {ev}")
        nxt[(a, ev)] = b
    plant = az.load_statespace(az.SYN / "post_cell_plant.statespace.cif")
    pnext = {(a, ev): b for a, ev, b in plant["trans"]}
    algs, reqs, _g = az.load_requirements(az.SYN / f"{variant}.sup.cif")
    return ss["init"], nxt, pnext, algs, reqs


def replay_visit(rows, ticks, until, space, post, car):
    init, nxt, pnext, algs, reqs = space
    state = init
    taken = []

    def step(ev, t, why):
        nonlocal state
        if (state, ev) in nxt:
            state = nxt[(state, ev)]
            taken.append(ev)
            return
        s = dict(state)
        forbidden = [name for name, rev, tree, _txt in reqs if rev == ev and not az.eval_pred(tree, s, algs)]
        raise Stop({
            "post": post, "vehicle_id": car, "sim": mon.iso(t), "wall_utc": ticks.wall_of(t), "recorded": why,
            "model_event": ev, "plant_allows": (state, ev) in pnext,
            "forbidden_by": forbidden or (["(derived by synthesis)"] if (state, ev) in pnext else ["(plant)"]),
            "state": s, "replayed": len(taken)})

    def try_enter(t):
        s = dict(state)
        if s["CleanArm"] == "DoorsOpen" and (state, "c_clean_enter") in nxt:
            step("c_clean_enter", t, "clean_started (the arm enters once allowed)")

    mine = [x for x in rows if x.vehicle == car and x.t < until]
    instants = sorted({x.t for x in mine} | {t for t in ticks.sim if mine and mine[0].t <= t < until})
    left = False
    for t in instants:
        if left:
            break
        if dict(state)["Tether"] == "Held" and t in set(ticks.sim):
            step("u_tick", t, "the next tick: the sweep looks again")
        for x in (r for r in mine if r.t == t):
            if x.event == "car_left":
                if dict(state)["Car"] != "Left":
                    step("c_release", t, "car_left")
                left = True
                continue
            for ev in MAP.get(x.event, []):
                step(ev, t, x.event)
            if x.event == "clean_started":
                step("c_clean_start", t, "clean_started")
            try_enter(t)
            if dict(state)["Car"] == "Left":
                left = True
        if not left and dict(state)["Tether"] == "Expired" and t in set(ticks.sim):
            step("c_hold", t, "the car stayed on the post past this tick's sweep")
    return {"post": post, "vehicle_id": car, "replayed": len(taken), "first_disallowed": None}


def replay_post(trace: Path, ticks_path: Path | None, variant: str) -> dict:
    rows, ticks = mon.read_trace(trace), mon.read_ticks(ticks_path)
    space = load_space(variant)
    until = next((x.t for x in rows if x.event == "run_stopped"), rows[-1].t + timedelta(seconds=1))
    rep = mon.check(rows, ticks, trace.stem)
    oos = [(f["fault_sim"], f.get("out_of_service_to")) for f in rep["faults"]]
    visits = []
    for car in dict.fromkeys(x.vehicle for x in rows if x.event == "car_arrived"):
        arrive = next(x.t for x in rows if x.vehicle == car and x.event == "car_arrived")
        prior = [o for o in oos if mon.ts(o[0]) < arrive and (o[1] == mon.OUT_OF_SERVICE_END_OPEN or mon.ts(o[1]) > arrive)]
        if prior:
            visits.append({"post": trace.stem, "vehicle_id": car, "skipped": "arrived at a post still out of service"})
            continue
        try:
            visits.append(replay_visit(rows, ticks, until, space, trace.stem, car))
        except Stop as s:
            visits.append({"post": trace.stem, "vehicle_id": car, "first_disallowed": s.args[0]})
    return {"post": trace.stem, "variant": variant, "visits": visits}


def render(rep: dict) -> str:
    L = [f"== {rep['post']} against {rep['variant']}"]
    for v in rep["visits"]:
        d = v.get("first_disallowed")
        if v.get("skipped"):
            L.append(f"   car {v['vehicle_id']}: skipped ({v['skipped']})")
        elif d is None:
            L.append(f"   car {v['vehicle_id']}: every recorded step allowed ({v['replayed']} model events)")
        else:
            s = d["state"]
            L.append(f"   car {v['vehicle_id']}: DISALLOWED {d['model_event']} at {d['sim']} (wall {d['wall_utc']}), "
                     f"recorded as {d['recorded']}; forbidden by {', '.join(d['forbidden_by'])}; state Charger="
                     f"{s['Charger']} ChargeArm={s['ChargeArm']} CleanArm={s['CleanArm']} Tether={s['Tether']} "
                     f"Car={s['Car']}")
    return "\n".join(L)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Replay post traces through a synthesized supervisor.")
    ap.add_argument("--all", type=Path, required=True, metavar="DIR")
    ap.add_argument("--variant", default="post_cell", choices=az.VARIANTS)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    ticks = a.all / "ticks.csv" if (a.all / "ticks.csv").exists() else None
    reps = [replay_post(p, ticks, a.variant) for p in sorted(a.all.glob("*.csv")) if p.name != "ticks.csv"]
    print(json.dumps(reps, indent=1) if a.json else "\n".join(render(r) for r in reps))
    return 1 if any(v.get("first_disallowed") for r in reps for v in r["visits"]) else 0


if __name__ == "__main__":
    sys.exit(main())
