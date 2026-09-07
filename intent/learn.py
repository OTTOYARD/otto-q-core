"""The learn loop, first increment — rejection and intractability reconciliation.

THE DOCTRINE (ottoq-intelligence README, the four-layer funnel):
    model proposes -> optimizer disposes -> shield guarantees -> loop learns.

This module is the LEARN step, in the only form that is honest to build against
the current world: reconciliation of the shield's refusals and the solver's
intractability into calibrated signals and constraints that feed the NEXT
propose. It never writes state, never imports a database client, and never
learns from run OUTCOMES — see the contamination guard below.

WHY NOT "BAYESIAN TUNING FROM RUN OUTCOMES" YET (the honest scope line):

FR-5 is documented (ottoq-intelligence/README.md) as "offline RL / Bayesian
tuning from run outcomes." That is the CONTAMINATED half and it is deliberately
NOT built here. The twin REPLAYS OTTO-Q's own decisions (Chase's caveat), so any
run-outcome history — `ottoq_decisions`, `ottoq_vehicle_dispatches`,
`ottoq_service_detail_records`, `ottoq_stall_bookings`, `vehicle_state_log` —
is contaminated by whatever bugs the engine shipped. Tuning parameters against
it would be tuning against our own bugs. That loop belongs in ottoq-intelligence,
against real depot data or a clean-world simulator, not against the twin.

What IS clean is the deterministic boundary: the shield's refusals are the LAW
saying "not allowable because of X" (allowability, not optimality), and the
solver's INFEASIBLE/UNKNOWN are math facts about the DECLARED world. Those are
ground truth. This module turns them into:
  1. a classification of every refusal (transient / live_world / solver_gap),
  2. an anomaly flag when a class is over-represented,
  3. a set of learned constraints that plug straight into the next solve
     (blocked points, frame reconciliation, capacity tightening, …),
  4. a diagnosis of solver intractability with the next action.

THE VOCABULARY IS THE PRODUCTION ONE, not invented. The ten refusal codes are
the exact CHECK constraint in migration 0086 (`ottoq_vehicle_commands`
reason_code), with semantics from 0086's header and db/baseline/functions_ottoq.sql.
The solver statuses are cp_model's own. Every seam is TOTAL: an unknown code
raises rather than silently passing (the AGENTS.md total-function rule).
"""

from __future__ import annotations

from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# The refusal taxonomy — the ten production reason codes, classified
# ---------------------------------------------------------------------------

#: Class of a refusal: what it MEANS for the learn loop.
#:   transient    — expected churn; re-solve already handles it; no signal.
#:   live_world   — the shield saw live state the solver's declared world did
#:                  not carry. Not a solver defect; a data-freshness signal.
#:   solver_gap   — the proposer emitted something the shield says is
#:                  structurally invalid. A genuine calibration defect.
REFUSAL_KINDS = ("transient", "live_world", "solver_gap")


@dataclass(frozen=True)
class RefusalClass:
    kind: str
    learned_constraint: str | None   # the constraint kind to emit when flagged
    rationale: str


#: reason_code -> classification. Grounded in 0086 (the refusal-vocabulary
#: migration) and db/baseline/functions_ottoq.sql (the preflight refusals).
REFUSAL_TAXONOMY: dict[str, RefusalClass] = {
    "target_occupied": RefusalClass(
        "live_world", "refresh_occupancy",
        "0086: stall occupied / reserved / calendar-held. The shield saw live "
        "occupancy the solver's declared world did not carry; a repeat on one "
        "entity is staleness, not a solver defect."),
    "resource_faulted": RefusalClass(
        "live_world", "block_points",
        "0086 + functions_ottoq: stall faulted or charger state unknown. A down "
        "point must be blocked for the next solve, not proposed again."),
    "target_unknown": RefusalClass(
        "solver_gap", "reconcile_frame",
        "0086: vehicle row missing, or stall not found. The proposal named an "
        "entity the world does not have — a frame/scenario vocabulary mismatch."),
    "vehicle_unresponsive": RefusalClass(
        "live_world", "refresh_vehicle_state",
        "functions_ottoq: the vehicle is in a state that cannot receive the "
        "command. Stale telemetry, not a proposal defect."),
    "vehicle_state_incompatible": RefusalClass(
        "live_world", "refresh_vehicle_state",
        "0086: the vehicle's state is incompatible with the command. Fresh "
        "telemetry resolves it."),
    "command_malformed": RefusalClass(
        "solver_gap", "fix_emitter",
        "0086: a required field was absent (or an unclassified refusal). The "
        "proposer emitted a command the shield cannot even evaluate — a "
        "proposal-emitter bug."),
    "no_capacity": RefusalClass(
        "solver_gap", "tighten_capacity",
        "functions_ottoq: escalated, no capacity. The solver over-estimated the "
        "site's ability; its capacity model is looser than the world's."),
    "superseded": RefusalClass(
        "transient", None,
        "0086/0080: a newer command replaced this one. Re-solve already handles "
        "it; not a calibration signal."),
    "run_ended": RefusalClass(
        "transient", None,
        "0086/0087: the command arrived after the run stopped. Expected at run "
        "boundaries; not a calibration signal."),
    "vehicle_declined": RefusalClass(
        "live_world", "vehicle_override",
        "0086: the vehicle itself refused (ack path). A work-side override, not "
        "a solver defect; the constraint is 'the vehicle said no'."),
}

