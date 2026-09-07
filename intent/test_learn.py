"""Tests for the learn loop — rejection and intractability reconciliation.

Run:  python3 -m pytest intent/test_learn.py -q

These pin the honest scope: the learn loop classifies shield refusals and
solver intractability into calibrated signals, WITHOUT learning from run
outcomes (which are contaminated — see the module docstring). Every assertion
below is about the DETERMINISTIC boundary: allowability refusals and math facts,
never decision history.
"""

from intent.learn import (
    REFUSAL_CODES,
    REFUSAL_TAXONOMY,
    Refusal,
    diagnose_solver,
    reconcile_refusals,
)

#: The production vocabulary from migration 0086, verbatim.
EXPECTED_CODES = (
    "command_malformed", "no_capacity", "resource_faulted", "run_ended",
    "superseded", "target_occupied", "target_unknown", "vehicle_declined",
    "vehicle_state_incompatible", "vehicle_unresponsive",
)


# ---- the taxonomy is TOTAL over the production vocabulary ------------------------

def test_taxonomy_covers_exactly_the_production_vocabulary():
    assert REFUSAL_CODES == tuple(sorted(EXPECTED_CODES)), (
        f"taxonomy {REFUSAL_CODES} drifted from migration 0086 vocabulary "
        f"{tuple(sorted(EXPECTED_CODES))} — reconcile, never absorb")


def test_every_code_classifies_into_a_known_kind():
    valid = {"transient", "live_world", "solver_gap"}
    for code, cls in REFUSAL_TAXONOMY.items():
        assert cls.kind in valid, f"{code}: bad kind {cls.kind!r}"
    # and the three classes are all exercised by the vocabulary
    kinds = {c.kind for c in REFUSAL_TAXONOMY.values()}
    assert kinds == valid, f"taxonomy kinds {kinds} do not span {valid}"


def test_the_transient_codes_are_exactly_superseded_and_run_ended():
    transient = {c for c, k in REFUSAL_TAXONOMY.items() if k.kind == "transient"}
    assert transient == {"superseded", "run_ended"}


def test_the_solver_gap_codes_carry_no_false_reassurance():
    gaps = {c: k.learned_constraint for c, k in REFUSAL_TAXONOMY.items()
            if k.kind == "solver_gap"}
    assert gaps == {
        "target_unknown": "reconcile_frame",
        "command_malformed": "fix_emitter",
        "no_capacity": "tighten_capacity",
    }


# ---- reconciliation: classification and flagging ---------------------------------

def test_clean_batch_of_transients_flags_nothing():
    r = reconcile_refusals([Refusal("superseded"), Refusal("run_ended")])
    assert r.is_clean()
    assert r.flags == ()
    assert r.learned_constraints == {}
    assert r.counts == {"superseded": 1, "run_ended": 1}


def test_a_solver_gap_flags_on_a_single_occurrence():
    r = reconcile_refusals([Refusal("command_malformed")])
    assert not r.is_clean()
    assert [f[0] for f in r.flags] == ["command_malformed"]
    assert r.learned_constraints == {"fix_emitter": []}


def test_live_world_flags_only_on_entity_repetition():
    # a single diffuse occupancy refusal is noise — no flag
    once = reconcile_refusals([Refusal("target_occupied", entity_id="s-1")])
    assert once.is_clean()

    # the same stall refused three times is a stuck pattern — flag + constraint
    thrice = reconcile_refusals([
        Refusal("target_occupied", entity_id="s-1"),
        Refusal("target_occupied", entity_id="s-1"),
        Refusal("target_occupied", entity_id="s-1"),
    ])
    assert not thrice.is_clean()
    assert [f[0] for f in thrice.flags] == ["target_occupied"]
    assert thrice.learned_constraints == {"refresh_occupancy": ["s-1"]}


def test_resource_fault_learns_the_blocked_point():
    r = reconcile_refusals([
        Refusal("resource_faulted", entity_id="s-3"),
        Refusal("resource_faulted", entity_id="s-3"),
        Refusal("resource_faulted", entity_id="s-3"),
    ])
    assert r.learned_constraints == {"block_points": ["s-3"]}


def test_unknown_codes_are_named_never_absorbed():
    r = reconcile_refusals([
        Refusal("superseded"),
        Refusal("definitely_not_a_code"),
        Refusal("also_bogus"),
    ])
    assert r.unknown_codes == ("also_bogus", "definitely_not_a_code")
    # the known code still classifies and the bogus ones do not poison the report
    assert r.counts == {"superseded": 1}
    assert not r.is_clean()          # unknown codes make the report dirty


