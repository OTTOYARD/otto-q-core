"""lab/safety/monitor.py -- the E3 v0 runtime monitor for one robotic DC fast-charging post.

Reads one post's event trace (CSV, as extract_trace.sql writes it) and, optionally, the run's tick clock, and reports
every interval in which the recorded behaviour violates

  R1  no mate starts on an out-of-service charger, and
  R2  a car on an out-of-service post is released when its demate ends: the cleaning arm does not hold it (G506).

It also lists ADVISORIES: what the synthesized supervisor forbids (R3d: no car leaves the post with an arm at it) but
the engine's record cannot decide, because the engine records no arm-home signal (db/checks/0474 section 5(c)).

A monitor is a finding for a person, never a lever (CLAUDE.md rule 10): it reads a trace and changes nothing.

Usage:
  python3 -I lab/safety/monitor.py TRACE.csv [--ticks TICKS.csv] [--json]
  python3 -I lab/safety/monitor.py --all lab/safety/fixtures/8c0b2e04 [--json]
Exit status: 0 no violation, 1 at least one R1/R2 violation, 2 bad input.

THE RULES, and where each comes from (none is fitted to the two answers):

  Out of service. A charger is out of service from its `charger_faulted` row (the faulted session's end) until it is
  repaired. The trace has no repair event (the twin sends nothing when a repair ends, db/checks/0474 5(a)), so the
  repair is derived as twin.ottoq_sim_recover_chargers does it: the first tick at or after fault + repair_minutes
  (without a tick clock: fault + repair_minutes exactly). A repair after the end of the observation leaves it open.

  R1. A `mate_started` or `session_started` on the post at an instant t inside [fault, repair) is a violation.

  R2. For each fault, the faulted car's release is DUE at:
      - the demate path (`demate_started` for that car at the fault): its `demate_cleared`, the arm reporting clear.
        On run 8c0b2e04 all 38 demates cleared at the first tick at or after demate_started + window_s, and all 31
        demates with no cleaning hold left the post at exactly that instant (lab/safety/README.md, "Calibration").
        With no `demate_cleared` in the trace, the first tick at or after demate_started + window_s; with no tick
        clock either, the post is reported undecidable rather than guessed.
      - the emergency path (`emergency_release` at the fault): the fault itself.
      - neither recorded: the fault itself (and the path is reported as none_recorded).
      The car violates R2 if it is still on the post after its release was due while the charger is still out of
      service: the violation interval is [due, min(left, repair)]. Times are compared exactly: every engine event is
      stamped at a tick instant, so a release made by the sweep that was due lands on the due instant itself.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from bisect import bisect_left
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

COLUMNS = ["seq", "sim_time", "event", "vehicle_id", "detail", "source"]
OUT_OF_SERVICE_END_OPEN = "open (not repaired before the trace ends)"


def ts(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def iso(t: datetime | None) -> str | None:
    return None if t is None else t.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def details(text: str) -> dict:
    out = {}
    for part in filter(None, (text or "").split(";")):
        k, _, v = part.partition("=")
        out[k] = v
    return out


@dataclass
class Row:
    seq: int
    t: datetime
    event: str
    vehicle: str
    detail: dict
    source: str


@dataclass
class Ticks:
    sim: list = field(default_factory=list)
    wall: dict = field(default_factory=dict)

    def first_at_or_after(self, t: datetime) -> datetime | None:
        i = bisect_left(self.sim, t)
        return self.sim[i] if i < len(self.sim) else None

    def wall_of(self, t: datetime | None) -> str | None:
        return None if t is None else self.wall.get(t)


@dataclass
class Finding:
    requirement: str
    post: str
    vehicle_id: str
    start_sim: str
    end_sim: str
    seconds: float
    start_wall_utc: str | None
    end_wall_utc: str | None
    facts: dict


def read_trace(path: Path) -> list[Row]:
    with path.open(newline="", encoding="utf-8") as f:
        r = csv.DictReader(f)
        if r.fieldnames != COLUMNS:
            raise ValueError(f"{path}: columns {r.fieldnames}, expected {COLUMNS}")
        rows = [Row(int(x["seq"]), ts(x["sim_time"]), x["event"], x["vehicle_id"], details(x["detail"]), x["source"])
                for x in r]
    if [x.seq for x in rows] != list(range(1, len(rows) + 1)):
        raise ValueError(f"{path}: seq is not 1..n")
    if any(b.t < a.t for a, b in zip(rows, rows[1:])):
        raise ValueError(f"{path}: rows are not in time order")
    for x in rows:
        if x.vehicle and len(x.vehicle) != 36:
            raise ValueError(f"{path}: row {x.seq} vehicle id {x.vehicle!r} is not a full UUID")
    return rows


def read_ticks(path: Path | None) -> Ticks:
    t = Ticks()
    if path is None:
        return t
    with path.open(newline="", encoding="utf-8") as f:
        for x in csv.DictReader(f):
            s = ts(x["sim_time"])
            t.sim.append(s)
            if x.get("wall_utc"):
                t.wall[s] = x["wall_utc"]
    t.sim.sort()
    return t


def cleans_of(rows: list[Row], vehicle: str) -> list[dict]:
    """The post's cleaning-arm cycles on this car: start, end, outcome (from clean_* rows)."""
    out, open_ = [], None
    for x in rows:
        if x.vehicle != vehicle:
            continue
        if x.event == "clean_started":
            open_ = {"start": x.t, "end": None, "outcome": "in_progress_at_trace_end"}
            out.append(open_)
        elif x.event in ("clean_done", "clean_cancelled") and open_ is not None:
            open_["end"] = x.t
            open_["outcome"] = "done" if x.event == "clean_done" else "cancelled:" + x.detail.get("reason", "")
            open_ = None
    return out