#: The complete production vocabulary, so a test can pin that the taxonomy is
#: TOTAL over it and an unknown code raises.
REFUSAL_CODES = tuple(sorted(REFUSAL_TAXONOMY))


@dataclass(frozen=True)
class Refusal:
    """One shield refusal, in the minimal shape the learn loop needs.

    The production source is ottoq_vehicle_commands.reason_code; this module
    takes records as arguments (never reads the table), so it stays pure.
    """
    reason_code: str
    entity_id: str | None = None
    rule_code: str | None = None


# ---------------------------------------------------------------------------
# Refusal reconciliation
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ReconciliationReport:
    counts: dict[str, int]                        # reason_code -> occurrences
    kinds: dict[str, str]                         # reason_code -> class kind
    #: flagged reasons: (reason_code, count, message). solver_gap flags on any
    #: occurrence; live_world flags on a repeated (reason, entity) pair; transient
    #: never flags.
    flags: tuple[tuple[str, int, str], ...]
    #: learned constraints to feed the next propose: kind -> sorted entities
    #: (or [] when the constraint is site-wide, e.g. tighten_capacity). The keys
    #: are the learned_constraint strings in REFUSAL_TAXONOMY.
    learned_constraints: dict[str, list[str]]
    #: the unresolved anomaly: a reason_code that is NOT in the production
    #: vocabulary. Presence here means the shield emitted a code this taxonomy
    #: has not learned — a vocabulary drift that must be reconciled, never
    #: silently absorbed.
    unknown_codes: tuple[str, ...]

    def is_clean(self) -> bool:
        return not self.flags and not self.unknown_codes


def _normalize(refusals) -> list[tuple[str, str | None]]:
    """Normalize a batch of refusals to (reason_code, entity_id) pairs.

    Accepts Refusal instances or any object carrying `reason_code` (str) and an
    optional `entity_id`. A record with a missing/None reason_code is skipped —
    it is malformed input, not a vocabulary word.
    """
    out: list[tuple[str, str | None]] = []
    for r in refusals:
        if isinstance(r, Refusal):
            rc, eid = r.reason_code, r.entity_id
        else:
            rc = getattr(r, "reason_code", None)
            eid = getattr(r, "entity_id", None)
        if isinstance(rc, str):
            out.append((rc, eid if isinstance(eid, str) else None))
    return out