def test_a_missing_reason_code_is_skipped_as_malformed_input():
    """The name promised a malformed record; the body passed two well-formed ones.

    Both records were Refusal("superseded"). Nothing in this test had a missing
    reason_code, so `_pairs`' `if isinstance(rc, str)` guard -- the line the test
    is named for -- was never exercised, and deleting it left the test green.
    """
    #: a None code and a duck-typed record with no attribute at all: two shapes
    #: a real ottoq_vehicle_commands row can arrive in
    class _NoCode:
        entity_id = "s-9"

    r = reconcile_refusals([
        Refusal("superseded"),
        Refusal(None),            # type: ignore[arg-type]
        Refusal("superseded"),
        _NoCode(),
    ])
    assert r.counts == {"superseded": 2}, (
        f"a malformed record leaked into the counts: {r.counts}")
    assert r.unknown_codes == (), (
        "a missing reason_code is malformed INPUT, not an unknown vocabulary "
        f"word; it must not be reported as one: {r.unknown_codes}")


def test_reconciliation_is_deterministic():
    batch = [Refusal("resource_faulted", entity_id="s-3"),
             Refusal("resource_faulted", entity_id="s-3"),
             Refusal("resource_faulted", entity_id="s-3"),
             Refusal("no_capacity"),
             Refusal("superseded")]
    a = reconcile_refusals(batch)
    b = reconcile_refusals(batch)
    assert a == b


def test_duck_typed_records_are_accepted():
    class Row:
        def __init__(self, rc, eid=None):
            self.reason_code = rc
            self.entity_id = eid
    r = reconcile_refusals([Row("no_capacity"), Row("run_ended")])
    assert r.counts == {"no_capacity": 1, "run_ended": 1}
    assert [f[0] for f in r.flags] == ["no_capacity"]


# ---- solver intractability diagnosis ---------------------------------------------

def test_optimal_and_feasible_are_solved_states():
    assert diagnose_solver("OPTIMAL").kind == "solved"
    assert diagnose_solver("FEASIBLE").kind == "solved_bounded"


def test_infeasible_distinguishes_rejection_on_or_off():
    off = diagnose_solver("INFEASIBLE")
    assert off.kind == "intractable"
    assert "enable rejection" in off.next_action

    on = diagnose_solver("INFEASIBLE", allow_rejection=True)
    assert "rejection enabled" in on.next_action
    assert "honest capacity limit" in on.next_action


def test_unknown_distinguishes_retained_plan():
    bare = diagnose_solver("UNKNOWN")
    assert "raise the deterministic budget" in bare.next_action
    held = diagnose_solver("UNKNOWN", has_previous_plan=True)
    assert "retained" in held.next_action


def test_model_invalid_is_a_bug_not_a_capacity_question():
    d = diagnose_solver("MODEL_INVALID")
    assert d.kind == "model_bug"
    assert "fix the model" in d.next_action


def test_an_unrecognized_status_is_named_not_absorbed():
    d = diagnose_solver("QUANTUM_SOLVED")
    assert d.recognized is False
    assert d.kind == "unknown"
    assert "unrecognized solver status" in d.next_action


# ---- the loop closes: learned constraints plug into the next solve ----------------

def test_learned_block_points_plug_into_the_next_solve():
    """The loop stays engaged: a faulted point, learned from refusals, is passed
    as `blocked_points` to the next solve and the solver routes around it.

    This is the closed loop in miniature, and it is clean: the refusal is shield
    output (allowability), the solve is over the declared world — no decision
    history, no run outcomes, no contamination.
    """
    import sys as _sys
    from pathlib import Path as _Path
    _sys.path.insert(0, str(_Path(__file__).parent.parent / "solvers" / "cpsat"))
    from model import build_and_solve, load_scenario  # noqa: E402

    SC = _Path(__file__).parent.parent / "solvers" / "cpsat" / "scenario_canonical.json"

    # Learn a stuck fault on a real charge point from three refusals.
    r = reconcile_refusals([
        Refusal("resource_faulted", entity_id="NASH-DCFC-01"),
        Refusal("resource_faulted", entity_id="NASH-DCFC-01"),
        Refusal("resource_faulted", entity_id="NASH-DCFC-01"),
    ])
    assert r.learned_constraints["block_points"] == ["NASH-DCFC-01"]

    blocked = set(r.learned_constraints["block_points"])
    plan = build_and_solve(load_scenario(SC), blocked_points=blocked)

    # The solver honored the learned constraint: nobody is routed to the down point.
    for a in plan["assets"]:
        for op in a["ops"]:
            if op["op"] == "charge":
                assert op["point"] not in blocked, (
                    f"{a['aid']} routed to blocked {op['point']} — the learned "
                    "constraint did not reach the next solve")


if __name__ == "__main__":
    for fn in [v for k, v in sorted(globals().items()) if k.startswith("test_")]:
        fn()
        print(f"{fn.__name__} PASS")
    print("ALL LEARN TESTS PASS")
