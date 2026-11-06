#!/usr/bin/env python3
"""E5 v0: the perfect day for the depot's operations, as a bound, on a finished lab day.

For a day the lab ran to its end (lab/research/p2_capacity/capacity_day.py --keep), this asks: with the same cars arriving
at the same times, owing the same work, on the same equipment, what is the best the depot could have done? CP-SAT
(OR-Tools 9.15.6755, the CP-SAT service's pin) solves it with perfect hindsight. The answer is compared with what the
kernel actually did, depot-wide and owner by owner.

THE MODEL (one minute per unit, from the day's start):
  - each visit: its arrival, its jobs, its due time when it has one, its owner;
  - jobs that hold a place: its charge on a post (the realized session's length: the car charges to its full target, rule
    9, and a car does not drain while it waits, so its charge takes what it took), and its bay work (the realized
    bookings' lengths, by lane: the wash bays, where detail work shares them, and the service bays). Cabin, exterior
    and digital work runs while the car charges (0383, 0764), so it holds no place of its own here;
  - a car is in one place at a time (no overlap between its own jobs), in any order: a RELAXATION of the engine's own
    order (a fault first, a charge before a bay), so the bound can only be better than the true best day;
  - each lane is a pool of identical units (cumulative), its capacity the units installed (rule 13), less a unit for
    every minute a post was faulted;
  - a visit leaves when its last job ends, plus its readiness check (3 minutes, the gate atom).
Objectives, each solved on its own (every one a valid bound on its own measure, and none can be beaten by any schedule):
  door     total minutes in the depot (arrival to departure), the measure every turnaround number reads;
  on_time  the most cars with a due time that are ready by it;
  wait     total minutes past each owner's contract queue wait (arrival to plug-in, 30 minutes in every contract).
For each, CP-SAT returns its best schedule (a perfect day that is ACHIEVABLE under the relaxation) and a proven bound.

WHAT IT IS NOT. The arrivals are held as they happened, and in the depot a car that left sooner would have been sent out
and come back sooner: the bound is for this day's arrival stream. The relaxation drops the engine's own job order, the
techs' pool and the staging spaces. Times are the run's own, quantized to its ticks (5 sim-minutes in the capacity days).

Usage: /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_perfect_day/bound_ops.py --db ottoq_cap_normal_day_116_171717
         [--run <uuid>] [--seconds 60] [--out results.jsonl]
Nothing here touches production.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
from collections import defaultdict

import psycopg
from ortools.sat.python import cp_model

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
TWIN = "11111111-1111-1111-1111-111111111111"
HERE = os.path.dirname(os.path.abspath(__file__))
GATE_MIN = 3

VISITS_SQL = """
SELECT o.visit_id::text, o.vehicle_id::text, fo.name AS owner, o.archetype,
       extract(epoch FROM (o.arrived_at - r.sim_clock_start)) / 60.0 AS arr,
       extract(epoch FROM (o.due_at - r.sim_clock_start)) / 60.0 AS due,
       extract(epoch FROM (o.departed_at - r.sim_clock_start)) / 60.0 AS dep,
       o.in_depot_at_horizon, o.on_time,
       -- when the car was READY: its last done atom (the readiness check is the last by construction); a car that
       -- finished its work may wait for the work side to send it, which no scheduling of the depot can shorten
       extract(epoch FROM ((SELECT max(COALESCE((e ->> 'done_at')::timestamptz, (e ->> 'closed_at')::timestamptz,
                                                  (e ->> 'ends_at')::timestamptz))
                              FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) e
                             WHERE vn.visit_id = o.visit_id AND e ->> 'status' = 'done') - r.sim_clock_start)) / 60.0 AS ready,
       COALESCE((SELECT s.max_queue_wait_minutes FROM ottoq_fleet_operator_slas s
                  WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status = 'active'
                  ORDER BY s.version DESC LIMIT 1), 30) AS contract_wait
  FROM public.ottoq_visit_outcomes(%(run)s) o
  JOIN ottoq_sim_runs r ON r.sim_run_id = %(run)s
  JOIN vehicles v ON v.id = o.vehicle_id
  JOIN fleet_operators fo ON fo.id = v.fleet_operator_id
