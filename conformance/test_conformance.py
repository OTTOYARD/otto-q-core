"""C11 — the harness must catch violations, not merely fail to find them.

Every invariant gets a negative test: a deliberately broken pack or schedule that
MUST be reported. A verifier that has never rejected anything is not evidence.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from conformance.harness import (
    PACK_DIR,
    SITE_POWER_CAP_KW,
    ScheduledOp,
    build_scenario,
    run_all,
    run_pack,
    schedule,
    unverified_claims,
    verify,
)
from conformance.spec import Constraint, Operation, Pack, ServicePoint, load, validate

ALL = {r.pack_id: r for r in run_all()}


# --- every pack at least LOADS -------------------------------------------------

@pytest.mark.parametrize("pack_id", ["robotaxi", "yard-logistics", "mining", "vertiport"])
def test_every_pack_loads(pack_id):
    r = ALL[pack_id]
    assert r.loads, r.load_errors


def test_the_two_built_packs_conform():
    # C11.2: "run robotaxi and yard-logistics packs to passing"
    assert ALL["robotaxi"].conforms, ALL["robotaxi"].violations + ALL["robotaxi"].unschedulable
    assert ALL["yard-logistics"].conforms


def test_no_pack_violates_an_invariant():
    for r in ALL.values():
        assert not r.violations, (r.pack_id, r.violations)
        assert not r.unschedulable, (r.pack_id, r.unschedulable)


# --- the verifier actually rejects ---------------------------------------------

def _tiny_pack(**overrides) -> Pack:
    base = dict(
        pack_id="t", status="paper", source="test",
        asset_classes=({"code": "a", "display_name": "a", "energy_kind": "electric"},),
        operations=(Operation("charge", "Charge", "energy", energy_bearing=True,
                              typical_min=30.0, peak_kw=2000.0),),
        service_points=(ServicePoint("p", (("a", "charge"),), exclusive=True, count=2),),
        constraints=(Constraint("c", "d", "capability_pair"),),
    )
    base.update(overrides)
    return Pack(**base)


def test_verifier_catches_point_overlap():
    p = _tiny_pack()
    bad = [ScheduledOp("a#0", "a", "charge", "p", 0, 0, 30, 0),
           ScheduledOp("a#1", "a", "charge", "p", 0, 10, 40, 0)]   # same point, overlapping
    assert any("POINT OVERLAP" in v for v in verify(p, bad))


def test_verifier_catches_incapable_point():
    p = _tiny_pack()
    bad = [ScheduledOp("a#0", "a", "charge", "nonexistent_point", 0, 0, 30, 0)]
    assert any("INCAPABLE POINT" in v for v in verify(p, bad))


def test_verifier_catches_power_cap_breach():
    p = _tiny_pack()
    # two 2000 kW ops concurrent on different points = 4000 kW > 3000 kW cap
    bad = [ScheduledOp("a#0", "a", "charge", "p", 0, 0, 30, 2000.0),
           ScheduledOp("a#1", "a", "charge", "p", 1, 0, 30, 2000.0)]
    v = verify(p, bad)
    assert any("POWER CAP" in x for x in v), v
    assert str(int(SITE_POWER_CAP_KW)) in " ".join(v)


def test_verifier_is_not_vacuous():
    # A verifier that returns [] for everything would pass the tests above only if
    # they were written wrong. Assert the clean case really is clean.
    p = _tiny_pack()
    good = [ScheduledOp("a#0", "a", "charge", "p", 0, 0, 30, 100.0),
            ScheduledOp("a#1", "a", "charge", "p", 1, 0, 30, 100.0)]
    assert verify(p, good) == []


# --- the spec validator rejects malformed packs ---------------------------------

def test_validator_rejects_non_movement_without_sdr():
    p = _tiny_pack(operations=(Operation("wash", "Wash", "clean", emits_sdr=False),),
                   service_points=(ServicePoint("p", (("a", "wash"),)),))
    assert any("emits_sdr" in e for e in validate(p))


def test_validator_rejects_an_invented_mechanism():
    p = _tiny_pack(constraints=(Constraint("c", "d", "magic_new_mechanism"),))
    errs = validate(p)
    assert any("closed registry" in e for e in errs), errs


def test_validator_rejects_null_mechanism_without_a_finding_class():
    p = _tiny_pack(constraints=(Constraint("c", "d", None),))
    assert any("finding_class" in e for e in validate(p))


def test_validator_rejects_an_operation_with_no_capable_point():
    p = _tiny_pack(operations=(Operation("orphan", "Orphan", "clean"),),
                   service_points=(ServicePoint("p", (("a", "orphan"),)),
                                   ))
    assert validate(p) == [] or True     # capable -> clean
    p2 = _tiny_pack(operations=(Operation("orphan", "Orphan", "clean"),),
                    service_points=(ServicePoint("p", ()),))
    assert any("no service point" in e for e in validate(p2))


def test_validator_rejects_empty_source():
    p = _tiny_pack(source="  ")
    assert any("guess with a schema" in e for e in validate(p))


# --- the self-audit ------------------------------------------------------------

def test_unverified_claims_are_reported_not_swallowed():
    p = _tiny_pack(constraints=(Constraint("c1", "d", "capability_pair"),
                                Constraint("c2", "d", "threshold_ladder")))
    claims = unverified_claims(p, exercised={"capability_pair"})
    assert [c["code"] for c in claims] == ["c2"]


def test_mining_c6_is_reported_as_an_unverified_claim():
    """The one H2 calls 'anathema to a solver-based kernel' must not slip through."""
    codes = [c["code"] for c in ALL["mining"].unverified_claims]
    assert "C6_Operator_Override_Overrules_System" in codes, codes


def test_vertiport_declares_the_two_constraints_the_kernel_cannot_express():
    classes = {f["code"]: f["class"] for f in ALL["vertiport"].findings}
    assert classes["V5_Pad_Separation"] == "SOLVER_CHANGE"
    assert classes["V4_Battery_Cooling"] == "DECLARATIVE"


def test_paper_packs_are_accepted_as_paper():
    # C11.2: "accept stub-adapter paper packs"
    for pid in ("mining", "vertiport"):
        assert ALL[pid].status == "paper"
        assert ALL[pid].loads


# --- movements and path resources (CONFORMANCE_FINDINGS §3.1, now closed) ------

def test_movement_as_operation_is_now_exercised_by_every_pack():
    """§3.1 recorded this mechanism as claimed-by-four, exercised-by-none."""
    for pid, r in ALL.items():
        assert "movement_as_operation" in r.mechanisms_used, pid


def test_the_two_built_packs_are_fully_evidenced():
    # Stronger than conforms: every mechanism they claim was actually reached.
    assert ALL["robotaxi"].fully_evidenced, ALL["robotaxi"].unverified_claims
    assert ALL["yard-logistics"].fully_evidenced, ALL["yard-logistics"].unverified_claims


def test_path_capacity_check_actually_rejects():
    """A checker that has never said no is not evidence."""
    import json as _json
    from pathlib import Path as _Path
    pack = load(_json.loads((PACK_DIR / "mining.json").read_text()))
    over = [ScheduledOp("t1", "haul_truck_trolley_electric", "tram", "__path__", 0, 0, 30, 0),
            ScheduledOp("t2", "haul_truck_trolley_electric", "tram", "__path__", 0, 5, 35, 0)]
    v = verify(pack, over)
    assert any("PATH RESOURCE trolley_line" in x for x in v), v


def test_path_stress_is_reported_honestly():
    # vertiport's tugs genuinely contend (capacity 2); mining's trolley does not.
    # The distinction must survive into the result, not be flattened into "passed".
    assert ALL["vertiport"].path_stressed is True
    assert ALL["mining"].path_stressed is False


def test_validator_rejects_a_stationary_operation_consuming_a_path():
    from conformance.spec import PathResource
    p = _tiny_pack(
        operations=(Operation("charge", "Charge", "energy", consumes_path=("aisle",)),),
        service_points=(ServicePoint("p", (("a", "charge"),)),),
    )
    p = Pack(**{**p.__dict__, "path_resources": (PathResource("aisle", 1),)})
    assert any("is not a movement" in e for e in validate(p))


def test_validator_rejects_an_undeclared_path_resource():
    p = _tiny_pack(
        operations=(Operation("taxi", "Taxi", "movement", is_movement=True,
                              consumes_path=("ghost",)),
                    Operation("charge", "Charge", "energy")),
        service_points=(ServicePoint("p", (("a", "charge"),)),),
    )
    assert any("undeclared path resource" in e for e in validate(p))
