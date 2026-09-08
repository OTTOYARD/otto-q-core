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
The solver statuses are cp_model's own. Every seam is TOTAL, but TOTAL HERE
MEANS NAMED, NOT RAISED: an unknown reason_code is returned in
ReconciliationReport.unknown_codes and makes the report dirty; an unknown
solver status is returned with recognized=False. Nothing in this module raises
on an unrecognized vocabulary item. That is deliberate -- a refusal batch is
telemetry arriving from a live world, and one unrecognized code must not
discard the ninety-nine recognized ones -- but it is a different contract from
"raises", and a caller who read "raises" here would never check unknown_codes
and would absorb exactly what this module exists to surface.
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


#: WHICH CHANNEL A CODE ACTUALLY ARRIVES ON (finding L-11).
#:
#: This module's Refusal docstring and intent/README.md both name
#: `ottoq_vehicle_commands.reason_code` as THE production source. For one code
#: that is false, and it is the most consequential one in the taxonomy: the
#: engine never writes `no_capacity` into that column. It emits it as an
#: `ottoq_events` payload field on event_type 'ottoq.refusal_escalated'
#: (db/baseline/functions_ottoq.sql:2373-2380), where 77,435 escalations live
#: against 0 in the reason_code column. So `tighten_capacity` -- the branch that
#: tells the loop its capacity model is looser than the world's -- was
#: STRUCTURALLY DEAD against its declared feed, and nothing said so.
#:
#: Annotating the channel does not make the branch live; the offline job that
#: unions the two feeds is the work that would. What it does is stop the
#: taxonomy from reading as though every branch were reachable, which is the
#: same discipline as naming an unknown code instead of absorbing it.
COMMANDS_CHANNEL = "ottoq_vehicle_commands.reason_code"
EVENTS_CHANNEL = "ottoq_events payload (event_type='ottoq.refusal_escalated')"


@dataclass(frozen=True)
class RefusalClass:
    kind: str
    learned_constraint: str | None   # the constraint kind to emit when flagged
    rationale: str
    #: The channel this code is actually written on. A class whose channel is
    #: not COMMANDS_CHANNEL is NOT reachable from the declared batch source.
    channel: str = COMMANDS_CHANNEL


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
        "site's ability; its capacity model is looser than the world's. NOT "
        "REACHABLE from the declared batch source -- see EVENTS_CHANNEL.",
        channel=EVENTS_CHANNEL),
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
#: TOTAL over it. An unknown code is NAMED in unknown_codes, not raised --
#: see the module header.
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
    #: HOW MANY RECORDS COULD NOT BE READ AT ALL (finding L-12). A record whose
    #: reason_code is None or non-string was skipped: not counted, not in
    #: unknown_codes, no trace anywhere. The report for a batch of nothing but
    #: unreadable rows was BYTE-IDENTICAL to the report for an empty batch, and
    #: is_clean() said True. Migration 0086 deliberately left 14 historical
    #: refusals with a NULL reason_code as evidence (refusal_has_code is NOT
    #: VALID), so this is a real shape in the live ledger, not a hypothetical:
    #: the loop's answer was "everything is clean" when the truth was "I could
    #: not read these".
    unreadable: int = 0
    #: reason_code -> the SHIELD RULE CODES that produced it, when the records
    #: carry them (finding L-45). Refusal.rule_code was accepted, carried and
    #: then discarded — _normalize never read it — so the field advertised a
    #: capability the module did not have. It now reaches the report and the
    #: flag messages, which is where an operator asks "which rule refused this".
    rule_codes: dict[str, tuple[str, ...]] = field(default_factory=dict)
    #: per learned-constraint kind, the entities WITH THEIR EVIDENCE AND
    #: LIFETIME (finding L-10). See reconcile_refusals.
    learned_detail: dict[str, list[dict]] = field(default_factory=dict)

    def is_clean(self) -> bool:
        #: An unreadable record is not clean. It is the one state the old
        #: report could not express.
        return not self.flags and not self.unknown_codes and not self.unreadable


