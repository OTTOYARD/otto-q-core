"""The regime-driven orchestration — the intent actually reorders the schedule.

Run:  python3 -m pytest policies/test_regime.py -q

The claim under test is the whole point of the intent layer: with the third
variable lever (min_flow, dwell/turnaround) added to the model, the regime is no
longer decorative. dispatch_rush and demand_surge order throughput before
energy, grid_peak and overnight order energy first, and the schedules they
produce genuinely differ while every one holds the readiness floor.

THE TRADE-OFF IS REAL AND MEASURED, not asserted by prose. On the canonical
scenario (seed 424242, pinned ortools 9.15.6755):

    grid_peak  (min_tardy, min_peak):       flow 2937 min, peak 150 kW
    rush       (min_tardy, min_flow, min_peak): flow 1676 min, peak 400 kW

Rush finishes the fleet ~1260 finish-minutes sooner and pays for it with a
~250 kW higher peak (a real demand-charge delta at NES GSA-3's $21.40/kW).
That is the regime meaning something, in numbers.

PERFORMANCE FINDINGS, STATED NOT HIDDEN (2026-09-07):
  1. min_flow does NOT prove OPTIMAL on the slack canonical scenario — the flow
     objective has a large flat region, so the search runs to its deterministic
     budget and returns FEASIBLE. Determinism comes from the budget, not from
     optimality, so the plan is still byte-stable; only the third tier is
     truncated while the first two (tardiness, peak) are proven OPTIMAL.
  2. A flow-first chain (rush) makes the trailing peak pass harder: holding the
     tight flow ceiling, min_peak needs ~1.0 work-units to find a solution where
     the energy-first chain proves OPTIMAL at 0.03. Below that it returns UNKNOWN
     and the chain reports optima["min_peak"] = None (the retained-pass guard)
     rather than misreporting the retained plan's objective as a peak.
  A cheaper per-tick formulation of the flow pass is the honest open item for
  the live hot path; for offline planning and the demo the current solver is fine.
"""

import dataclasses
import json
import sys
import types
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))

from model import build_and_solve, load_scenario  # noqa: E402
from forward import lexicographic_solve, lexicographic_solve_traced  # noqa: E402
import regime  # noqa: E402
from regime import intent_orchestrate, resolve_active  # noqa: E402
from intent.intent import ARTIFACT_PATH, load_intent, stamp  # noqa: E402
from intent.solve import pass_sequence  # noqa: E402

SC = HERE.parent / "solvers" / "cpsat" / "scenario_canonical.json"

#: Deterministic budget for tests where the flow pass is LAST (determinism /
#: floor / 3-pass-reduces-flow / demand_surge). min_flow never proves optimal
#: here; a modest budget captures most of the flow gain and stays byte-stable.
FLOW_BUDGET = {"det_budget_s": 0.5}

#: Flow-FIRST (rush) needs more budget: the trailing peak pass holds a tight flow
#: ceiling and needs ~1.0 work-units to find a solution (see module docstring).
RUSH_BUDGET = {"det_budget_s": 1.5}


def _peak_from_plan(plan):
    """The plan's OWN peak, rebuilt from its charge segments.

    Never plan["site_peak_kw"]: that field is present only when a min_peak pass
    ran last, and reading a reported optimum to check a plan is the mistake this
    test exists to catch.
    """
    ev = []
    for a in plan["assets"]:
        for op in a["ops"]:
            if op["op"] == "charge":
                for seg in op["segments"]:
                    ev.append((seg["start"], seg["kw"]))
                    ev.append((seg["end"], -seg["kw"]))
    ev.sort()
    load = peak = 0
    for _, d in ev:
        load += d
        peak = max(peak, load)
    return peak