"""

# what each visit OWED that holds a place (its atoms: the charge on a post, bay work by lane), and how long each took
# where it was done (the visit's own sessions and bookings); a job never started takes its atom's estimate
ATOMS_SQL = """
WITH o AS (SELECT * FROM public.ottoq_visit_outcomes(%(run)s))
SELECT o.visit_id::text, a.e ->> 'svc' AS svc, a.e ->> 'concurrency' AS conc, a.e ->> 'requires_bay' AS bay,
       COALESCE((a.e ->> 'est_min')::numeric, p.est_min_default) AS est_min, p.lane,
       COALESCE((a.e ->> 'must_do')::boolean, true) AS must_do
  FROM o JOIN ottoq_visit_needs vn ON vn.visit_id = o.visit_id
  CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms ELSE '[]' END) a(e)
  LEFT JOIN service_cadence_policy p ON p.svc = a.e ->> 'svc'
"""

SESSIONS_SQL = """
WITH o AS (SELECT * FROM public.ottoq_visit_outcomes(%(run)s)),
     r AS (SELECT sim_clock_start AS t0, sim_clock_current AS t1 FROM ottoq_sim_runs WHERE sim_run_id = %(run)s)
SELECT o.visit_id::text, extract(epoch FROM (s.started_at - r.t0)) / 60.0 AS start,
       extract(epoch FROM (COALESCE(s.ended_at, r.t1) - s.started_at)) / 60.0 AS dur, s.ended_at IS NULL AS censored
  FROM o, r, ocpp_sessions s
 WHERE s.sim_run_id = %(run)s AND s.vehicle_id = o.vehicle_id AND s.started_at >= o.arrived_at
   AND (o.departed_at IS NULL OR s.started_at < o.departed_at) AND s.status::text <> 'faulted'
"""

# --post-occupancy: a charge holds its post from the car's arrival on the post to its leaving it, not only for the session
# (the robot unplugs it after the session ends: on the lab days a car leaves its post a tick after its session ended).
# Read from the stall's own pointer (stall.state_changed, current_vehicle_id), the session's bounds where none is found.
SESSIONS_OCC_SQL = """
WITH o AS (SELECT * FROM public.ottoq_visit_outcomes(%(run)s)),
     r AS (SELECT sim_clock_start AS t0, sim_clock_current AS t1 FROM ottoq_sim_runs WHERE sim_run_id = %(run)s),
     s AS (SELECT o.visit_id, s.vehicle_id, s.stall_id, s.started_at, s.ended_at
             FROM o, ocpp_sessions s
            WHERE s.sim_run_id = %(run)s AND s.vehicle_id = o.vehicle_id AND s.started_at >= o.arrived_at
              AND (o.departed_at IS NULL OR s.started_at < o.departed_at) AND s.status::text <> 'faulted'),
     occ AS (SELECT s.*,
                    COALESCE((SELECT max(e.sim_clock_at) FROM ottoq_events e
                               WHERE e.entity_id = s.stall_id AND e.event_type = 'stall.state_changed'
                                 AND e.payload -> 'diff' -> 'current_vehicle_id' ->> 'to' = s.vehicle_id::text
                                 AND e.sim_clock_at <= s.started_at), s.started_at) AS occ_from,
                    COALESCE((SELECT min(e.sim_clock_at) FROM ottoq_events e
                               WHERE e.entity_id = s.stall_id AND e.event_type = 'stall.state_changed'
                                 AND e.payload -> 'diff' -> 'current_vehicle_id' ->> 'from' = s.vehicle_id::text
                                 AND e.sim_clock_at >= s.ended_at), s.ended_at) AS occ_to
               FROM s)
SELECT occ.visit_id::text, extract(epoch FROM (occ.occ_from - r.t0)) / 60.0 AS start,
       extract(epoch FROM (COALESCE(occ.occ_to, r.t1) - occ.occ_from)) / 60.0 AS dur, occ.occ_to IS NULL AS censored
  FROM occ, r
"""

BOOKINGS_SQL = """
WITH o AS (SELECT * FROM public.ottoq_visit_outcomes(%(run)s)),
     r AS (SELECT sim_clock_start AS t0, sim_clock_current AS t1 FROM ottoq_sim_runs WHERE sim_run_id = %(run)s)