def _normalize(refusals) -> tuple[list[tuple[str, str | None, str | None]], int]:
    """Normalize a batch to (reason_code, entity_id, rule_code) triples.

    Returns (triples, unreadable_count). Accepts Refusal instances or any object
    carrying `reason_code` (str) and optional `entity_id` / `rule_code`.

    A record with a missing/None/non-string reason_code is still not classified
    -- it is malformed input, not a vocabulary word -- but it is now COUNTED
    (finding L-12). Skipping it silently made a batch of unreadable rows
    indistinguishable from an empty clean one, which is the difference between
    "nothing is wrong" and "I could not read this".
    """
    out: list[tuple[str, str | None, str | None]] = []
    unreadable = 0
    for r in refusals:
        if isinstance(r, Refusal):
            rc, eid, rule = r.reason_code, r.entity_id, r.rule_code
        else:
            rc = getattr(r, "reason_code", None)
            eid = getattr(r, "entity_id", None)
            rule = getattr(r, "rule_code", None)
        if isinstance(rc, str):
            out.append((rc,
                        eid if isinstance(eid, str) else None,
                        rule if isinstance(rule, str) else None))
        else:
            unreadable += 1
    return out, unreadable


#: A LEARNED BLOCK IS FOR THE NEXT SOLVE, AND MUST BE RE-OBSERVED TO PERSIST
#: (finding L-10). The first version emitted a bare kind -> entity-list map:
#: no bound on how many points block_points could name, no expiry on any
#: entry, no confidence, and no inverse operation anywhere in the repo that
#: ever removes a block. Downstream, model.py raises a hard RuntimeError when a
#: blocked set makes the model infeasible with no previous plan -- so an
#: over-large learned block set takes the site from "degraded schedule" to "no
#: schedule at all", which is the opposite of what learning is for.
#:
#: A lifetime of ONE SOLVE is a design statement, not a guessed magnitude:
#: evidence that is still true will be observed again on the next batch and
#: renew itself, and evidence that has gone stale expires on its own. Nothing
#: has to invent how long a fault lasts.
LEARNED_CONSTRAINT_TTL_SOLVES = 1

#: The share of a kind's capable entities a learned constraint may remove.
#: An INFERENCE and flagged as one, in the house discipline: there is no
#: measured AV-depot figure for "how much of a site may be blocked on
#: evidence". Half is the point at which a block set stops being a correction
#: and starts being an outage, and a caller with a measured number passes its
#: own. It binds only when the caller declares how many capable entities exist
#: -- this module never guesses the denominator.
DEFAULT_MAX_BLOCK_FRACTION = 0.5