def in_progress(clean: dict, t: datetime) -> bool:
    return clean["start"] <= t and (clean["end"] is None or clean["end"] > t)


def check(rows: list[Row], ticks: Ticks, post: str) -> dict:
    end = next((x.t for x in rows if x.event == "run_stopped"), rows[-1].t if rows else None)
    violations: list[Finding] = []
    advisories: list[Finding] = []
    faults, undecidable = [], []

    for f in (x for x in rows if x.event == "charger_faulted"):
        drawn = f.t + timedelta(minutes=float(f.detail["repair_minutes"]))
        repaired = (ticks.first_at_or_after(drawn) if ticks.sim else drawn)
        open_ = repaired is None or (end is not None and repaired > end)
        faults.append({"fault": f, "repaired": None if open_ else repaired, "drawn_repair_end": drawn})

    # ── R1: no mate starts on an out-of-service charger ─────────────────────────────────────────────────────────────
    for x in (r for r in rows if r.event in ("mate_started", "session_started")):
        for fo in faults:
            lo, hi = fo["fault"].t, fo["repaired"]
            if lo <= x.t and (hi is None or x.t < hi):
                violations.append(Finding(
                    "R1", post, x.vehicle, iso(x.t), iso(x.t), 0.0, ticks.wall_of(x.t), ticks.wall_of(x.t),
                    {"event": x.event, "out_of_service_from": iso(lo),
                     "out_of_service_to": iso(hi) if hi else OUT_OF_SERVICE_END_OPEN, "source": x.source}))

    # ── R2: the faulted car is released when its demate ends ────────────────────────────────────────────────────────
    for fo in faults:
        f, repaired = fo["fault"], fo["repaired"]
        v = f.vehicle
        same = [x for x in rows if x.vehicle == v and x.t == f.t]
        dem = next((x for x in same if x.event == "demate_started"), None)
        emr = next((x for x in same if x.event == "emergency_release"), None)
        if dem is not None:
            path = "demate"
            cleared = next((x for x in rows if x.vehicle == v and x.event == "demate_cleared" and x.t >= f.t), None)
            if cleared is not None:
                due, due_from = cleared.t, "demate_cleared"
            else:
                window_end = dem.t + timedelta(seconds=float(dem.detail.get("window_s", "0")))
                due = ticks.first_at_or_after(window_end) if ticks.sim else None
                due_from = "first tick at or after the demate window"
                if due is None:
                    undecidable.append({"vehicle_id": v, "fault": iso(f.t),
                                        "why": "no demate_cleared and no tick clock to place the window's end"})
                    continue
        elif emr is not None:
            path, due, due_from = "emergency_release", f.t, "the fault (the stop path's re-queue branch)"
        else:
            path, due, due_from = "none_recorded", f.t, "the fault (no demate or release recorded)"
        left_row = next((x for x in rows if x.vehicle == v and x.event == "car_left" and x.t >= f.t), None)
        left = left_row.t if left_row else end
        cl = [c for c in cleans_of(rows, v) if in_progress(c, f.t)]
        clean = cl[0] if cl else None
        facts = {
            "fault_sim": iso(f.t), "fault_wall_utc": ticks.wall_of(f.t), "reason": f.detail.get("reason"),
            "repair_minutes": float(f.detail["repair_minutes"]),
            "out_of_service_to": iso(repaired) if repaired else OUT_OF_SERVICE_END_OPEN,
            "release_path": path, "release_due_sim": iso(due), "release_due_from": due_from,
            "left_sim": iso(left), "left_wall_utc": ticks.wall_of(left), "left_source": left_row.source if left_row else None,
            "still_on_post_at_trace_end": left_row is None,
            "held_from_fault_s": round((left - f.t).total_seconds(), 1),
            "clean_in_progress_at_fault": clean is not None,
            "clean_start_sim": iso(clean["start"]) if clean else None,
            "clean_end_sim": iso(clean["end"]) if clean and clean["end"] else None,
            "clean_outcome": clean["outcome"] if clean else None,
        }
        if clean is not None and clean["end"] is not None and ticks.sim:
            facts["left_at_first_tick_after_clean_end"] = ticks.first_at_or_after(clean["end"]) == left
        fo["r2"] = facts
        stop = left if repaired is None else min(left, repaired)
        if stop > due:
            violations.append(Finding("R2", post, v, iso(due), iso(stop), round((stop - due).total_seconds(), 1),
                                      ticks.wall_of(due), ticks.wall_of(stop), facts))

    # ── Advisories: R3d, which the engine record cannot decide ──────────────────────────────────────────────────────
    for x in (r for r in rows if r.event == "emergency_release"):
        advisories.append(Finding(
            "R3d?", post, x.vehicle, iso(x.t), iso(x.t), 0.0, ticks.wall_of(x.t), ticks.wall_of(x.t),
            {"what": "arm.emergency_release: the car's stall pointer was cleared at the fault instant with the "
                     "connector latched (tether_phase=" + x.detail.get("tether_phase", "?") + "); no demate window is "
                     "recorded, so the charge arm's exit is not in the engine record",
             "model": "R3d forbids releasing a car before its charge arm is stowed (c_emergency_release is never "
                      "enabled by the supervisor)",
             "covered_by": "the renderer's depart gate (ottoyarddepot-sim armGate.ts) holds the drawn car until the "
                           "drawn arm is clear, bounded", "source": x.source}))
    for x in (r for r in rows if r.event == "car_left"):
        for c in cleans_of(rows, x.vehicle):
            if c["start"] < x.t and (c["end"] is None or c["end"] > x.t):
                advisories.append(Finding(
                    "R3d?", post, x.vehicle, iso(x.t), iso(c["end"]) if c["end"] else iso(end),
                    round(((c["end"] or end) - x.t).total_seconds(), 1), ticks.wall_of(x.t),
                    ticks.wall_of(c["end"]) if c["end"] else None,
                    {"what": "the car left the post while the post's cleaning-arm cycle was recorded in progress "
                             f"(started {iso(c['start'])}, {c['outcome']} {iso(c['end'])})",
                     "model": "R3d forbids releasing a car before its cleaning arm is home with the doors shut",
                     "covered_by": "the engine records no arm-home signal (db/checks/0474 5(c), frontier plan gap 5); "
                                   "the renderer's cleanGate holds the drawn car until the drawn arm is home, bounded",
                     "source": x.source}))

    return {"post": post, "rows": len(rows), "faults": [fo.get("r2", {"fault_sim": iso(fo["fault"].t)}) for fo in faults],
            "violations": [asdict(v) for v in violations], "advisories": [asdict(a) for a in advisories],
            "undecidable": undecidable}


