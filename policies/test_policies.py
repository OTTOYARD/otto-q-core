"""C5 policy battery — plain-assert, house style.

Run:  python3 policies/test_policies.py
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))

from assignment_policy import ALL_POLICIES, WaymoStagingPolicy  # noqa: E402
from harness import HarnessState, run_comparison, run_policy  # noqa: E402
from model import load_scenario  # noqa: E402

SC = HERE.parent / "solvers" / "cpsat" / "scenario_canonical.json"
ARTIFACT = HERE / "comparison_seed424242.json"


def main():
    # P1 — every policy fills the interface and yields a complete, physically
    # valid schedule (the harness raises on double-booking; we add cooldown +
    # capability checks over the bookings it kept).
    for cls in ALL_POLICIES:
        sc = load_scenario(SC)
        state = HarnessState(sc)
        assignments = cls().decide(state, list(sc["assets"]))
        assert len(assignments) == len(sc["assets"])
        cool = sc["site"]["dcfc_cooldown_min"]
        kinds = {p["id"]: p["kind"] for p in sc["service_points"]}
        by_point = {}
        for aid, pid, s, e in state.bookings:
            assert kinds[pid] in ("dcfc", "l2"), f"{cls.name}: charge on non-charge point"
            by_point.setdefault(pid, []).append((s, e))
        for pid, wins in by_point.items():
            wins.sort()
            for (s1, e1), (s2, e2) in zip(wins, wins[1:]):
                assert s2 >= e1, f"{cls.name}: overlap on {pid}"
                if kinds[pid] == "dcfc":
                    assert s2 - e1 >= cool, f"{cls.name}: cooldown violated on {pid}"
        for a in sc["assets"]:
            seg0 = state.segments[a.aid][0]
            assert seg0["start"] >= a.arrival_min, f"{cls.name}: charge before arrival"
    print(f"P1 PASS {len(ALL_POLICIES)} policies produce complete, valid, "
          "cooldown-respecting schedules")

    # P2 — CRN pairing: every policy sees the identical draw (asserted inside
    # run_comparison too; re-asserted here independently).
    d1 = [(a.aid, a.arrival_min, a.soc) for a in load_scenario(SC)["assets"]]
    d2 = [(a.aid, a.arrival_min, a.soc) for a in load_scenario(SC)["assets"]]
    assert d1 == d2, "P2 FAIL: scenario draw not deterministic in the seed"
    print("P2 PASS CRN discipline: one deterministic draw per seed, shared by all policies")

    # P3 — BYTE-FOR-BYTE: two regenerations identical, and equal to the
    # committed artifact.
    c1 = run_comparison(SC)
    c2 = run_comparison(SC)
    b1 = json.dumps(c1, indent=1, sort_keys=True) + "\n"
    b2 = json.dumps(c2, indent=1, sort_keys=True) + "\n"
    assert b1 == b2, "P3 FAIL: regeneration not byte-stable"
    assert b1 == ARTIFACT.read_text(), "P3 FAIL: regeneration differs from committed artifact"
    print(f"P3 PASS byte-for-byte: sha256 {c1['comparison_sha256'][:16]}… "
          "stable across regenerations and equal to the committed artifact")

    # P4 — the PARKED policy compiles and refuses to run.
    stub = WaymoStagingPolicy()
    try:
        stub.decide(None, [])
        raise AssertionError("P4 FAIL: parked policy ran")
    except NotImplementedError as e:
        assert "12,545,288" in str(e)
    print("P4 PASS WaymoStagingPolicy: compiles, refuses to run (US 12,545,288 B2 referenced)")

    # P5 — the four runs in the committed artifact carry the four expected names.
    names = [r["policy"] for r in c1["runs"]]
    assert names == ["fifo", "greedy", "otto_q_asis", "cpsat"], names
    print("P5 PASS four-policy comparison present: " + ", ".join(names))

    print("ALL TESTS PASS")


if __name__ == "__main__":
    main()