def test_every_pass_order_holds_every_earlier_optimum_in_the_shipped_plan():
    """The chain's central claim, measured on the plan rather than re-reported.

    lexicographic_solve threads each pass's optimum into the passes after it.
    The min_peak branch's threading of max_flow_total IS covered -- mutating it
    away turns test_rush_and_grid_peak_produce_different_schedules red. The
    min_flow branch's threading of max_peak_total was covered by NOTHING:
    deleting it left all 109 tests green while the overnight/steady_state chain
    (the pass order two of the six regimes resolve to) shipped a plan peaking at
    460 kW after its own min_peak pass had proved 150.

    So this checks the property directly, on both three-pass orders, by
    recomputing tardiness, flow and peak FROM THE FINAL PLAN and comparing them
    against what each earlier pass reported. A ceiling that is not threaded shows
    up here as a shipped plan worse than an optimum the chain claims it held.
    """
    for modes in (("min_tardy", "min_peak", "min_flow"),
                  ("min_tardy", "min_flow", "min_peak")):
        budget = RUSH_BUDGET if modes[1] == "min_flow" else FLOW_BUDGET
        plan, optima, passes = lexicographic_solve_traced(
            load_scenario(SC), list(modes), budget=budget)
        got = {"min_tardy": _tardy(plan), "min_flow": _flow(plan),
               "min_peak": _peak_from_plan(plan)}
        for i, mode in enumerate(modes[:-1]):          # every pass but the last
            held = optima.get(mode)
            if held is None:
                continue                                # retained pass: nothing held
            assert got[mode] <= held, (
                f"pass order {modes}: the {mode} pass reported {held}, but the "
                f"SHIPPED plan measures {got[mode]} -- a later pass discarded an "
                f"optimum the chain claims it held. This is the max_flow_total "
                f"class of bug, in whichever branch dropped the ceiling.")
        print(f"chain {modes} -> tardy {got['min_tardy']} flow {got['min_flow']} "
              f"peak {got['min_peak']}; optima {optima}")


def _flow(plan):
    return sum(a["finish"] for a in plan["assets"] if a["finish"] is not None)


def _tardy(plan):
    return sum(a["tardy_min"] for a in plan["assets"]
               if a["tardy_min"] is not None)


# ---- the third lever: min_flow is a valid lexicographic pass -------------------

def test_min_flow_is_deterministic():
    a = build_and_solve(load_scenario(SC), objective_mode="min_flow",
                        max_tardy_total=0, **FLOW_BUDGET)
    b = build_and_solve(load_scenario(SC), objective_mode="min_flow",
                        max_tardy_total=0, **FLOW_BUDGET)
    assert a["plan_sha256"] == b["plan_sha256"]


def test_min_flow_holds_the_tardiness_floor():
    p = build_and_solve(load_scenario(SC), objective_mode="min_flow",
                        max_tardy_total=0, **FLOW_BUDGET)
    assert _tardy(p) == 0


def test_min_flow_reports_a_real_peak_ceiling_chain():
    _, opt = lexicographic_solve(load_scenario(SC),
                                 ("min_tardy", "min_peak", "min_flow"),
                                 budget=FLOW_BUDGET)
    assert "min_tardy" in opt and "min_peak" in opt and "min_flow" in opt
    assert opt["min_peak"] > 0   # the canonical site carries real load


def test_three_pass_reduces_flow_vs_two_pass_holding_both_axes():
    two, _ = lexicographic_solve(load_scenario(SC), ("min_tardy", "min_peak"))
    three, _ = lexicographic_solve(load_scenario(SC),
                                   ("min_tardy", "min_peak", "min_flow"),
                                   budget=FLOW_BUDGET)
    # the third pass can only improve (or tie) flow while holding tardiness+peak
    assert _tardy(three) <= _tardy(two)
    assert _flow(three) <= _flow(two)


def test_chain_reports_an_unreachable_ceiling_as_none():
    # A flow-first chain at a budget too small for the trailing peak pass must
    # NOT report the retained plan's objective as a peak. The guard records the
    # failed pass as None and the flow optimum that DID complete stays intact.
    _, opt = lexicographic_solve(load_scenario(SC),
                                 ("min_tardy", "min_flow", "min_peak"),
                                 budget={"det_budget_s": 0.4})
    assert opt["min_flow"] is not None      # the flow pass completed
    assert opt["min_peak"] is None          # the peak pass did not — reported


# ---- the regime reorders the schedule -------------------------------------------

