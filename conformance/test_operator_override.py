"""C11 thread 2 — does the kernel support mining C6, the operator override?

H2 calls C6 "anathema to a solver-based kernel": a human can overrule a scheduled
service event and keep the truck hauling. The mining pack CLAIMS this is covered by
`work_side_refusal` (CLAUDE.md 2.7: work-side refusal is a first-class event
triggering re-solve, never an error). The claim was never exercised.

This file exercises it against the real C9 primitive, and the answer is more
interesting than either prediction.
"""

from __future__ import annotations

import pytest

from recall.recall_decision import (
    AssetState,
    NaiveThresholdRecall,
    RecallEventLog,
    SiteForecast,
    WorkSideSignals,
    run_recall_cycle,
)


def _log() -> RecallEventLog:
    """The real event log — this exercises the production record shape, not a stub."""
    return RecallEventLog(sim_run_id="c11-operator-override")


SITE = SiteForecast(sim_min_now=0.0, eta_min=10.0, free_capable_points=4,
                    inbound_assets=1, congestion_wait_min=5.0)
WORK = WorkSideSignals(mission_active=True, mission_min_remaining=120.0)


def _safety_critical_asset() -> AssetState:
    """Rung 1: a safety-critical fault. urgency=critical, deferrable=False."""
    return AssetState(asset_id="haul-7", soc_pct=80.0, reserve_soc_pct=20.0,
                      deploy_floor_pct=30.0, worst_fault_rank=0, home_site="mine-a")


def test_the_kernel_does_recall_a_safety_critical_asset():
    """Baseline: without an override, the ladder fires and marks it non-deferrable."""
    out = NaiveThresholdRecall().decide(_safety_critical_asset(), WORK, SITE)
    assert out.recall is True
    assert out.urgency == "critical"
    assert out.deferrable is False, "rung 1 must be non-deferrable"


def test_a_work_side_refusal_overrides_even_a_SAFETY_CRITICAL_recall():
    """THE FINDING. C6 is supported — and the kernel cannot express its LIMIT.

    `run_recall_cycle` consults `work_side_accepts` unconditionally. It never reads
    `outcome.deferrable`, so a refusal cancels a recall the ladder marked
    non-deferrable and critical — a safety-critical fault, or a vehicle about to
    strand below reserve.

    So H2's prediction is wrong in the direction it feared (the kernel bends
    readily) and right in a direction it did not name: nothing in the kernel
    distinguishes a refusable recall from an inviolable one, even though CLAUDE.md
    2.5 says Layer 1 exists precisely to hold "inviolable constraints".
    """
    log = _log()
    resolves = []
    outcome = run_recall_cycle(
        NaiveThresholdRecall(), log,
        _safety_critical_asset(), WORK, SITE,
        work_side_accepts=lambda o: False,          # the human says: keep hauling
        resolve=lambda kind, payload: resolves.append((kind, payload)),
    )

    # The override wins, with no guard whatsoever.
    assert outcome.recall is False
    assert outcome.trigger == "work_side_refusal"

    # It IS a first-class event and it DOES trigger re-solve — 2.7 holds.
    kinds = [r["event_type"] for r in log.records]
    assert "recall_refused" in kinds, kinds
    assert "recall_issued" not in kinds, "a refused recall must not also be issued"
    assert resolves and resolves[0][0] == "recall_refused"

    # And the recall it cancelled was marked non-deferrable and critical.
    rec = next(r for r in log.records if r["event_type"] == "recall_refused")
    dec = rec["payload"]["decision"]
    assert dec["urgency"] == "critical", dec
    assert dec["deferrable"] is False, dec


def test_deferrable_is_recorded_but_never_enforced():
    """The flag exists on the outcome and is simply not consulted by the call site."""
    import inspect
    from recall import recall_decision
    src = inspect.getsource(recall_decision.run_recall_cycle)
    assert "work_side_accepts" in src
    assert "deferrable" not in src, (
        "If run_recall_cycle has learned to read `deferrable`, this finding is "
        "stale and CONFORMANCE_FINDINGS must be updated."
    )


def test_a_routine_recall_is_refusable_and_that_is_correct():
    """Not everything here is a defect: refusing a routine recall is the design."""
    routine = AssetState(asset_id="haul-8", soc_pct=80.0, reserve_soc_pct=20.0,
                         deploy_floor_pct=30.0, worst_fault_rank=99,
                         km_since_pm=1e9, home_site="mine-a")
    out = NaiveThresholdRecall().decide(routine, WORK, SITE)
    assert out.recall is True and out.deferrable is True and out.urgency == "routine"


# --- the correction: the kernel DOES model override authority ------------------

def test_the_refusal_callback_carries_no_actor_no_role_no_rule():
    """§1b, corrected. The gap is WIRING, not modelling.

    ottoq_rules already models override authority precisely: 52 rows, each with
    severity, enforcement, override_allowed and override_min_role. 36 are
    non-overridable (10 safety_critical); 5 are overridable behind a named role —
    EN.004.demand_response_compliance needs command_center_operator,
    SLA.006.maintenance_window and SLA.004.required_services_complete need
    depot_supervisor. There is even SM.005.audit_note_required_on_overrides.

    So the kernel CAN express "an operator may override a maintenance window but
    not a sensor-liveness block". What it cannot currently do is APPLY that to a
    recall refusal: `work_side_accepts` is a bare `Callable[[RecallOutcome], bool]`
    — no actor, no role, no rule reference — so the refusal path has nothing to
    check the Layer 1 authority model against.

    This test pins the signature. When the refusal path learns to carry an actor
    or consult a rule, it fails, and the finding is revisited rather than rotting.
    """
    import inspect
    from recall import recall_decision

    sig = inspect.signature(recall_decision.run_recall_cycle)
    accepts = sig.parameters["work_side_accepts"]
    assert "RecallOutcome], bool" in str(accepts.annotation), str(accepts.annotation)

    src = inspect.getsource(recall_decision.run_recall_cycle)
    for authority_concept in ("role", "override_allowed", "rule_code", "actor"):
        assert authority_concept not in src, (
            f"run_recall_cycle now references {authority_concept!r}. The wiring gap "
            f"in CONFORMANCE_FINDINGS §1b may be closed — re-verify and update it."
        )