def check_file(trace: Path, ticks_path: Path | None) -> dict:
    return check(read_trace(trace), read_ticks(ticks_path), trace.stem)


def render(rep: dict) -> str:
    L = [f"== {rep['post']}  ({rep['rows']} trace rows, {len(rep['faults'])} fault(s))"]
    for fo in rep["faults"]:
        if "release_path" not in fo:
            L.append(f"   fault {fo['fault_sim']}: R2 undecidable")
            continue
        clean = (f"clean {fo['clean_start_sim']} -> {fo['clean_end_sim']} ({fo['clean_outcome']})"
                 if fo["clean_in_progress_at_fault"] else "no clean at the fault")
        L.append(f"   fault {fo['fault_sim']} (wall {fo['fault_wall_utc']}) {fo['reason']}, repair "
                 f"{fo['repair_minutes']:g} min, out of service to {fo['out_of_service_to']}")
        L.append(f"     release path {fo['release_path']}, due {fo['release_due_sim']} ({fo['release_due_from']}); "
                 f"left {fo['left_sim']} (wall {fo['left_wall_utc']}); held {fo['held_from_fault_s']} s from the "
                 f"fault; {clean}")
        if fo.get("left_at_first_tick_after_clean_end") and fo["left_sim"] != fo["release_due_sim"]:
            L.append("     the car left at the first tick after the cleaning arm's cycle ended: the release waited for "
                     "the clean")
    if not rep["violations"]:
        L.append("   R1/R2: no violation")
    for v in rep["violations"]:
        L.append(f"   VIOLATION {v['requirement']} car {v['vehicle_id']}: {v['start_sim']} -> {v['end_sim']} "
                 f"({v['seconds']} s past due; wall {v['start_wall_utc']} -> {v['end_wall_utc']})")
    for a in rep["advisories"]:
        L.append(f"   advisory {a['requirement']} car {a['vehicle_id']} at {a['start_sim']}: {a['facts']['what']}")
    for u in rep["undecidable"]:
        L.append(f"   undecidable: {u}")
    return "\n".join(L)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("trace", nargs="?", type=Path, help="one post's trace CSV")
    ap.add_argument("--ticks", type=Path, help="the run's tick clock CSV (ticks.csv)")
    ap.add_argument("--all", type=Path, metavar="DIR", help="check every NASH-*.csv in DIR with DIR/ticks.csv")
    ap.add_argument("--json", action="store_true", help="print JSON instead of text")
    a = ap.parse_args(argv)
    try:
        if a.all:
            ticks = a.ticks or (a.all / "ticks.csv" if (a.all / "ticks.csv").exists() else None)
            reps = [check_file(p, ticks) for p in sorted(a.all.glob("*.csv")) if p.name != "ticks.csv"]
        elif a.trace:
            reps = [check_file(a.trace, a.ticks)]
        else:
            ap.error("give a TRACE.csv or --all DIR")
    except (OSError, ValueError, KeyError) as e:
        print(f"monitor: bad input: {e}", file=sys.stderr)
        return 2
    if a.json:
        print(json.dumps(reps, indent=1))
    else:
        print("\n".join(render(r) for r in reps))
        n = sum(len(r["violations"]) for r in reps)
        print(f"\n{len(reps)} post(s), {n} R1/R2 violation(s), "
              f"{sum(len(r['advisories']) for r in reps)} advisory(ies)")
    return 1 if any(r["violations"] for r in reps) else 0


if __name__ == "__main__":
    sys.exit(main())