SELECT o.visit_id::text, st.stall_type::text AS lane, b.need_atom,
       extract(epoch FROM (lower(b.during) - r.t0)) / 60.0 AS start,
       extract(epoch FROM (LEAST(upper(b.during), COALESCE(b.released_at, upper(b.during)), r.t1) - lower(b.during))) / 60.0 AS dur,
       upper(b.during) > r.t1 AS censored
  FROM o, r, ottoq_stall_bookings b JOIN stalls st ON st.id = b.stall_id
 WHERE b.sim_run_id = %(run)s AND b.vehicle_id = o.vehicle_id AND st.stall_type::text IN ('wash_bay', 'service_bay')
   AND b.state IN ('active', 'done', 'interrupted') AND lower(b.during) >= o.arrived_at
   AND (o.departed_at IS NULL OR lower(b.during) < o.departed_at)
"""

BAY_LANE = {"detail": "wash_bay", "wash": "wash_bay", "wash_bay": "wash_bay", "service": "service_bay",
            "service_bay": "service_bay"}


NUM_WORKERS = 4   # CP-SAT workers; --workers sets it

def jobs_of(atoms: list, sessions: list, bookings: list) -> list:
    """One visit's place-holding jobs: realized where done (sessions, bookings), else the atom's estimate."""
    out = []
    owes_charge = any(a["lane"] == "anchor" or a["conc"] == "anchor" for a in atoms if a["must_do"])
    if sessions:
        for x in sessions:
            out.append({"lane": "post", "start": x["start"], "dur": x["dur"], "censored": x["censored"], "real": True})
    elif owes_charge:
        est = max((a["est_min"] or 0) for a in atoms if a["lane"] == "anchor" or a["conc"] == "anchor")
        out.append({"lane": "post", "start": None, "dur": float(est or 25), "censored": True, "real": False})
    used = set()
    for a in atoms:
        if not a["must_do"]:
            continue
        lane = BAY_LANE.get(a["bay"] or "") or BAY_LANE.get(a["lane"] or "")
        if lane is None:
            continue
        hit = next((i for i, b in enumerate(bookings) if i not in used and b["lane"] == lane
                    and (b["need_atom"] in (None, a["svc"]))), None)
        if hit is not None:
            used.add(hit)
            b = bookings[hit]
            out.append({"lane": lane, "start": b["start"], "dur": b["dur"], "censored": b["censored"], "real": True})
        else:
            out.append({"lane": lane, "start": None, "dur": float(a["est_min"] or 10), "censored": True, "real": False})
    return out


UNITS_SQL = """
SELECT CASE WHEN stall_type::text IN ('dcfc', 'l2') THEN 'post' ELSE stall_type::text END AS lane, count(*)
  FROM stalls WHERE depot_id = %(depot)s AND stall_type::text IN ('dcfc', 'l2', 'wash_bay', 'service_bay') GROUP BY 1
"""

# minutes each post was down: a faulted session's charger, from the fault until its repair (0621's reading)
FAULTS_SQL = """
WITH r AS (SELECT sim_clock_start AS t0, sim_clock_current AS t1 FROM ottoq_sim_runs WHERE sim_run_id = %(run)s)
SELECT extract(epoch FROM (COALESCE(ev.at, s.ended_at) - r.t0)) / 60.0 AS down_from,
       COALESCE(ev.rep, 0) AS repair_min
  FROM r, ocpp_sessions s
  LEFT JOIN LATERAL (SELECT e.sim_clock_at AS at, (e.payload ->> 'repair_minutes')::numeric AS rep
                       FROM ottoq_events e
                      WHERE e.entity_type = 'ocpp_session' AND e.entity_id = s.id AND e.event_type = 'charge.session_faulted'
                      ORDER BY e.occurred_at DESC LIMIT 1) ev ON true
 WHERE s.sim_run_id = %(run)s AND s.status::text = 'faulted' AND s.ended_at IS NOT NULL