def test_regime_resolves_the_pinned_regimes():
    assert resolve_active(7).regime_key == "dispatch_rush"
    assert resolve_active(22).regime_key == "overnight"
    assert resolve_active(15).regime_key == "steady_state"
    assert resolve_active(14, frozenset({"grid_peak_imminent"})).regime_key == "grid_peak"
    assert resolve_active(14, frozenset({"demand_surge"})).regime_key == "demand_surge"
    assert resolve_active(14, frozenset({"weather_hold"})).regime_key == "weather_event"


def test_rush_and_grid_peak_produce_different_schedules():
    rush, _, orush = intent_orchestrate(load_scenario(SC), hour_of_day=7,
                                        budget=RUSH_BUDGET)
    peak, _, opeak = intent_orchestrate(load_scenario(SC), hour_of_day=14,
                                        signals=frozenset({"grid_peak_imminent"}))
    # both hold the readiness floor (the canonical scenario is slack -> 0 tardy)
    assert _tardy(rush) == 0 and _tardy(peak) == 0
    # the rush chain completed (both soft passes reached an optimum)
    assert orush["min_flow"] is not None and orush["min_peak"] is not None
    # the regime means something: rush finishes the fleet sooner ...
    assert _flow(rush) < _flow(peak)
    # ... and pays for it with a higher peak — the throughput-vs-energy trade-off
    assert orush["min_peak"] > opeak["min_peak"]
    # and they are genuinely different schedules — not one plan under two labels
    assert rush["plan_sha256"] != peak["plan_sha256"]


def test_demand_surge_prioritizes_flow_over_energy():
    surge, active, opt = intent_orchestrate(load_scenario(SC), hour_of_day=14,
                                            signals=frozenset({"demand_surge"}),
                                            budget=FLOW_BUDGET)
    assert active.regime_key == "demand_surge"
    assert "min_flow" in opt and "min_peak" not in opt   # no energy pass in surge


def test_grid_peak_prioritizes_energy_without_flow():
    peak, active, opt = intent_orchestrate(load_scenario(SC), hour_of_day=14,
                                           signals=frozenset({"grid_peak_imminent"}))
    assert active.regime_key == "grid_peak"
    assert "min_peak" in opt and "min_flow" not in opt


# ---- the floor is structural across every regime --------------------------------

def test_floor_is_always_first_through_the_orchestrator():
    combos = [(0, frozenset()), (7, frozenset()), (22, frozenset()),
              (14, frozenset({"grid_peak_imminent"})),
              (14, frozenset({"demand_surge"})),
              (14, frozenset({"weather_hold"}))]
    for h, sigs in combos:
        plan, active, opt = intent_orchestrate(load_scenario(SC),
                                               hour_of_day=h, signals=sigs,
                                               budget=FLOW_BUDGET)
        assert "min_tardy" in opt
        assert active.priority[0] == "readiness"


def test_regime_policy_books_a_valid_complete_schedule():
    from harness import HarnessState
    from regime import RegimeOrchestratorPolicy
    sc = load_scenario(SC)
    state = HarnessState(sc)
    assignments = RegimeOrchestratorPolicy(hour_of_day=7,
                                           budget=RUSH_BUDGET).decide(
        state, list(sc["assets"]))
    assert len(assignments) == len(sc["assets"])
    kinds = {p["id"]: p["kind"] for p in sc["service_points"]}
    by_point = {}
    for aid, pid, s, e in state.bookings:
        assert kinds[pid] in ("dcfc", "l2")
        by_point.setdefault(pid, []).append((s, e))
    for pid, wins in by_point.items():
        wins.sort()
        for (s1, e1), (s2, e2) in zip(wins, wins[1:]):
            assert s2 >= e1, f"overlap on {pid}"

# ---- rejection composes with the chain -------------------------------------------