def reconcile_refusals(refusals, *, entity_repeat_threshold: int = 2,
                       capable_entities: dict[str, int] | None = None,
                       max_block_fraction: float = DEFAULT_MAX_BLOCK_FRACTION,
                       run_id: str | None = None,
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

    `capable_entities` maps a learned-constraint kind to HOW MANY entities of
    that kind the site has, and is the denominator for the block cap: when a
    kind's learned set would exceed `max_block_fraction` of it, the constraint
    is NOT emitted and a flag says so instead. Learning that would black out
    the site is a finding about the evidence, not a schedule. Left None, no cap
    binds -- this module refuses to guess a site's capacity (finding L-10).

    `run_id` is echoed into every learned entry so a constraint fed forward can
    be traced to the batch that produced it.
    """
    norm, unreadable = _normalize(refusals)

    counts: dict[str, int] = {}
    unknown: set[str] = set()
    rules: dict[str, set[str]] = {}
    for rc, _eid, rule in norm:
        if rule:
            rules.setdefault(rc, set()).add(rule)
    for rc, _eid, _rule in norm:
        if rc in REFUSAL_TAXONOMY:
            counts[rc] = counts.get(rc, 0) + 1
        else:
            unknown.add(rc)

    kinds = {c: REFUSAL_TAXONOMY[c].kind for c in counts}

    # entity-pair repetition, for the live_world flag
    pairs: dict[tuple[str, str], int] = {}
    for rc, eid, _rule in norm:
        if rc in REFUSAL_TAXONOMY and eid is not None:
            pairs[(rc, eid)] = pairs.get((rc, eid), 0) + 1

    flags: list[tuple[str, int, str]] = []
    for code, n in sorted(counts.items()):
        cls = REFUSAL_TAXONOMY[code]
        by = (f" [shield rules: {', '.join(sorted(rules[code]))}]"
              if rules.get(code) else "")
        if cls.kind == "solver_gap":
            flags.append((code, n,
                          f"solver_gap '{code}' fired {n}x{by} — a proposal the "
                          f"shield could not even validate; fix the emitter or "
                          f"reconcile the frame ({cls.rationale})"))
        elif cls.kind == "live_world":
            repeats = [eid for (rc, eid), k in pairs.items()
                       if rc == code and k > entity_repeat_threshold]
            if repeats:
                flags.append((code, n,
                              f"live_world '{code}'{by} repeated on "
                              f"{sorted(set(repeats))} beyond threshold "
                              f"{entity_repeat_threshold} — stale telemetry or a "
                              f"stuck resource; refresh before the next solve"))
    flags.sort(key=lambda f: f[0])

    # learned constraints: union over flagged codes' learned_constraint kinds,
    # with the offending entities where the signal carries one.
    #: kind -> entity -> how many times that entity carried the code.
    learned: dict[str, dict[str, int]] = {}
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
        learned.setdefault(lc, {})
        # Populate from the SAME predicate that flagged the code. A live_world
        # code is flagged because some entity repeated past the threshold; only
        # those entities belong in the constraint. Naming every entity that ever
        # carried the code would let one stuck point remove every healthy point
        # that produced a single one-off refusal of the same kind from the next
        # solve's capacity. A solver_gap code flags on any occurrence, so every
        # entity that carried it is in scope.
        for (rc, eid), k in pairs.items():
            if rc != code:
                continue
            if cls.kind == "solver_gap" or k > entity_repeat_threshold:
                learned[lc][eid] = learned[lc].get(eid, 0) + k
        # The key stays even when the set is empty: a solver_gap refusal that
        # carried no entity_id still means "fix the emitter", and dropping the
        # key would lose that. A flagged live_world code always contributes at
        # least one entity, since that is what flagged it.

    #: THE CAP, AND WHAT HAPPENS WHEN IT BINDS. Refusing to learn is itself a
    #: finding: the flag says the site would have been blacked out, which an
    #: operator can act on, where a silent RuntimeError from the solver three
    #: layers down is not actionable at all.
    capped: set[str] = set()
    if capable_entities:
        for kind, entities in sorted(learned.items()):
            total = capable_entities.get(kind)
            if not total or not entities:
                continue
            allowed = max_block_fraction * total
            if len(entities) > allowed:
                capped.add(kind)
                flags.append((
                    kind, len(entities),
                    f"learned '{kind}' would remove {len(entities)} of {total} "
                    f"capable entities, past the {max_block_fraction:g} cap — "
                    f"NOT learned. A block set this size stops being a "
                    f"correction and becomes an outage; the site would go from "
                    f"a degraded schedule to no schedule at all"))
        flags.sort(key=lambda f: f[0])

    learned_constraints = {k: ([] if k in capped else sorted(v))
                           for k, v in sorted(learned.items())}
    #: EVERY LEARNED ENTRY CARRIES ITS EVIDENCE AND ITS LIFETIME. A bare id
    #: could not say how often it was observed, which batch produced it, or
    #: when it stops applying -- so nothing could ever unlearn it.
    learned_detail = {
        k: [{"entity": e,
             "observed_count": learned[k][e],
             "run_id": run_id,
             "expires_after_n_solves": LEARNED_CONSTRAINT_TTL_SOLVES}
            for e in learned_constraints[k]]
        for k in learned_constraints}

    return ReconciliationReport(
        counts=counts, kinds=kinds, flags=tuple(flags),
        learned_constraints=learned_constraints,
        unknown_codes=tuple(sorted(unknown)),
        unreadable=unreadable,
        rule_codes={k: tuple(sorted(v)) for k, v in sorted(rules.items())},
        learned_detail=learned_detail,
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
    enforces. Refusal reason_codes ARE a constrained vocabulary, and they are
    handled the same way for the same reason: reconcile_refusals returns an
    unrecognized code in unknown_codes and marks the report dirty rather than
    raising, so one unknown code cannot discard a batch of known ones.
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