"""


def load(db: str, run: str | None, occupancy: bool = False) -> dict:
    conn = psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=db)
    if run is None:
        run = conn.execute("SELECT sim_run_id::text FROM ottoq_sim_runs WHERE run_by = 'ab_harness' "
                           "ORDER BY started_at DESC LIMIT 1").fetchone()[0]
    meta = conn.execute("SELECT scenario_code, random_seed, tick_count, sim_clock_start, sim_clock_current, "
                        "payload -> 'lab_capacity' FROM ottoq_sim_runs WHERE sim_run_id = %s", (run,)).fetchone()
    cur = conn.cursor()
    cur.execute(VISITS_SQL, {"run": run})
    cols = [d.name for d in cur.description]
    visits = [dict(zip(cols, r)) for r in cur.fetchall()]
    atoms, sess, bk = defaultdict(list), defaultdict(list), defaultdict(list)
    cur.execute(ATOMS_SQL, {"run": run})
    for vid, svc, conc, bay, est, lane, must in cur.fetchall():
        atoms[vid].append({"svc": svc, "conc": conc, "bay": bay, "est_min": float(est) if est is not None else None,
                           "lane": lane, "must_do": must})
    cur.execute(SESSIONS_OCC_SQL if occupancy else SESSIONS_SQL, {"run": run})
    for vid, start, dur, cen in cur.fetchall():
        sess[vid].append({"start": float(start), "dur": float(dur), "censored": cen})
    cur.execute(BOOKINGS_SQL, {"run": run})
    for vid, lane, need, start, dur, cen in cur.fetchall():
        bk[vid].append({"lane": lane, "need_atom": need, "start": float(start), "dur": float(dur), "censored": cen})
    jobs = {v["visit_id"]: jobs_of(atoms.get(v["visit_id"], []), sess.get(v["visit_id"], []), bk.get(v["visit_id"], []))
            for v in visits}
    units = dict(conn.execute(UNITS_SQL, {"depot": TWIN}).fetchall())
    faults = [(float(a), float(b)) for a, b in conn.execute(FAULTS_SQL, {"run": run}).fetchall()]
    conn.close()
    horizon = (meta[4] - meta[3]).total_seconds() / 60.0
    return {"db": db, "run": run, "scenario": meta[0], "seed": meta[1], "ticks": meta[2], "horizon": horizon,
            "lab": meta[5], "visits": visits, "jobs": jobs, "units": units, "faults": faults}


def realized(day: dict) -> dict:
    """The kernel's day on the model's measures. A visit still in the depot at the horizon counts to the horizon."""
    H = day["horizon"]
    out = defaultdict(lambda: defaultdict(float))
    for v in day["visits"]:
        arr = float(v["arr"])
        dep = float(v["dep"]) if v["dep"] is not None else H
        # ready: the last done atom of a car that left (never after it left); a car still in at the horizon, the horizon
        ready = min(float(v["ready"]) if v["ready"] is not None else dep, dep) if v["dep"] is not None else H
        posts = [j for j in day["jobs"].get(v["visit_id"], []) if j["lane"] == "post"]
        first_plug = min((j["start"] for j in posts if j["start"] is not None), default=None)
        # a car that owed a charge and never plugged in waited to the horizon: its wait is counted to there
        plug = first_plug if first_plug is not None else (H if posts else None)
        for k in ("all", v["owner"]):
            out[k]["visits"] += 1
            out[k]["door_min"] += max(min(dep, H) - arr, 0)
            out[k]["door_ready_min"] += max(min(ready, H) - arr, 0)
            if v["due"] is not None:
                out[k]["ready_by_due"] += 1 if (v["dep"] is not None and ready <= float(v["due"])) else 0
            out[k]["past_contract_min"] += max(min(plug, H) - arr - float(v["contract_wait"]), 0) if plug is not None else 0
            if v["due"] is not None:
                out[k]["with_due"] += 1
                out[k]["on_time"] += 1 if (v["dep"] is not None and float(v["dep"]) <= float(v["due"])) else 0
            out[k]["in_depot_at_horizon"] += 1 if v["in_depot_at_horizon"] else 0
    return {k: dict(x) for k, x in out.items()}


def solve(day: dict, objective: str, seconds: float, owner: str | None = None, fix: str | None = None,
          caps: dict | None = None, engine_order: bool = False) -> dict:
    """One clairvoyant solve. fix = 'post' or 'bay' holds that lane's jobs at their realized start (the regret split)."""
    Hd = int(math.ceil(day["horizon"]))      # the day's own end: both sides count minutes only up to it
    H = Hd + 24 * 60                          # the schedule may run past it, as the real day's cars did
    m = cp_model.CpModel()
    lanes = defaultdict(list)            # lane -> [(interval, demand)]
    visit_vars = []
    for v in day["visits"]:
        jobs = day["jobs"].get(v["visit_id"], [])
        arr = int(math.floor(float(v["arr"])))
        ivs, ends, plug_starts = [], [], []
        for j in jobs:
            d = max(int(round(j["dur"])), 1)
            if fix and j["start"] is not None and ((fix == "post" and j["lane"] == "post")
                                                   or (fix == "bay" and j["lane"] != "post")):
                s = m.NewConstant(max(int(round(j["start"])), arr))
            else:
                s = m.NewIntVar(arr, H - d, "s")
            e = m.NewIntVar(arr + d, H, "e")
            iv = m.NewIntervalVar(s, d, e, "iv")
            ivs.append(iv)
            ends.append(e)
            lanes[j["lane"]].append(iv)
            if j["lane"] == "post":
                plug_starts.append(s)
        if len(ivs) > 1:
            m.AddNoOverlap(ivs)
        if engine_order and len(ivs) > 1:
            # the engine's own order of a car's work: a car with an open fault is repaired before it charges (0557);
            # any other car charges before its bays (0780: a car that owes a charge is not ready for a bay)
            posts = [(iv, e) for (iv, e, j) in zip(ivs, ends, jobs) if j["lane"] == "post"]
            bays = [(iv, e, j) for (iv, e, j) in zip(ivs, ends, jobs) if j["lane"] != "post"]
            fault = v.get("archetype") == "E_tech_hold_fault"
            for piv, pe in posts:
                for biv, be, bj in bays:
                    if fault and bj["lane"] == "service_bay":
                        m.Add(be <= piv.StartExpr())
                    else:
                        m.Add(pe <= biv.StartExpr())
        dep = m.NewIntVar(arr, H, "dep")
        if ends:
            m.AddMaxEquality(dep, [e for e in ends])
        else:
            m.Add(dep == arr)
        out_at = m.NewIntVar(arr, H, "out")
        m.AddMinEquality(out_at, [dep + (GATE_MIN if ends else 0), m.NewConstant(max(Hd, arr))])
        door = m.NewIntVar(0, H, "door")
        m.Add(door == out_at - arr)
        late = m.NewIntVar(0, H, "late")
        on_time = None
        if v["due"] is not None:
            due = int(math.floor(float(v["due"])))
            m.Add(late >= dep + (GATE_MIN if ends else 0) - due)
            on_time = m.NewBoolVar("ot")
            m.Add(dep + (GATE_MIN if ends else 0) <= due).OnlyEnforceIf(on_time)
        else:
            m.Add(late == 0)
        past = m.NewIntVar(0, H, "past")
        if plug_starts:
            first = m.NewIntVar(arr, H, "first")
            m.AddMinEquality(first, plug_starts)
            first_c = m.NewIntVar(arr, H, "first_c")
            m.AddMinEquality(first_c, [first, m.NewConstant(max(Hd, arr))])
            m.Add(past >= first_c - arr - int(v["contract_wait"]))
        else:
            m.Add(past == 0)
        visit_vars.append((v, door, on_time, past, out_at))
    for lane, ivs in lanes.items():
        cap = int(day["units"].get(lane, 0))
        if cap <= 0:
            continue
        demands = [1] * len(ivs)
        if lane == "post":
            for a, rep in day["faults"]:
                d = max(int(round(rep)), 0)
                if d > 0 and a < H:
                    ivs = ivs + [m.NewIntervalVar(int(a), d, int(a) + d, "down")]
                    demands = demands + [1]
        m.AddCumulative(ivs, demands, cap)
    sel = [x for x in visit_vars if owner is None or x[0]["owner"] == owner]
    if caps:   # rule 14's form of the perfect day: no owner's cars spend more minutes to ready than the kernel's day gave them
        for o, cap in caps.items():
            m.Add(sum(x[1] for x in visit_vars if x[0]["owner"] == o) <= int(math.floor(cap)))
    if objective == "door":
        m.Minimize(sum(x[1] for x in sel))
    elif objective == "on_time":
        m.Maximize(sum(x[2] for x in sel if x[2] is not None))
    elif objective == "wait":
        m.Minimize(sum(x[3] for x in sel))
    else:
        raise ValueError(objective)
    s = cp_model.CpSolver()
    s.parameters.max_time_in_seconds = seconds
    s.parameters.num_workers = NUM_WORKERS
    s.parameters.random_seed = 0
    t0 = time.time()
    st = s.Solve(m)
    res = {"objective": objective, "owner": owner, "fix": fix, "status": s.StatusName(st),
           "seconds": round(time.time() - t0, 1)}
    if st in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        res["best"] = s.ObjectiveValue()
        res["bound"] = s.BestObjectiveBound()
        per = defaultdict(lambda: defaultdict(float))
        for v, door, ot, past, out_at in visit_vars:
            for k in ("all", v["owner"]):
                per[k]["door_min"] += s.Value(door)
                per[k]["past_contract_min"] += s.Value(past)
                if v["due"] is not None:
                    per[k]["ready_by_due"] += 1 if s.Value(out_at) <= math.floor(float(v["due"])) else 0
                if ot is not None:
                    per[k]["on_time"] += s.Value(ot)
        res["schedule"] = {k: dict(x) for k, x in per.items()}
    return res


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--run")
    ap.add_argument("--seconds", type=float, default=60)
    ap.add_argument("--workers", type=int, default=4,
                    help="CP-SAT workers (fewer beside running lab days; the bound stays a bound, only weaker in the time)")
    ap.add_argument("--split", action="store_true", help="also solve with each lane held at the kernel's starts")
    ap.add_argument("--owners", action="store_true", help="also each owner's own best (door), the others free")
    ap.add_argument("--engine-order", action="store_true",
                    help="hold each car's work in the engine's own order (repair first on a fault, else charge before bays)")
    ap.add_argument("--post-occupancy", action="store_true",
                    help="a charge holds its post from the car's arrival on it to its leaving it (SESSIONS_OCC_SQL), not the session only")
    ap.add_argument("--objectives", default="door,on_time,wait", help="comma-separated: door, on_time, wait")
    ap.add_argument("--out", default=os.path.join(HERE, "bound_ops.jsonl"))
    a = ap.parse_args()
    global NUM_WORKERS
    NUM_WORKERS = a.workers
    day = load(a.db, a.run, occupancy=a.post_occupancy)
    real = realized(day)
    out = {"db": day["db"], "run": day["run"], "scenario": day["scenario"], "seed": day["seed"], "lab": day["lab"],
           "engine_order": a.engine_order, "post_occupancy": a.post_occupancy,
           "horizon_min": day["horizon"], "units": day["units"], "faults": len(day["faults"]),
           "visits": len(day["visits"]), "jobs": sum(len(j) for j in day["jobs"].values()),
           "realized": real, "solves": []}
    for obj in [x.strip() for x in a.objectives.split(",") if x.strip()]:
        out["solves"].append(solve(day, obj, a.seconds, engine_order=a.engine_order))
    if a.split:
        for fix in ("bay", "post"):
            out["solves"].append(solve(day, "door", a.seconds, fix=fix, engine_order=a.engine_order))
    if a.owners:
        for owner in sorted({v["owner"] for v in day["visits"]}):
            out["solves"].append(solve(day, "door", a.seconds, owner=owner, engine_order=a.engine_order))
        # the fair perfect day: the least total, no owner above what the kernel's day gave it (minutes to ready)
        caps = {o: x["door_ready_min"] for o, x in real.items() if o != "all"}
        fair = solve(day, "door", a.seconds, caps=caps, engine_order=a.engine_order)
        fair["objective"] = "door_no_owner_worse"
        out["solves"].append(fair)
    with open(a.out, "a") as f:
        f.write(json.dumps(out, default=str) + "\n")
    r = real.get("all", {})
    for sv in out["solves"]:
        tag = sv["objective"] + (f"[{sv['owner']}]" if sv["owner"] else "") + (f"[fix {sv['fix']}]" if sv["fix"] else "")
        print(f"{tag:28s} {sv['status']:9s} best {sv.get('best')}  bound {sv.get('bound')}  ({sv['seconds']} s)")
    print(f"realized: door {r.get('door_min'):.0f} min (to ready {r.get('door_ready_min'):.0f}) over "
          f"{r.get('visits'):.0f} visits; on time {r.get('on_time', 0):.0f}/{r.get('with_due', 0):.0f} "
          f"(ready by due {r.get('ready_by_due', 0):.0f}); past contract {r.get('past_contract_min', 0):.0f} min")


if __name__ == "__main__":
    main()