def test_chain_supports_rejection_and_reads_the_true_peak():
    import json as _json
    from model import materialize
    sc = _json.loads(SC.read_text())
    charge = [p for p in sc["service_points"] if p["kind"] in ("dcfc", "l2")][:2]
    sc["service_points"] = charge + [p for p in sc["service_points"]
                                     if p["kind"] not in ("dcfc", "l2")]
    sc["horizon_min"] = 300
    m = materialize(_json.loads(_json.dumps(sc)))
    plan, opt, passes = lexicographic_solve_traced(
        m, ("min_tardy", "min_peak"), budget={"allow_rejection": True})
    assert plan.get("rejected"), "rejection enabled but nothing was rejected"
    assert opt["min_peak"] is not None and opt["min_peak"] < 100_000, (
        f"peak misread from the rejection-inflated objective: {opt['min_peak']}")
    assert [p["mode"] for p in passes] == ["min_tardy", "min_peak"]
    assert all("status" in p and "objective" in p for p in passes)


def test_the_readiness_floor_cannot_be_demoted_out_of_first_place():
    """min_tardy leads every lexicographic chain because readiness is a floor,
    not a preference: it is the one objective the site cannot trade away. The
    solver enforces that, and every call site in the repo happens to pass a
    conforming list -- so deleting the guard left the whole suite green and the
    structural claim rested on nobody making a mistake.
    """
    import pytest as _pytest
    with _pytest.raises(ValueError, match="must begin with min_tardy"):
        lexicographic_solve(load_scenario(SC), ("min_peak", "min_tardy"))
    with _pytest.raises(ValueError, match="must begin with min_tardy"):
        lexicographic_solve(load_scenario(SC), ())


# ---------------------------------------------------------------------------
# L-52: the commander's intent is a parameter, not a process-global singleton.
# ---------------------------------------------------------------------------

def _reversed_priority_intent():
    """The kernel intent with every regime's soft priority reversed.

    A DIFFERENT DOCTRINE over the same objectives -- which is what a pack from
    another sector is. min_tardy still leads every chain because the resolver
    prepends the readiness floor structurally; what a pack reorders is the rest.
    """
    base = load_intent()
    return dataclasses.replace(
        base,
        regimes=tuple(dataclasses.replace(r, priority=tuple(reversed(r.priority)))
                      for r in base.regimes))


def test_an_intent_override_changes_the_pass_order_it_resolves():
    assert pass_sequence(resolve_active(7)) != pass_sequence(
        resolve_active(7, intent=_reversed_priority_intent())), (
        "the fixture no longer distinguishes the two doctrines")


def test_the_regime_policy_carries_an_intent_down_to_the_chain(monkeypatch):
    """The defect L-52 names: the override existed and this caller dropped it."""
    seen = {}

    def _spy(sc, modes, *, budget=None):
        seen["modes"] = list(modes)
        return {"assets": []}, {}

    monkeypatch.setattr(regime, "lexicographic_solve", _spy)
    pack = _reversed_priority_intent()
    policy = regime.RegimeOrchestratorPolicy(hour_of_day=7, intent=pack)
    policy.decide(types.SimpleNamespace(sc={}), [])
    assert seen["modes"] == list(pass_sequence(resolve_active(7, intent=pack)))
    assert seen["modes"] != list(pass_sequence(resolve_active(7)))


def test_a_pack_without_its_own_artifact_gets_the_kernel_default():
    assert regime.intent_for_pack("no_such_pack_anywhere") is regime.INTENT
    assert regime.intent_for_pack(None) is regime.INTENT


def test_a_pack_that_ships_an_intent_artifact_gets_its_own(tmp_path,
                                                           monkeypatch):
    raw = json.loads(ARTIFACT_PATH.read_text())
    for r in raw["regimes"]:
        r["priority"] = list(reversed(r["priority"]))
    dest = tmp_path / "mining_intent_v1.json"
    dest.write_text(json.dumps(raw))
    stamp(dest)                    # a pack's artifact is fingerprinted too

    monkeypatch.setattr(regime, "PACK_INTENT_DIR", tmp_path)
    monkeypatch.setattr(regime, "_PACK_INTENTS", {})
    loaded = regime.intent_for_pack("mining")
    assert loaded is not regime.INTENT
    assert pass_sequence(resolve_active(7, intent=loaded)) != \
        pass_sequence(resolve_active(7))


# ---------------------------------------------------------------------------
# L-18: a pass that produced nothing reports nothing, in every field.
# ---------------------------------------------------------------------------

