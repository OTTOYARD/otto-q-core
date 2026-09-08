"""Tests for the learn loop — rejection and intractability reconciliation.

Run:  python3 -m pytest intent/test_learn.py -q

These pin the honest scope: the learn loop classifies shield refusals and
solver intractability into calibrated signals, WITHOUT learning from run
outcomes (which are contaminated — see the module docstring). Every assertion
below is about the DETERMINISTIC boundary: allowability refusals and math facts,
never decision history.
"""

from intent.learn import (
    COMMANDS_CHANNEL,
    EVENTS_CHANNEL,
    LEARNED_CONSTRAINT_TTL_SOLVES,
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


def test_the_repeat_threshold_boundary_is_exactly_where_it_says_it_is():
    """`k > entity_repeat_threshold` with a default of 2 means TWO occurrences
    are still noise and THREE are a pattern. The existing tests cover one and
    three, which is precisely the pair that cannot tell `>` from `>=` — flip the
    operator and both still pass. The boundary is the test.
    """
    twice = reconcile_refusals([Refusal("target_occupied", entity_id="s-1"),
                                Refusal("target_occupied", entity_id="s-1")])
    assert twice.is_clean(), (
        "two occurrences are at the threshold, not beyond it; flagging here "
        "would make the documented 'beyond threshold 2' rule a lie")

    # ...and the parameter is public, so lowering it moves the boundary with it.
    lowered = reconcile_refusals([Refusal("target_occupied", entity_id="s-1"),
                                  Refusal("target_occupied", entity_id="s-1")],
                                 entity_repeat_threshold=1)
    assert not lowered.is_clean()
    assert lowered.learned_constraints == {"refresh_occupancy": ["s-1"]}


def test_resource_fault_learns_the_blocked_point():
    r = reconcile_refusals([
        Refusal("resource_faulted", entity_id="s-3"),
        Refusal("resource_faulted", entity_id="s-3"),
        Refusal("resource_faulted", entity_id="s-3"),
    ])
    assert r.learned_constraints == {"block_points": ["s-3"]}


def test_the_learned_constraint_names_only_the_entities_that_crossed_the_threshold():
    """One stuck point must not take its healthy neighbours down with it.

    `reconcile_refusals` decides WHETHER to emit a constraint from the repeat
    threshold. It must populate it from the same predicate. Before this test the
    inner loop had no threshold check at all, so a single genuinely stuck point
    dragged every point that produced one one-off refusal of the same code into
    `block_points` — and the next solve lost their capacity. Every earlier test
    here used one entity, which is why nothing caught it.

    The flag message and the learned constraint must name the same entities;
    that agreement is the property under test.
    """
    recs = [Refusal("resource_faulted", entity_id="p-stuck") for _ in range(5)]
    recs += [Refusal("resource_faulted", entity_id=f"p-{i}") for i in range(58)]

    r = reconcile_refusals(recs, entity_repeat_threshold=2)

    assert r.learned_constraints["block_points"] == ["p-stuck"], (
        f"blocked {len(r.learned_constraints['block_points'])} points; only "
        f"p-stuck crossed the threshold"
    )
    # ...and the flag agrees with the constraint, which is the whole point.
    assert "['p-stuck']" in r.flags[0][2]


def test_a_code_flagged_by_one_entity_does_not_block_the_others_it_touched():
    """The narrower sibling of the above, on the occupancy code.

    Two stalls refuse once each, a third refuses four times. Only the third is
    a stuck pattern; the other two are the ordinary noise of a busy site.
    """
    r = reconcile_refusals(
        [Refusal("target_occupied", entity_id="s-1"),
         Refusal("target_occupied", entity_id="s-2")]
        + [Refusal("target_occupied", entity_id="s-3") for _ in range(4)],
        entity_repeat_threshold=2,
    )
    assert r.learned_constraints == {"refresh_occupancy": ["s-3"]}


def test_a_solver_gap_still_names_every_entity_it_touched():
    """The other half of the predicate: solver_gap codes flag on ANY occurrence,
    so every entity that carried one is in scope. Narrowing them to the repeat
    threshold would be the opposite defect — a frame that never gets reconciled.
    """
    r = reconcile_refusals([
        Refusal("target_unknown", entity_id="s-9"),
        Refusal("target_unknown", entity_id="s-8"),
    ], entity_repeat_threshold=2)
    assert r.learned_constraints == {"reconcile_frame": ["s-8", "s-9"]}


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


# ---------------------------------------------------------------------------
# L-12: a batch it could not read is not a clean batch.
# ---------------------------------------------------------------------------

class _Nulled:
    """A refusal row as migration 0086 deliberately left 14 of them: no code."""
    reason_code = None
    entity_id = "stall-1"
    rule_code = None


def test_a_batch_of_unreadable_rows_is_not_reported_clean():
    """It used to be BYTE-IDENTICAL to the report for an empty batch.

    Not counted, not in unknown_codes, no trace anywhere — and is_clean() said
    True. The loop's answer was "everything is clean" when the truth was "I
    could not read these", on a shape the live ledger actually holds.
    """
    empty = reconcile_refusals([])
    nulled = reconcile_refusals([_Nulled(), _Nulled(), _Nulled()])
    assert nulled.unreadable == 3
    assert nulled.is_clean() is False
    assert empty.is_clean() is True
    assert nulled != empty, "the two reports are still indistinguishable"


def test_a_readable_batch_reports_no_unreadable_rows():
    r = reconcile_refusals([Refusal("superseded"), Refusal("superseded")])
    assert r.unreadable == 0 and r.is_clean() is True


# ---------------------------------------------------------------------------
# L-45: rule_code was accepted, carried and discarded.
# ---------------------------------------------------------------------------

def test_the_shield_rule_that_refused_reaches_the_report_and_the_flag():
    r = reconcile_refusals([
        Refusal("command_malformed", entity_id="v-1", rule_code="HW.002"),
        Refusal("command_malformed", entity_id="v-2", rule_code="HW.003"),
    ])
    assert r.rule_codes["command_malformed"] == ("HW.002", "HW.003")
    msg = next(m for c, _n, m in r.flags if c == "command_malformed")
    assert "HW.002" in msg and "HW.003" in msg


def test_a_batch_without_rule_codes_says_nothing_about_rules():
    r = reconcile_refusals([Refusal("command_malformed", entity_id="v-1")])
    assert r.rule_codes == {}
    msg = next(m for c, _n, m in r.flags if c == "command_malformed")
    assert "shield rules" not in msg


# ---------------------------------------------------------------------------
# L-10: a learned block carries its evidence and its lifetime, and cannot
# black out the site.
# ---------------------------------------------------------------------------

def _faults(entity, n):
    return [Refusal("resource_faulted", entity_id=entity) for _ in range(n)]


def test_every_learned_entry_carries_its_evidence_and_its_expiry():
    r = reconcile_refusals(_faults("stall-1", 3), run_id="run-7")
    assert r.learned_constraints["block_points"] == ["stall-1"]
    (entry,) = r.learned_detail["block_points"]
    assert entry["entity"] == "stall-1"
    assert entry["observed_count"] == 3
    assert entry["run_id"] == "run-7"
    assert entry["expires_after_n_solves"] == LEARNED_CONSTRAINT_TTL_SOLVES == 1


def test_a_block_set_that_would_black_out_the_site_is_refused_and_flagged():
    """model.py raises a hard RuntimeError when a blocked set makes the model
    infeasible with no previous plan — so an over-large learned block takes the
    site from a degraded schedule to no schedule at all. Refusing to learn is
    the finding; a flag an operator can read beats a RuntimeError three layers
    down that they cannot."""
    batch = [r for i in range(3) for r in _faults(f"stall-{i}", 3)]
    r = reconcile_refusals(batch, capable_entities={"block_points": 4})
    assert r.learned_constraints["block_points"] == []
    msg = next(m for c, _n, m in r.flags if c == "block_points")
    assert "3 of 4" in msg and "NOT learned" in msg
    assert r.is_clean() is False


def test_a_block_set_inside_the_cap_is_learned_normally():
    batch = [r for i in range(2) for r in _faults(f"stall-{i}", 3)]
    r = reconcile_refusals(batch, capable_entities={"block_points": 10})
    assert r.learned_constraints["block_points"] == ["stall-0", "stall-1"]


def test_no_cap_binds_when_the_caller_declares_no_capacity():
    """This module refuses to guess a site's denominator."""
    batch = [r for i in range(9) for r in _faults(f"stall-{i}", 3)]
    r = reconcile_refusals(batch)
    assert len(r.learned_constraints["block_points"]) == 9


# ---------------------------------------------------------------------------
# L-11: the taxonomy says which channel each code actually arrives on.
# ---------------------------------------------------------------------------

def test_no_capacity_is_marked_as_arriving_on_a_different_channel():
    """77,435 escalations live in ottoq_events; 0 in the reason_code column
    this module's declared feed reads. tighten_capacity — the branch that tells
    the loop its capacity model is looser than the world's — is structurally
    dead against that feed, and the taxonomy now says so."""
    assert REFUSAL_TAXONOMY["no_capacity"].channel == EVENTS_CHANNEL
    reachable = [c for c, cls in REFUSAL_TAXONOMY.items()
                 if cls.channel == COMMANDS_CHANNEL]
    assert "no_capacity" not in reachable
    assert set(reachable) == set(REFUSAL_TAXONOMY) - {"no_capacity"}


def test_every_class_names_a_real_channel():
    assert {cls.channel for cls in REFUSAL_TAXONOMY.values()} <= {
        COMMANDS_CHANNEL, EVENTS_CHANNEL}
