"""C5 comparison harness — CRN-paired, seed-keyed, byte-for-byte reproducible.

The discipline is ottoq_ab_runs', preserved exactly:
  * ONE scenario draw per seed (`load_scenario` is deterministic in the seed),
    shared verbatim across every policy — common random numbers, so per-asset
    differences are paired differences;
  * policies consume no randomness of their own;
  * the emitted comparison dict contains no timestamps and is serialized with
    sorted keys, so the same seed reproduces the same bytes and sha256.

Physics are the C4 model's own (charge_segments; 18-min DCFC cooldown on the
point; 4-min moves; wash after charge). Wash/inspect routing is identical
FCFS for every policy so the comparison isolates the charge-assignment
decision — the axis the four policies actually differ on.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "solvers" / "cpsat"))
from model import charge_segments, load_scenario  # noqa: E402


class HarnessState:
    def __init__(self, sc):
        self.sc = sc
        self._free = {p["id"]: 0 for p in sc["service_points"]}
        self._order = {p["id"]: i for i, p in enumerate(sc["service_points"])}
        self.bookings = []          # (aid, point_id, start, end) charge only
        self.segments = {}          # aid -> [{kw, minutes, start, end}]

    def charge_points(self):
        return [p for p in self.sc["service_points"] if p["kind"] in ("dcfc", "l2")]

    def point(self, pid):
        return next(p for p in self.sc["service_points"] if p["id"] == pid)

    def point_order(self, pid):
        return self._order[pid]

    def point_free_at(self, pid):
        return self._free[pid]

    def book_charge(self, asset, point, start):
        segs, t = [], start
        for seg in charge_segments(self.sc, asset, point["kw"]):
            segs.append({**seg, "start": t, "end": t + seg["minutes"]})
            t += seg["minutes"]
        cool = self.sc["site"]["dcfc_cooldown_min"] if point["kind"] == "dcfc" else 0
        assert start >= self._free[point["id"]], \
            f"double-booking {point['id']}: start {start} < free {self._free[point['id']]}"
        self._free[point["id"]] = t + cool
        self.bookings.append((asset.aid, point["id"], start, t))
        self.segments[asset.aid] = segs
        return t


def run_policy(sc, policy) -> dict:
    """The committed comparison's per-policy result. Return shape is FROZEN.

    `comparison_seed424242.json` is asserted byte-for-byte by test_policies.py, so
    adding a key here changes a committed artifact's sha256. Anything that needs more
    than these metrics should use `run_policy_traced`, which returns this dict
    unchanged plus the harness state -- the load curve included.
    """
    result, _ = run_policy_traced(sc, policy)
    return result


def run_policy_traced(sc, policy):
    """`run_policy` plus the state it built, so the site load curve is recoverable.

    The harness already computes the kW event stream to take its maximum; discarding
    it afterwards is what left `peak_site_kw` as the only power fact the comparison
    could report, and therefore why the tariff never reached the objective
    (docs/BENCHMARK_CREDIBILITY.md). Returning the state costs nothing and lets the
    cost layer bill the same schedule the metrics describe -- the same run, not a
    re-derivation that could drift from it.
    """
    state = HarnessState(sc)
    assignments = policy.decide(state, list(sc["assets"]))
    assert len(assignments) == len(sc["assets"]), f"{policy.name}: unassigned assets"

    # identical downstream routing for every policy: FCFS wash, then inspect
    mv = sc["site"]["move_duration_min"]
    wash_free = {p["id"]: 0 for p in sc["service_points"] if p["kind"] == "wash_bay"}
    svc_free = {p["id"]: 0 for p in sc["service_points"] if p["kind"] == "service_bay"}
    per_asset, events = {}, []
    charge_end = {aid: segs[-1]["end"] for aid, segs in state.segments.items()}
    for asset in sorted(sc["assets"], key=lambda a: (charge_end[a.aid], a.aid)):
        finish = charge_end[asset.aid]
        moves = 0
        if asset.needs_wash:
            pid = min(wash_free, key=lambda k: (wash_free[k], k))
            ws = max(finish + mv, wash_free[pid])
            wash_free[pid] = ws + 12
            finish = ws + 12
            moves += 1
        if asset.needs_inspect:
            pid = min(svc_free, key=lambda k: (svc_free[k], k))
            isv = max(finish + mv, svc_free[pid])
            svc_free[pid] = isv + 20
            finish = isv + 20
            moves += 1
        segs = state.segments[asset.aid]
        for s in segs:
            events.append((s["start"], s["kw"]))
            events.append((s["end"], -s["kw"]))
        per_asset[asset.aid] = {
            "arrival": asset.arrival_min, "soc": asset.soc,
            "charge_start": segs[0]["start"], "charge_end": segs[-1]["end"],
            "wait_min": segs[0]["start"] - asset.arrival_min,
            "finish": finish, "ready_by": asset.ready_by_min,
            "tardy_min": max(0, finish - asset.ready_by_min),
            "moves": moves,
        }

    events.sort()
    load = peak = 0
    for _, d in events:
        load += d
        peak = max(peak, load)
    waits = sorted(a["wait_min"] for a in per_asset.values())
    p95 = waits[max(0, int(round(0.95 * len(waits))) - 1)]
    charge_pts = [p["id"] for p in sc["service_points"] if p["kind"] in ("dcfc", "l2")]
    turns = sum(1 for _, pid, _, _ in state.bookings if pid in charge_pts)
    return {
        "policy": policy.name,
        "assets": {k: per_asset[k] for k in sorted(per_asset)},
        "metrics": {
            "total_tardy_min": sum(a["tardy_min"] for a in per_asset.values()),
            "p95_wait_to_first_op_min": p95,
            "peak_site_kw": peak,
            "charge_point_turns": turns,
            "total_moves": sum(a["moves"] for a in per_asset.values()),
            "makespan_min": max(a["finish"] for a in per_asset.values()),
        },
    }, state


def run_comparison(scenario_path) -> dict:
    from assignment_policy import ALL_POLICIES
    sc = load_scenario(scenario_path)
    runs = []
    for cls in ALL_POLICIES:
        sc_fresh = load_scenario(scenario_path)   # same seed -> same draw (CRN)
        runs.append(run_policy(sc_fresh, cls()))
    # CRN attestation: every policy saw the identical arrival stream
    base = runs[0]["assets"]
    for r in runs[1:]:
        for aid in base:
            assert r["assets"][aid]["arrival"] == base[aid]["arrival"]
            assert r["assets"][aid]["soc"] == base[aid]["soc"]
    baseline = next(r for r in runs if r["policy"] == "fifo")["metrics"]
    comparison = {
        "scenario": sc["name"], "seed": sc["seed"],
        "crn_pairing": "one scenario draw per seed, shared by all policies",
        "runs": runs,
        "paired_delta_vs_fifo": {
            r["policy"]: {k: r["metrics"][k] - baseline[k] for k in baseline}
            for r in runs if r["policy"] != "fifo"
        },
    }
    comparison["comparison_sha256"] = hashlib.sha256(
        json.dumps(comparison, sort_keys=True).encode()).hexdigest()
    return comparison