def test_a_retained_pass_publishes_no_leftover_number(monkeypatch):
    """The guard suppressed the leftover in `optima` and published it in `passes`.

    `passes` travels verbatim into the proposer's fire record, so the previous
    pass's objective was reported under THIS pass's mode, with the previous
    pass's deterministic_time and its `reproducible: true` — for a pass that
    returned no schedule at all. That is precisely the number the guard's own
    comment says it exists to suppress, moved one field over.
    """
    import forward as fwd
    real = fwd.build_and_solve
    calls = {"n": 0}

    def _retain_the_second_pass(sc, **kw):
        calls["n"] += 1
        plan = real(sc, **kw)
        if calls["n"] == 2:
            #: exactly what model.py returns when a pass cannot solve: the
            #: PREVIOUS plan, carrying the previous pass's objective and repro.
            return {**plan, "retained_previous": True, "solver_status": "UNKNOWN"}
        return plan

    monkeypatch.setattr(fwd, "build_and_solve", _retain_the_second_pass)
    sc = load_scenario(SC)
    _plan, optima, passes = fwd.lexicographic_solve_traced(
        sc, ("min_tardy", "min_peak"), budget=FLOW_BUDGET)

    assert len(passes) == 2
    second = passes[1]
    assert second["retained"] is True
    assert optima["min_peak"] is None, "the guard's original half still holds"
    for field in ("objective", "deterministic_time"):
        assert second[field] is None, (
            f"the retained pass published the PREVIOUS pass's {field}: "
            f"{second[field]!r}")
    assert second["reproducible"] is False and second["proven"] is False
    #: ...and a pass that DID solve still reports its own numbers.
    assert passes[0]["retained"] is False
    assert passes[0]["objective"] is not None


# ---------------------------------------------------------------------------
# L-21: a rejected asset is abstained on, not crashed on.
# ---------------------------------------------------------------------------

class _FakeArrival:
    def __init__(self, aid):
        self.aid = aid


class _FakeState:
    """The two calls decide() makes on its state, and nothing else."""
    sc = {}

    def __init__(self):
        self.booked = []

    def point(self, pid):
        return pid

    def book_charge(self, asset, point, start):
        self.booked.append((asset.aid, point, start))


def _plan_missing_one(aids, rejected):
    return {"assets": [
        {"aid": aid, "ops": ([] if aid in rejected else
                             [{"op": "charge", "point": "p1", "start": 0}])}
        for aid in aids]}


def test_the_regime_policy_abstains_on_a_rejected_asset_instead_of_raising(
        monkeypatch):
    """allow_rejection is an advertised budget key, and it crashed the policy.

    A rejected asset leaves the plan with `ops: []` (model.py), so it never
    enters `starts`; indexing it raised KeyError for every arrival, destroying
    the abstain-vs-crash distinction the rejection feature exists to preserve.
    The plan's own `proposals` list already carries the declined asset with
    abstain: true, so the policy simply returns no Assignment for it.
    """
    aids = ["v-a", "v-b", "v-c"]
    monkeypatch.setattr(regime, "intent_orchestrate",
                        lambda sc, h, sig, budget=None, intent=None:
                        (_plan_missing_one(aids, {"v-b"}), None, {}))
    state = _FakeState()
    out = regime.RegimeOrchestratorPolicy(hour_of_day=7).decide(
        state, [_FakeArrival(a) for a in aids])
    assert [a.aid for a in out] == ["v-a", "v-c"]
    assert [b[0] for b in state.booked] == ["v-a", "v-c"]


def test_the_forward_policy_abstains_on_a_rejected_asset_too(monkeypatch):
    import forward as fwd
    aids = ["v-a", "v-b"]
    monkeypatch.setattr(fwd, "lexicographic_solve",
                        lambda sc, modes, budget=None:
                        (_plan_missing_one(aids, {"v-a"}), {}))
    state = _FakeState()
    out = fwd.ForwardOrchestratorPolicy().decide(
        state, [_FakeArrival(a) for a in aids])
    assert [a.aid for a in out] == ["v-b"]