def reconcile_refusals(refusals, *, entity_repeat_threshold: int = 2,
                       ) -> ReconciliationReport:
    """Classify a batch of refusals and emit the reconciliation report.

    `refusals` is an iterable of Refusal (or any object with `reason_code` and
    optional `entity_id`). Classification is deterministic and TOTAL: an unknown
    reason_code is surfaced in `unknown_codes` rather than raising, so one bad
    record cannot take down the report — but it is named, never absorbed.

    Flagging rules (explicit, not magic):
      * solver_gap  — any occurrence flags (a structural invalidity is always
                      worth surfacing; it should be rare).
      * live_world  — flags when the same (reason_code, entity_id) pair repeats
                      beyond `entity_repeat_threshold` (default 2). A stuck fault
                      or stale occupancy is a pattern; diffuse races are noise.
      * transient   — never flags (superseded / run_ended are expected).
    """
    norm = _normalize(refusals)

    counts: dict[str, int] = {}
    unknown: set[str] = set()
    for rc, _eid in norm:
        if rc in REFUSAL_TAXONOMY:
            counts[rc] = counts.get(rc, 0) + 1
        else:
            unknown.add(rc)

    kinds = {c: REFUSAL_TAXONOMY[c].kind for c in counts}

    # entity-pair repetition, for the live_world flag
    pairs: dict[tuple[str, str], int] = {}
    for rc, eid in norm:
        if rc in REFUSAL_TAXONOMY and eid is not None:
            pairs[(rc, eid)] = pairs.get((rc, eid), 0) + 1

    flags: list[tuple[str, int, str]] = []
    for code, n in sorted(counts.items()):
        cls = REFUSAL_TAXONOMY[code]
        if cls.kind == "solver_gap":
            flags.append((code, n,
                          f"solver_gap '{code}' fired {n}x — a proposal the "
                          f"shield could not even validate; fix the emitter or "
                          f"reconcile the frame ({cls.rationale})"))
        elif cls.kind == "live_world":
            repeats = [eid for (rc, eid), k in pairs.items()
                       if rc == code and k > entity_repeat_threshold]
            if repeats:
                flags.append((code, n,
                              f"live_world '{code}' repeated on "
                              f"{sorted(set(repeats))} beyond threshold "
                              f"{entity_repeat_threshold} — stale telemetry or a "
                              f"stuck resource; refresh before the next solve"))
    flags.sort(key=lambda f: f[0])

    # learned constraints: union over flagged codes' learned_constraint kinds,
    # with the offending entities where the signal carries one.
    learned: dict[str, set[str]] = {}
    for code in counts:
        cls = REFUSAL_TAXONOMY[code]
        lc = cls.learned_constraint
        if lc is None:
            continue
        flagged = (
            cls.kind == "solver_gap"
            or (cls.kind == "live_world"
                and any(rc == code and k > entity_repeat_threshold
                        for (rc, _e), k in pairs.items())))
        if not flagged:
            continue
        learned.setdefault(lc, set())
        for (rc, eid) in pairs:
            if rc == code:
                learned[lc].add(eid)

    learned_constraints = {k: sorted(v) for k, v in sorted(learned.items())}

    return ReconciliationReport(
        counts=counts, kinds=kinds, flags=tuple(flags),
        learned_constraints=learned_constraints,
        unknown_codes=tuple(sorted(unknown)),
    )


# ---------------------------------------------------------------------------
# Solver intractability diagnosis
# ---------------------------------------------------------------------------

#: Solver statuses (cp_model.StatusName) -> classification + next action.
#: These are math facts about the declared world, not decision outcomes, so
#: they are clean ground truth for the learn loop.
SOLVER_DIAGNOSES: dict[str, tuple[str, str]] = {
    "OPTIMAL": ("solved", "proved optimal; nothing to learn"),
    "FEASIBLE": ("solved_bounded",
                 "deterministic-budget-truncated; reproducible but not proven "
                 "optimal — consider raising the budget for a stronger plan"),
    "INFEASIBLE": ("intractable",
                   "no feasible schedule for the declared world: either the site "
                   "is genuinely over-subscribed (enable rejection to serve a "
                   "partial plan and name the unserved) or a declared constraint "
                   "is wrong — inspect the scenario, do not raise an arbitrary cap"),
    "UNKNOWN": ("intractable",
                "search hit its budget/clock without a proof: raise the "
                "deterministic budget, or retain the previous plan (the site is "
                "never without a schedule)"),
    "MODEL_INVALID": ("model_bug",
                      "the model itself is unsatisfiable as built — a code or "
                      "scenario defect, not a capacity question; fix the model"),
}


@dataclass(frozen=True)
class SolverDiagnosis:
    status: str
    kind: str                 # solved | solved_bounded | intractable | model_bug
    next_action: str
    recognized: bool          # False = an unknown status; named, not absorbed


def diagnose_solver(status: str, *, allow_rejection: bool = False,
                    has_previous_plan: bool = False) -> SolverDiagnosis:
    """Classify a solver status and state the next action.

    TOTAL over the known statuses; an unknown status is reported with
    recognized=False and a generic next action rather than raising, because a
    solver-status string is advisory telemetry, not a vocabulary the shield
    enforces. (Contrast with refusal reason_codes, which ARE a constrained
    vocabulary and therefore raise.)
    """
    entry = SOLVER_DIAGNOSES.get(status)
    if entry is None:
        return SolverDiagnosis(
            status=status, kind="unknown",
            next_action=f"unrecognized solver status {status!r} — treat as "
                        "intractable and inspect the solver version/vocabulary",
            recognized=False)
    kind, action = entry
    #: Rejection refines INFEASIBLE: with it on, the rejected list IS the honest
    #: capacity limit; without it, the caller gets nothing to act on.
    if status == "INFEASIBLE" and allow_rejection:
        action = ("rejection enabled — the rejected set names who could not be "
                  "served; that is the site's honest capacity limit, feed it "
                  "back as tightened capacity")
    if status == "UNKNOWN" and has_previous_plan:
        action = ("budget/clock bound hit; the previous plan was retained — "
                  "raise the deterministic budget for a proven plan, but the "
                  "site is never without a schedule")
    return SolverDiagnosis(status=status, kind=kind, next_action=action,
                           recognized=True)
