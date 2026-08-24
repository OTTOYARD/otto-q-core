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


# ---- C5b: the cost dimension -----------------------------------------------------

def test_cost_layer_does_not_disturb_the_committed_comparison():
    """run_policy's return shape is frozen; the cost layer must not change the artifact."""
    import json as _json
    from pathlib import Path as _Path
    from harness import run_comparison as _rc
    sc = _Path(__file__).parent.parent / "solvers" / "cpsat" / "scenario_canonical.json"
    comp = _rc(sc)
    blob = _json.dumps(comp, indent=1, sort_keys=True) + "\n"
    committed = (_Path(__file__).parent / "comparison_seed424242.json").read_text()
    assert blob == committed


def test_cost_comparison_is_deterministic_and_matches_its_artifact():
    import json as _json
    from pathlib import Path as _Path
    from cost import cost_comparison
    here = _Path(__file__).parent
    sc = here.parent / "solvers" / "cpsat" / "scenario_canonical.json"
    a = cost_comparison(sc)
    b = cost_comparison(sc)
    assert a["cost_sha256"] == b["cost_sha256"]
    blob = _json.dumps(a, indent=1, sort_keys=True) + "\n"
    assert blob == (here / "cost_seed424242.json").read_text()


def test_the_solver_now_holds_both_axes_at_once():
    """DELIBERATELY REVISED 2026-08-24 -- the history matters, so it is recorded here.

    The first version of this test asserted the cheapest policy is NOT the fastest
    (cheapest == fifo), with a note that if it ever stopped holding, a policy had
    genuinely learned to do both and the revision should be deliberate. That happened
    the same day: the model was forcing parallel ops to end INSIDE the charge window,
    which pushed ops-heavy assets onto slow chargers (AV-05: 41 min of ops, 28 min of
    DCFC, exiled to a 407-minute L2 session = 118 phantom tardy-minutes). With the
    over-constraint removed, the joint solve holds tardiness at greedy's zero AND a
    bill at-or-below FIFO's. The tradeoff was never physics -- it was an artifact of
    the model, and this test now locks in that both axes are held together.
    """
    from pathlib import Path as _Path
    from cost import cost_comparison
    sc = _Path(__file__).parent.parent / "solvers" / "cpsat" / "scenario_canonical.json"
    t = cost_comparison(sc)["tradeoff"]
    assert t["total_tardy_min"]["cpsat"] == 0
    assert t["monthly_total_usd"]["cpsat"] <= t["monthly_total_usd"]["fifo"]


def test_dominated_policies_are_named():
    """A policy beaten on BOTH axes is dominated -- no weighting would choose it.

    REVISED 2026-08-24 with the ops-window fix: cpsat, previously itself dominated by
    greedy, now dominates every myopic policy -- zero tardiness at a bill at-or-below
    FIFO's leaves no axis on which fifo, greedy or otto_q_asis can win.
    """
    from pathlib import Path as _Path
    from cost import cost_comparison
    sc = _Path(__file__).parent.parent / "solvers" / "cpsat" / "scenario_canonical.json"
    t = cost_comparison(sc)["tradeoff"]
    assert set(t["pareto_optimal"]) | set(t["dominated"]) == set(t["total_tardy_min"])
    assert t["pareto_optimal"] == ["cpsat"]
    assert set(t["dominated"]) == {"fifo", "greedy", "otto_q_asis"}


def test_every_cost_artifact_states_its_assumptions():
    from pathlib import Path as _Path
    from cost import cost_comparison
    sc = _Path(__file__).parent.parent / "solvers" / "cpsat" / "scenario_canonical.json"
    c = cost_comparison(sc)
    assert len(c["assumptions"]) >= 4
    assert any("repeats" in a for a in c["assumptions"])
    assert any("power cap" in a for a in c["assumptions"])


def test_peak_lower_bound_is_a_valid_bound():
    """No policy may measure a peak below the provable lower bound.

    The bound comes from an interval argument: assets whose entire [arrival, ready_by]
    lies inside a window must deliver their energy inside it, so the average -- and
    therefore the peak -- is at least energy/duration over that window. A measured peak
    below it would mean either the bound or the harness is wrong.
    """
    from pathlib import Path as _Path
    from cost import cost_comparison, peak_lower_bound
    sc = _Path(__file__).parent.parent / "solvers" / "cpsat" / "scenario_canonical.json"
    lb = peak_lower_bound(sc)["peak_lower_bound_kw"]
    rows = cost_comparison(sc, site_ids=("site_alpha",))["sites"]["site_alpha"]["policies"]
    for name, r in rows.items():
        assert r["measured_peak_kw"] >= lb, f"{name} peak below the provable bound"


def test_headroom_shows_every_policy_leaves_more_on_the_table_than_they_differ_by():
    """The finding that reframes the comparison.

    The spread BETWEEN policies is small next to what they all leave unclaimed. If this
    ever inverts -- policies differing by more than they waste -- the objective has
    started reaching the tariff and this test should be revisited deliberately.
    """
    from pathlib import Path as _Path
    from cost import headroom
    sc = _Path(__file__).parent.parent / "solvers" / "cpsat" / "scenario_canonical.json"
    h = headroom(sc)
    left = {n: r["left_on_table_usd"] for n, r in h["policies"].items()}
    costs = [r["monthly_usd"] for r in h["policies"].values()]
    spread = max(costs) - min(costs)
    assert min(left.values()) > spread
    # every policy bills a multiple of the ideal, not a near-miss
    assert all(r["multiple_of_ideal"] >= 2.0 for r in h["policies"].values())


def test_headroom_states_its_caveat():
    from pathlib import Path as _Path
    from cost import headroom
    sc = _Path(__file__).parent.parent / "solvers" / "cpsat" / "scenario_canonical.json"
    assert "understatement" in headroom(sc)["caveat"]
