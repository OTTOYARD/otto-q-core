"""The CP-SAT proposer's database client -- frame in, door calls out.

WHAT THIS IS. BUILD_QUEUE #4 (2026-09-12): "the one component that optimises a
declared objective cannot reach the component that decides." proposer/ is pure by
law -- the separation guard proves it cannot import a database client -- so the
insert its README calls "founder-gated" had no home. This is the home. It does
exactly three things and nothing else:

  1. READ the decision frame (`ottoq_build_decision_frame(depot, run)`) and the
     class table (`proposer.class_table.SELECT_VEHICLE_CLASSES`);
  2. CALL `proposer.forward_proposer.propose()` -- the lexicographic CP-SAT
     solve, deterministic-time bounded, batch-sized for the tick;
  3. SUBMIT every row through `public.ottoq_submit_external_proposal`, the SAME
     door cuOpt's edge function and an operator use, so the server assigns the
     identity (0198), Posture A can refuse it from a certification arm (0241),
     and the decide path DISPOSES exactly as it does for every other proposer.

WHAT IT NEVER DOES. It never INSERTs into ottoq_external_proposals (grep this
file: the word appears only in prose), never writes a booking, never touches a
vehicle. `emit_sql` produces `SELECT public.ottoq_submit_external_proposal(...)`
statements and nothing else, so the offline artifact is auditable as "here is
exactly what the proposer asked the engine to consider" -- and the shield still
decides every row.

THE FIRE RECORD is the cuopt_invocation_log discipline for this proposer: every
call is quantifiable, "never invoked" distinguishable from "invoked and abstained"
from "invoked and proposed N". It carries the frame hash (which world the solver
saw), the solver's own accounting (statuses, optima, reproducible flag), and the
counts. Migration 0260 gives it a ledger (`ottoq_proposer_fire_log`) and a
one-call submit (`ottoq_proposer_submit_batch`); until that is applied,
`--via door` submits row by row and the fire record is the bridge's stdout.

WHY THE LIVE MODE IMPORTS psycopg LAZILY. CI runs `python3 -m pytest -q` with no
database and no psycopg on purpose (.github/workflows/verify.yml: "no secrets, no
database"). The pure half of this module -- fire(), emit_sql() -- is what the tests
exercise; the live half is reached only by `--dsn`, and a missing driver is a
named error, not an import-time crash that would take the tests with it.

SOURCE NAME. `forward_lex`, because that is what proposer/forward_proposer.py
already stamps on every row it builds (proposal.rationale.optimizer and the row's
`source`). The precedence row for it lives in migration 0259; without 0259 a
forward_lex row is heard but LOSES the tie-break to the local path's regenerated
row by created_at (proposer/README.md, finding L-40) -- db/checks/0184 measures
exactly that.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
for _p in (ROOT, ROOT / "proposer", ROOT / "solvers" / "cpsat", ROOT / "policies"):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

from proposer.class_table import SELECT_VEHICLE_CLASSES, class_table_from_rows  # noqa: E402
from proposer.forward_proposer import (  # noqa: E402
    DEFAULT_DET_BUDGET_S,
    DEFAULT_SERVICEABLE_STATES,
    FrameError,
    NON_CHARGING_TYPES,
    frame_facts_version,
    propose,
    serviceable_predicate,
    stall_block_reason,
    vehicle_is_held,
)

SOURCE = "forward_lex"
ACTION_CONTEXT = "stall_assignment"
ENTITY_TYPE = "vehicle"
DOOR = "public.ottoq_submit_external_proposal"
BATCH = "public.ottoq_proposer_submit_batch"
#: 0278's one-call arming ritual. It sets proposer_frame_facts,
#: proposer_hold_enabled and cuopt_first_refusal_max_defers at RUN scope,
#: all-or-nothing, reads every ottoq_policy_set receipt rather than assuming it,
#: and refuses a run whose run_by is cert_harness with ERRCODE 42501 -- arming a
#: certification arm would change the frame its canon was measured against.
ARM = "public.ottoq_agentic_arm"
#: Who the arming is attributed to in ottoq_policy_params.updated_by.
ARMED_BY = "proposer_bridge"
FRAME_FN = "public.ottoq_build_decision_frame"
DEFAULT_TTL_S = 60

#: The dollar-quote tag used for every jsonb literal the emitter writes. A
#: payload that CONTAINS the tag would terminate the literal early, so the
#: emitter refuses such a payload rather than producing SQL that parses as
#: something else. Checked on every literal, not assumed.
DOLLAR_TAG = "$ottoq_bridge$"

_UUID = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
                   r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
_IDENT = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


class BridgeError(ValueError):
    """An input the bridge refuses to guess around."""


class BridgeIdle(BridgeError):
    """The depot has nothing to propose into -- a state, not a mistake.

    A scheduled poller finds an idle depot most of the time, and a red job every
    five minutes teaches the reader to ignore red jobs. `--idle-ok` turns only
    THIS case into exit 0; an ambiguous depot (two running runs) or a
    certification arm is still a refusal, because those need a human decision.
    """


# ---------------------------------------------------------------------------
# Pure half: fire() and the SQL emitter
# ---------------------------------------------------------------------------


def _canonical(obj: Any) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True, default=str)


def content_hash(obj: Any) -> str:
    """sha256 over canonical JSON. Key order and whitespace do not move it."""
    return "sha256:" + hashlib.sha256(_canonical(obj).encode("ascii")).hexdigest()


def _require_uuid(value: Any, what: str) -> str:
    if not isinstance(value, str) or not _UUID.match(value):
        raise BridgeError(f"{what} must be a uuid, got {value!r}")
    return value.lower()


def _require_ident(value: Any, what: str) -> str:
    if not isinstance(value, str) or not _IDENT.match(value):
        raise BridgeError(f"{what} must match {_IDENT.pattern}, got {value!r}")
    return value


#: One tick of the certification clock (30 sim-minutes); a charge the plan
#: starts later than this is not this tick's assignment (see only_due_now).
DEFAULT_START_WITHIN_MIN = 30
#: The kernel's own default deadline when the frame carries none; recorded on
#: every row as ready_by_source=default. A demo that knows its turnaround
#: passes its own value; a value nobody declared is an ASSUMPTION, so it is a
#: parameter and on the fire record, never a constant hidden in the plan.
DEFAULT_READY_DELTA_MIN = 240


def fire(frame: dict, class_rows: list[dict], *, site: dict,
         sim_run_id: str, depot_id: str,
         hour_of_day: int | None = None,
         max_assets: int | None = None,
         det_budget_s: float = DEFAULT_DET_BUDGET_S,
         ready_by_min: dict[str, int] | None = None,
         default_ready_delta_min: int = DEFAULT_READY_DELTA_MIN,
         start_within_min: int = DEFAULT_START_WITHIN_MIN,
         allow_rejection: bool = False,
         fired_at: str | None = None,
         serviceable_states: frozenset[str] | None = None) -> dict:
    """One proposer invocation over one frame. Pure: writes nothing.

    Returns {"rows": [...door-shaped rows...], "fire": {...the fire record...}}.
    A frame with nothing plannable is a fire with status 'empty' and zero rows,
    never an exception -- "invoked and had nothing to say" is a ledger fact.
    """
    sim_run_id = _require_uuid(sim_run_id, "sim_run_id")
    depot_id = _require_uuid(depot_id, "depot_id")
    if not isinstance(site, dict) or "dcfc_cooldown_min" not in site:
        raise BridgeError("site must be a dict declaring dcfc_cooldown_min "
                          "(see bridge/sites/*.json)")

    class_table = class_table_from_rows(class_rows)
    vehicles = frame.get("vehicles") or []
    n_vehicles = len(vehicles)
    #: L-60: the states this fire plans for. A narrowing only (the proposer
    #: refuses anything outside its default set); on the record so "planned for
    #: the held arrivals only" is a ledger fact and not a memory.
    states = (frozenset(serviceable_states) if serviceable_states is not None
              else DEFAULT_SERVICEABLE_STATES)
    n_in_serviceable_state = sum(1 for v in vehicles if v.get("state") in states)
    #: L-60 (migration 0265): of those, how many already hold a reservation or a
    #: booking and were therefore not planned for. The decide path does not
    #: re-decide a vehicle that holds a place, so a proposal for one sits
    #: `pending` until its TTL and never reaches the shield. On a frame without
    #: the 0265 facts this is 0 for every vehicle -- which is why
    #: `frame_facts_version` travels beside it: 0 held under version 1 is a
    #: measurement, 0 held under no version is a blindness.
    #:
    #: Measured with the proposer's OWN predicate, imported rather than
    #: re-expressed here: a second nearly-identical test is how a published
    #: count drifts from the population it claims to describe. So this is the
    #: set that WOULD have been planned for and was not, which is narrower than
    #: `n_in_serviceable_state` (that one is state alone, and a vehicle already
    #: at its target SoC is in it).
    _plannable = serviceable_predicate(states)
    n_vehicles_held = sum(1 for v in vehicles
                          if _plannable(v) and vehicle_is_held(v))
    #: L-58/L-61: the charge-capable stalls, and why each one that is not a
    #: point this tick is not. `n_stalls_busy` stays the single total it always
    #: was; `stalls_blocked` is the breakdown 0186 had to be hand-queried for.
    charge_stalls = [s for s in (frame.get("stalls") or [])
                     if s.get("type") not in NON_CHARGING_TYPES
                     and float(s.get("connector_max_kw") or 0) > 0]
    stalls_blocked: dict[str, int] = {}
    for stall in charge_stalls:
        reason = stall_block_reason(stall)
        if reason is not None:
            stalls_blocked[reason] = stalls_blocked.get(reason, 0) + 1

    record: dict[str, Any] = {
        "source": SOURCE,
        "action_context": ACTION_CONTEXT,
        "sim_run_id": sim_run_id,
        "depot_id": depot_id,
        "fired_at": fired_at or datetime.now(timezone.utc).isoformat(),
        "frame_hash": content_hash(frame),
        "site_hash": content_hash(site),
        "class_table_hash": content_hash(class_table),
        "n_vehicles": n_vehicles,
        "n_in_serviceable_state": n_in_serviceable_state,
        "serviceable_states": sorted(states),
        "n_stalls": len(frame.get("stalls") or []),
        #: L-58: of the CHARGE-CAPABLE stalls, how many were not points this
        #: tick and were therefore never offered to the solver. Recorded on
        #: every path, the empty one included, so "planned on 17 of 40" and
        #: "nothing free" are both ledger facts and not inferences.
        #:
        #: CORRECTED 2026-09-13 WITH 0265's CONSUMER, and the correction is the
        #: point: this used to count over EVERY stall in the frame. That agreed
        #: with the proposer's own `stalls_busy` only by luck -- a staging stall
        #: is `available` with no vehicle, so it read free and fell out of both
        #: counts. Under 0265 it does not: 0265 emits the facts for every stall
        #: at the depot and a staging stall has no ocpp_charger_id, so it is
        #: correctly not offerable and would have joined this count. At the
        #: flagship depot that is 232 of 330 stalls, and turning the gate on
        #: would have moved a published number from a handful to ~260 with
        #: nothing whatever changing in the world. A count whose value depends
        #: on which frame contract produced it is not a measurement.
        "n_stalls_busy": sum(stalls_blocked.values()),
        "n_charge_stalls": len(charge_stalls),
        "stalls_blocked": stalls_blocked,
        "n_vehicles_held": n_vehicles_held,
        #: WHICH FRAME CONTRACT THE THREE COUNTS ABOVE WERE MEASURED UNDER.
        #: Feature-detected off the frame's own `selector` block (0265), never
        #: assumed and never configured: a bridge that claimed version 1 while
        #: reading a gate-off frame would publish a blindness as a measurement.
        "frame_facts_version": frame_facts_version(frame),
        "hour_of_day": hour_of_day,
        "max_assets": max_assets,
        "det_budget_s": det_budget_s,
        "allow_rejection": allow_rejection,
    }

    try:
        result = propose(frame, class_table, site=site,
                         hour_of_day=hour_of_day, max_assets=max_assets,
                         det_budget_s=det_budget_s, ready_by_min=ready_by_min,
                         default_ready_delta_min=default_ready_delta_min,
                         allow_rejection=allow_rejection,
                         serviceable_states=states)
    except FrameError as exc:
        #: e.g. "frame has no charge-capable stalls that declare an accepted
        #: inlet". Nothing to propose ON, which is a fact about the frame and is
        #: recorded as one; it must not take a loop down.
        record.update(status="empty", n_rows=0, n_planned=0, n_abstained=0,
                      n_deferred=0, solver=None, error=str(exc))
        return {"rows": [], "fire": record}
    except RuntimeError as exc:
        #: L-62: the kernel raises RuntimeError when the model is INFEASIBLE and
        #: there is no previous plan to retain -- measured on run ccf48af1 at
        #: tick 3: 13 waiting vehicles, ONE free stall, a 720-minute horizon.
        #: That is a fact about the site, not a fault in the loop: with
        #: allow_rejection off the solver may decline the whole frame, and the
        #: fire record says so. "Invoked, could not serve the frame" is a ledger
        #: fact exactly like an abstention; a traceback is not.
        record.update(status="empty", n_rows=0, n_planned=0, n_abstained=0,
                      n_deferred=0, solver=None,
                      error=f"solver declined the frame: {exc}")
        return {"rows": [], "fire": record}

    rows = list(result.get("proposals") or [])
    for row in rows:
        if row.get("source") != SOURCE:
            raise BridgeError(f"proposer stamped source {row.get('source')!r}; "
                              f"this bridge submits only {SOURCE!r}")
        if row.get("action_context") != ACTION_CONTEXT:
            raise BridgeError(f"unexpected action_context {row.get('action_context')!r}")

    rows, not_due = only_due_now(rows, start_within_min=start_within_min)

    record.update(
        #: the same vocabulary as the ledger (0260): 'submitted' whenever a row
        #: reaches the door, abstains included, 'empty' only when none does. An
        #: all-abstain fire is told apart by n_planned == 0, not by its status.
        status="proposed" if rows else "empty",
        n_rows=len(rows),
        n_planned=int(result.get("planned") or 0) - len(not_due),
        n_abstained=int(result.get("abstained") or 0) + len(not_due),
        n_deferred=int(result.get("deferred") or 0),
        n_not_due=len(not_due),
        start_within_min=start_within_min,
        default_ready_delta_min=default_ready_delta_min,
        solver=result.get("solver"),
        note=result.get("note"),
    )
    return {"rows": rows, "fire": record}


def only_due_now(rows: list[dict], *, start_within_min: int) -> tuple[list[dict], list[str]]:
    """THE PLAN IS A SCHEDULE; THE DOOR TAKES THIS TICK'S ASSIGNMENTS.

    Found on the first dry run against real depot data (2026-09-12 20:58 UTC):
    with six vehicles at the gate the solver returned an OPTIMAL plan that put
    two of them on the same L2 stall -- one starting now, the other at +174
    min, after the first finishes. Both rows would have reached the door in the
    same tick, the tick would have enacted the first and the shield would have
    refused the second for a stall already taken: a refusal manufactured by
    flattening time, not a safety finding, and it would have been counted as one.

    So a charge whose planned start lies beyond this tick's window becomes an
    ABSTAIN row carrying its planned start -- "invoked, not yet due" is a ledger
    fact -- and is re-offered by the next fire, whose plan will have moved it
    forward. Rows whose planned start is within the window pass unchanged. An
    abstain row from the proposer passes unchanged too.
    """
    kept: list[dict] = []
    deferred: list[str] = []
    for row in rows:
        p = row["proposal"]
        start = (p.get("rationale") or {}).get("planned_start_min")
        if p.get("abstain") or start is None or int(start) <= int(start_within_min):
            kept.append(row)
            continue
        deferred.append(row["entity_id"])
        kept.append({
            **row,
            "proposal": {
                "verb": "assign_stall", "abstain": True, "vehicle_id": p.get("vehicle_id", row["entity_id"]),
                "rationale": {
                    "optimizer": p["rationale"].get("optimizer", SOURCE),
                    "reason": f"planned to start at +{int(start)} min on {p.get('stall_type')} "
                              f"{p.get('stall_id')}, beyond this tick's {int(start_within_min)}-min "
                              f"window; re-offered when due",
                    "planned_start_min": int(start),
                    "planned_end_min": p["rationale"].get("planned_end_min"),
                    "planned_stall_id": p.get("stall_id"),
                    "ready_by_source": p["rationale"].get("ready_by_source"),
                    "abstained_by": "bridge:not_due",
                },
                "resolved_action_context": ACTION_CONTEXT,
            },
        })
    return kept, deferred


def _jsonb_literal(obj: Any) -> str:
    text = _canonical(obj)
    if DOLLAR_TAG in text:
        raise BridgeError(f"payload contains the dollar-quote tag {DOLLAR_TAG}; "
                          f"refusing to emit SQL that would parse differently")
    return f"{DOLLAR_TAG}{text}{DOLLAR_TAG}::jsonb"


def door_call_sql(row: dict, *, sim_run_id: str, depot_id: str,
                  ttl_seconds: int = DEFAULT_TTL_S) -> str:
    """One `SELECT public.ottoq_submit_external_proposal(...)` for one row."""
    run = _require_uuid(sim_run_id, "sim_run_id")
    depot = _require_uuid(depot_id, "depot_id")
    ctx = _require_ident(row.get("action_context"), "action_context")
    etype = _require_ident(row.get("entity_type"), "entity_type")
    entity = _require_uuid(row.get("entity_id"), "entity_id")
    source = _require_ident(row.get("source"), "source")
    if not isinstance(ttl_seconds, int) or ttl_seconds < 1:
        raise BridgeError(f"ttl_seconds must be a positive int, got {ttl_seconds!r}")
    return (f"SELECT {DOOR}('{run}'::uuid, '{depot}'::uuid, '{ctx}', '{etype}', "
            f"'{entity}'::uuid, {_jsonb_literal(row['proposal'])}, "
            f"'{source}', {ttl_seconds});")


def batch_call_sql(rows: list[dict], fire_record: dict, *, sim_run_id: str,
                   depot_id: str, ttl_seconds: int = DEFAULT_TTL_S) -> str:
    """One `SELECT public.ottoq_proposer_submit_batch(...)` (migration 0260):
    every row through the door inside one function, plus one fire-log row."""
    run = _require_uuid(sim_run_id, "sim_run_id")
    depot = _require_uuid(depot_id, "depot_id")
    for row in rows:
        _require_uuid(row.get("entity_id"), "entity_id")
        _require_ident(row.get("action_context"), "action_context")
        _require_ident(row.get("entity_type"), "entity_type")
        _require_ident(row.get("source"), "source")
    if not isinstance(ttl_seconds, int) or ttl_seconds < 1:
        raise BridgeError(f"ttl_seconds must be a positive int, got {ttl_seconds!r}")
    payload = [{"action_context": r["action_context"], "entity_type": r["entity_type"],
                "entity_id": r["entity_id"].lower(), "proposal": r["proposal"]}
               for r in rows]
    #: One batch, one source: the door stamps p_source on every row, so a mixed
    #: batch would misattribute. The record names the source for an empty batch.
    sources = {r["source"] for r in rows} or {fire_record.get("source", SOURCE)}
    if len(sources) != 1:
        raise BridgeError(f"a batch must carry one source, got {sorted(sources)}")
    source = _require_ident(next(iter(sources)), "source")
    return (f"SELECT {BATCH}('{run}'::uuid, '{depot}'::uuid, '{source}', "
            f"{_jsonb_literal(payload)}, {_jsonb_literal(fire_record)}, "
            f"{ttl_seconds});")


def emit_sql(result: dict, *, sim_run_id: str, depot_id: str,
             ttl_seconds: int = DEFAULT_TTL_S, via: str = "door") -> str:
    """The offline artifact: door calls only, the fire record as a comment.

    via='door'  -- one door call per row (works against today's schema).
    via='batch' -- one ottoq_proposer_submit_batch call (needs migration 0260),
                   which also ledgers an EMPTY fire; the door route cannot.
    """
    if via not in ("door", "batch"):
        raise BridgeError(f"via must be 'door' or 'batch', got {via!r}")
    rows, record = result["rows"], result["fire"]
    lines = [
        f"-- bridge/proposer_bridge.py fire record ({record['status']}, "
        f"{record['n_rows']} row(s)); the shield disposes every row below.",
        f"-- fire: {_canonical(record)}",
    ]
    if via == "batch":
        lines.append(batch_call_sql(rows, record, sim_run_id=sim_run_id,
                                    depot_id=depot_id, ttl_seconds=ttl_seconds))
    elif rows:
        lines.extend(door_call_sql(r, sim_run_id=sim_run_id, depot_id=depot_id,
                                   ttl_seconds=ttl_seconds) for r in rows)
    else:
        lines.append("-- no rows: nothing submitted. NOTE this empty fire is NOT "
                     "ledgered on the door route; use via='batch' (0260) for that.")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Live half: psycopg, imported only here
# ---------------------------------------------------------------------------


def _import_psycopg():
    try:
        import psycopg  # type: ignore
    except ImportError as exc:  # pragma: no cover - exercised via monkeypatch
        raise BridgeError("live mode needs psycopg (pip install 'psycopg[binary]'); "
                          "the offline route (--frame/--classes/--emit-sql) does not") from exc
    return psycopg


def _run_row(cur, sim_run_id: str) -> dict:
    cur.execute(
        "SELECT r.status, r.depot_id::text, r.run_by, r.tick_count, "
        "       r.sim_clock_current, "
        "       EXTRACT(HOUR FROM (r.sim_clock_current AT TIME ZONE "
        "                          COALESCE(d.timezone, 'UTC')))::int AS sim_hour "
        "  FROM public.ottoq_sim_runs r LEFT JOIN public.depots d ON d.id = r.depot_id "
        " WHERE r.sim_run_id = %s::uuid", (sim_run_id,))
    row = cur.fetchone()
    if row is None:
        raise BridgeError(f"run {sim_run_id} does not exist")
    keys = ("status", "depot_id", "run_by", "tick_count", "sim_clock_current", "sim_hour")
    return dict(zip(keys, row))


def _fetch_frame(cur, depot_id: str, sim_run_id: str) -> dict:
    cur.execute(f"SELECT {FRAME_FN}(%s::uuid, %s::uuid)", (depot_id, sim_run_id))
    frame = cur.fetchone()[0]
    if isinstance(frame, str):
        frame = json.loads(frame)
    return frame


def _fetch_class_rows(cur) -> list[dict]:
    cur.execute(SELECT_VEHICLE_CLASSES)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


CERT_RUN_BY = "cert_harness"
# The two rigs that must never share a depot with a live proposer loop. A pair
# runs both of its arms inside ONE transaction, so its ottoq_sim_runs rows are
# invisible to this session until it commits -- which is exactly why the house
# rule says pg_stat_activity is the only authority for "in flight" and why this
# guard asks the process list, not the run table.
CERT_CALLS = ("%ottoq_determinism_pair%", "%ottoq_ab_pair%")


def _cert_in_flight(cur) -> str | None:
    """Name the certification rig holding the database, or None if clear."""
    cur.execute(
        "SELECT count(*) FROM pg_stat_activity "
        " WHERE pid <> pg_backend_pid() AND state <> 'idle' "
        "   AND (query ILIKE %s OR query ILIKE %s)", CERT_CALLS)
    n = cur.fetchone()[0]
    if n:
        return (f"{n} certification call(s) in flight (ottoq_determinism_pair / "
                f"ottoq_ab_pair); a proposer must not submit into a certification arm")
    return None


def _resolve_run(cur, depot_id: str) -> str:
    """The depot's one live run id, or a refusal that says which case it hit.

    `--run auto` exists because a scheduled loop cannot know the run id in
    advance: the operator starts a run, the loop finds it. It refuses rather than
    guesses in all three ambiguous cases -- no live run, more than one, or a
    certification arm holding the depot.
    """
    cur.execute(
        "SELECT r.sim_run_id::text, r.run_by, r.status "
        "  FROM public.ottoq_sim_runs r "
        " WHERE r.depot_id = %s::uuid AND r.status IN ('running', 'paused') "
        " ORDER BY r.started_at DESC", (depot_id,))
    rows = [dict(zip(("sim_run_id", "run_by", "status"), r)) for r in cur.fetchall()]
    live = [r for r in rows if r["status"] == "running"]
    if not live:
        if rows:
            held = ", ".join(f"{r['sim_run_id']} ({r['status']})" for r in rows)
            raise BridgeIdle(f"depot {depot_id} has no running run; found {held}. "
                             f"A paused run is ticked by hand, so the loop does not fire on it")
        raise BridgeIdle(f"depot {depot_id} has no running or paused run to propose into")
    if len(live) > 1:
        named = ", ".join(r["sim_run_id"] for r in live)
        raise BridgeError(f"depot {depot_id} has {len(live)} running runs ({named}); "
                          f"pass --run explicitly rather than letting the bridge guess")
    run = live[0]
    if run["run_by"] == CERT_RUN_BY:
        raise BridgeError(f"run {run['sim_run_id']} on depot {depot_id} is a certification "
                          f"arm (run_by={CERT_RUN_BY}); the proposer never submits into one")
    return run["sim_run_id"]


class BlindFrameError(BridgeError):
    """The frame the solver was handed does not carry the selector's facts."""


def _arm_run(cur, sim_run_id: str, by: str) -> dict:
    """Arm the run for agentic proposal, and return 0278's arming verdict.

    WHY THE LOOP ARMS RATHER THAN THE OPERATOR. 0278 built the ritual; nothing
    performed it. Measured 2026-09-14 (db/checks/0214): of the seven runs that
    have ever carried a proposer_frame_facts row, exactly ONE did -- a probe run
    created to measure the blindness. All six `proposer_live` runs, and all 329
    CP-SAT proposals they produced, were solved against a frame with the gate
    off. A ritual that must be remembered before every run is a ritual that will
    not be performed, so the process that needs it performs it.

    Raises rather than warns. A proposer that plans against a blind frame does
    not fail -- it succeeds at the wrong problem, offering points the door had
    already given away, which is worse than not proposing at all.
    """
    cur.execute(f"SELECT {ARM}(%s::uuid, %s)", (sim_run_id, ARMED_BY))
    row = cur.fetchone()
    receipt = row[0] if row else None
    if not isinstance(receipt, dict) or not receipt.get("ok"):
        raise BridgeError(f"{ARM} did not confirm the arming of run {sim_run_id}: {receipt}")
    verdict = (receipt.get("arming") or {}).get("verdict")
    if verdict != "armed":
        raise BridgeError(f"run {sim_run_id} reports arming verdict {verdict!r} after "
                          f"{ARM} returned ok; missing "
                          f"{(receipt.get('arming') or {}).get('missing')}")
    return receipt["arming"]


def _require_seeing_frame(frame: dict, sim_run_id: str) -> int:
    """Refuse a frame that does not carry the selector facts (0265).

    This does NOT trust the arming above -- it reads the frame that actually
    came back. The two are deliberately independent: arming is what we asked
    for, `selector.facts_version` is what we got, and the gap between those is
    the entire finding of db/checks/0214.

    What is at stake, measured on the flagship depot at tick 4: the blind frame
    offered 25 charge points to the solver and the facts frame offered 0 -- 24
    reserved by the door, 1 charger faulted. The solver was not choosing badly
    among scarce points; it was choosing among points that were already gone.
    """
    version = frame_facts_version(frame)
    if version is None:
        raise BlindFrameError(
            f"the decision frame for run {sim_run_id} carries no selector.facts_version, "
            f"so `offerable`, `reserved_by` and `charger_state` are absent and a reserved "
            f"but empty stall reads as free. Either proposer_frame_facts is off for this "
            f"run or the database predates 0265. Pass --allow-blind-frame only to MEASURE "
            f"the blind behaviour; never to propose into a live depot with it.")
    return version


#: THE SEAT AND THE FIRE MUST BE THE SAME EVENT (G58, db/checks/0223).
#:
#: ottoq_cuopt_defer_roll binds a first-refusal seat at EXACTLY ONE TICK -- step
#: 2 moves armed -> spent at the current tick, step 1 clears anything spent
#: before it. That one-tick bound is the starvation guarantee and must not be
#: widened. So the only way a seat can be answered is for the proposer to fire
#: inside that tick, and until now this loop slept a fixed wall-clock interval
#: against a twin advancing on its own metronome. Nothing aligned them.
#:
#: Measured on run 36e5cc68 with an 18-second interval, the separation was
#: total: every seat armed at a tick the loop happened to fire on was answered
#: (15 of 15, including one where a single charge stall was free), and every
#: seat armed at a tick it did not fire on went unanswered (12 of 12). Across
#: two runs the twenty unanswered seats split 7 saturation / 13 cadence.
#:
#: So the loop waits for the TICK, not for the clock. It polls tick_count and
#: fires when it moves. The poll is cheap (one indexed row) and the wait is
#: bounded: if the tick does not move within `tick_wait_s` the loop fires
#: anyway, because a proposer that silently naps through its whole window looks
#: identical to one that worked -- the same rule `max_consecutive_skips`
#: already enforces for the certification guard.
#:
#: WHY THE REASON TRAVELS ON THE NEXT FIRE. 0223 had to RECONSTRUCT this
#: alignment by joining the fire log to the deferral ledger on tick number. It
#: should not have had to: the fire record now carries what woke it and how many
#: ticks passed, so the question is a column rather than a join.
TICK_POLL_S = 1.0
DEFAULT_TICK_WAIT_S = 90.0


def _wait_for_next_tick(conn, sim_run_id: str, *, after_tick: int | None,
                        max_wait_s: float, poll_s: float = TICK_POLL_S) -> str:
    """Block until this run's tick_count passes `after_tick`.

    Returns why the wait ended -- 'tick_change', 'timeout', 'run_ended' or
    'run_gone' -- and never raises: a poll that cannot answer is a reason to
    fire, not a reason to stop.
    """
    deadline = time.monotonic() + max_wait_s
    while True:
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT tick_count, status FROM public.ottoq_sim_runs "
                            "WHERE sim_run_id = %s::uuid", (sim_run_id,))
                row = cur.fetchone()
            conn.rollback()
        except Exception:
            conn.rollback()
            return "poll_failed"
        if row is None:
            return "run_gone"
        tick, status = row[0], row[1]
        if status != "running":
            return "run_ended"
        if after_tick is None or (tick is not None and tick > after_tick):
            return "tick_change"
        if time.monotonic() >= deadline:
            return "timeout"
        time.sleep(poll_s)


def run_live(dsn: str, *, sim_run_id: str, depot_id: str, site: dict,
             ttl_seconds: int = DEFAULT_TTL_S, max_assets: int | None = None,
             det_budget_s: float = DEFAULT_DET_BUDGET_S, via: str = "door",
             regime: bool = False, loop: bool = False, interval_s: float = 10.0,
             max_fires: int | None = None, log=print,
             default_ready_delta_min: int = DEFAULT_READY_DELTA_MIN,
             start_within_min: int = DEFAULT_START_WITHIN_MIN,
             serviceable_states: frozenset[str] | None = None,
             allow_rejection: bool = False,
             arm: bool = True,
             allow_blind_frame: bool = False,
             follow_ticks: bool = True,
             tick_wait_s: float = DEFAULT_TICK_WAIT_S,
             max_consecutive_skips: int = 30) -> list[dict]:
    """Fetch → propose → submit, once or in a loop while the run is running.

    Every fire is committed in its own transaction so the door's tick_seq stamp
    (0236) names the tick the batch actually landed in. Returns the receipts.
    """
    psycopg = _import_psycopg()
    auto_run = str(sim_run_id).strip().lower() == "auto"
    if not auto_run:
        sim_run_id = _require_uuid(sim_run_id, "sim_run_id")
    depot_id = _require_uuid(depot_id, "depot_id")
    receipts: list[dict] = []
    #: Arm ONCE per resolved run, not once per fire. `--run auto` can hand the
    #: loop a different run mid-window (an operator restarts one), so the trigger
    #: is a CHANGE of run id rather than a flag set on the first pass.
    armed_run: str | None = None
    arming: dict | None = None
    #: What woke this fire, and how far the world moved since the last one.
    #: 'first' until something has woken it; see _wait_for_next_tick.
    trigger: str = "first"
    last_fired_tick: int | None = None
    with psycopg.connect(dsn) as conn:
        n = 0
        skips = 0
        while True:
            with conn.cursor() as cur:
                held = _cert_in_flight(cur)
            if held is not None:
                # A certification or A/B pair owns the database. Refuse outright
                # when fired once; when looping, wait it out -- but not forever,
                # because a scheduled loop that silently naps through its whole
                # window looks identical to one that worked.
                if not loop:
                    raise BridgeError(held)
                skips += 1
                log(_canonical({"skipped": held, "consecutive_skips": skips}))
                if skips >= max_consecutive_skips:
                    raise BridgeError(f"{held}; skipped {skips} times in a row, giving up")
                conn.rollback()
                time.sleep(interval_s)
                continue
            skips = 0
            with conn.cursor() as cur:
                if auto_run:
                    sim_run_id = _resolve_run(cur, depot_id)
                n += 1
                run = _run_row(cur, sim_run_id)
                if run["depot_id"].lower() != depot_id:
                    raise BridgeError(f"run {sim_run_id} is on depot {run['depot_id']}, "
                                      f"not {depot_id}")
                if run["status"] != "running":
                    log(f"run {sim_run_id} is {run['status']}; stopping")
                    break
                if arm and sim_run_id != armed_run:
                    arming = _arm_run(cur, sim_run_id, ARMED_BY)
                    armed_run = sim_run_id
                    log(_canonical({"armed": arming}))
                frame = _fetch_frame(cur, depot_id, sim_run_id)
                #: Read what came back, never what was asked for.
                if not allow_blind_frame:
                    _require_seeing_frame(frame, sim_run_id)
                class_rows = _fetch_class_rows(cur)
                result = fire(frame, class_rows, site=site, sim_run_id=sim_run_id,
                              depot_id=depot_id,
                              hour_of_day=(run["sim_hour"] if regime else None),
                              max_assets=max_assets, det_budget_s=det_budget_s,
                              default_ready_delta_min=default_ready_delta_min,
                              start_within_min=start_within_min,
                              serviceable_states=serviceable_states,
                              allow_rejection=allow_rejection)
                rows, record = result["rows"], result["fire"]
                record["tick_count_at_fetch"] = run["tick_count"]
                record["run_resolved_by"] = "auto" if auto_run else "argument"
                #: G58: what woke this fire, and how many ticks passed since the
                #: last one. 0223 had to reconstruct both by joining the fire log
                #: to the deferral ledger; they are columns now.
                record["fire_trigger"] = trigger
                record["ticks_since_last_fire"] = (
                    None if last_fired_tick is None or run["tick_count"] is None
                    else run["tick_count"] - last_fired_tick)
                #: So a fire row says whether the frame it planned against was
                #: armed by this loop, armed already, or deliberately blind.
                record["arming"] = arming if arm else {"verdict": "not_armed_by_loop"}
                receipt: dict[str, Any] = {"fire": record}
                if via == "batch":
                    cur.execute(
                        f"SELECT {BATCH}(%s::uuid, %s::uuid, %s, %s::jsonb, %s::jsonb, %s)",
                        (sim_run_id, depot_id, SOURCE,
                         _canonical([{"action_context": r["action_context"],
                                      "entity_type": r["entity_type"],
                                      "entity_id": r["entity_id"],
                                      "proposal": r["proposal"]} for r in rows]),
                         _canonical(record), ttl_seconds))
                    receipt["batch"] = cur.fetchone()[0]
                else:
                    ids = []
                    for r in rows:
                        cur.execute(
                            f"SELECT {DOOR}(%s::uuid, %s::uuid, %s, %s, %s::uuid, "
                            f"%s::jsonb, %s, %s)",
                            (sim_run_id, depot_id, r["action_context"], r["entity_type"],
                             r["entity_id"], _canonical(r["proposal"]), r["source"],
                             ttl_seconds))
                        ids.append(str(cur.fetchone()[0]))
                    receipt["proposal_ids"] = ids
                conn.commit()
            receipts.append(receipt)
            log(_canonical(receipt))
            last_fired_tick = run["tick_count"]
            if not loop or (max_fires is not None and n >= max_fires):
                break
            if follow_ticks:
                trigger = _wait_for_next_tick(conn, sim_run_id,
                                              after_tick=last_fired_tick,
                                              max_wait_s=tick_wait_s,
                                              poll_s=min(TICK_POLL_S, interval_s))
                if trigger in ("run_ended", "run_gone") and not auto_run:
                    log(_canonical({"stopping": trigger, "run": sim_run_id}))
                    break
            else:
                trigger = "interval"
                time.sleep(interval_s)
    return receipts


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _parse_states(spec: str | None) -> frozenset[str] | None:
    """`--states a,b` -> frozenset; None stays None (the default set)."""
    if spec is None:
        return None
    states = frozenset(s.strip() for s in spec.split(",") if s.strip())
    if not states:
        raise BridgeError("--states names no state")
    return states


def _load_json(path: str) -> Any:
    return json.loads(Path(path).read_text())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="python3 -m bridge.proposer_bridge",
        description="CP-SAT proposer -> ottoq_submit_external_proposal. "
                    "Offline: --frame + --classes + --emit-sql. Live: --dsn.")
    ap.add_argument("--run", required=True,
                    help="sim_run_id (uuid), or 'auto' in live mode to resolve the "
                         "depot's one running non-certification run each fire")
    ap.add_argument("--depot", required=True, help="depot_id (uuid)")
    ap.add_argument("--site", required=True,
                    help="site JSON (bridge/sites/*.json)")
    ap.add_argument("--frame", help="decision frame JSON (offline)")
    ap.add_argument("--classes", help="ottoq_vehicle_classes rows JSON (offline)")
    ap.add_argument("--emit-sql", help="write the door calls here (offline)")
    ap.add_argument("--dsn", help="postgres DSN (live); never commit one")
    ap.add_argument("--via", choices=("door", "batch"), default="door")
    ap.add_argument("--ttl", type=int, default=DEFAULT_TTL_S)
    ap.add_argument("--max-assets", type=int, default=None)
    ap.add_argument("--det-budget", type=float, default=DEFAULT_DET_BUDGET_S)
    ap.add_argument("--default-ready-delta", type=int, default=DEFAULT_READY_DELTA_MIN,
                    help="minutes until a vehicle with no declared deadline must be ready "
                         "(recorded as ready_by_source=default on every row)")
    ap.add_argument("--start-within", type=int, default=DEFAULT_START_WITHIN_MIN,
                    help="submit only charges the plan starts within this many minutes; "
                         "later ones abstain with their planned start")
    ap.add_argument("--allow-rejection", action="store_true",
                    help="let the solver return a plan for the vehicles it CAN serve and "
                         "abstain, with a reason, on the rest -- instead of declining an "
                         "oversubscribed frame outright (recorded on the fire record)")
    ap.add_argument("--states", default=None,
                    help="comma-separated SUBSET of the serviceable states to plan for "
                         "(narrows; default all four). D3: arrived_at_gate is the "
                         "population the one-tick hold is holding (L-60)")
    ap.add_argument("--regime", action="store_true",
                    help="live only: resolve the regime from the run's sim hour "
                         "(the expensive chain; default is the cheap two-pass)")
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--interval-s", type=float, default=10.0)
    ap.add_argument("--max-fires", type=int, default=None)
    ap.add_argument("--json-out", help="write the fire result (rows + record) here")
    ap.add_argument("--no-arm", action="store_true",
                    help="do NOT call ottoq_agentic_arm on the resolved run. The default "
                         "is to arm, because 0278 built the ritual and nothing performed "
                         "it: all six live runs and all 329 proposals before 2026-09-14 "
                         "were solved against a gate-off frame. Opting out is explicit.")
    ap.add_argument("--no-follow-ticks", action="store_true",
                    help="sleep --interval-s between fires instead of waiting for the "
                         "run's tick to move. The default is to FOLLOW THE TICK, "
                         "because the first-refusal seat is exactly one tick wide "
                         "(ottoq_cuopt_defer_roll) and a loop on a wall clock answers "
                         "it only by coincidence: measured on run 36e5cc68, every seat "
                         "armed at a tick this loop fired on was answered (15 of 15) "
                         "and every seat armed at a tick it missed was not (12 of 12). "
                         "See db/checks/0223.")
    ap.add_argument("--tick-wait-s", type=float, default=DEFAULT_TICK_WAIT_S,
                    help="how long to wait for the tick to move before firing anyway. "
                         "A bound, not a target: a loop that naps silently through its "
                         "whole window looks identical to one that worked.")
    ap.add_argument("--allow-blind-frame", action="store_true",
                    help="propose even when the frame carries no selector.facts_version, "
                         "so `offerable` is absent and a reserved-but-empty stall reads as "
                         "free. For MEASURING the blind behaviour only -- at tick 4 on the "
                         "flagship depot the blind frame offered 25 points and the facts "
                         "frame offered 0.")
    ap.add_argument("--idle-ok", action="store_true",
                    help="for schedulers: exit 0 when the depot has no running run to "
                         "propose into. An ambiguous depot or a certification arm still "
                         "exits non-zero -- those are decisions, not idleness.")
    args = ap.parse_args(argv)

    site = _load_json(args.site)
    try:
        if args.dsn:
            receipts = run_live(args.dsn, sim_run_id=args.run, depot_id=args.depot,
                                site=site, ttl_seconds=args.ttl,
                                max_assets=args.max_assets,
                                det_budget_s=args.det_budget, via=args.via,
                                regime=args.regime, loop=args.loop,
                                interval_s=args.interval_s, max_fires=args.max_fires,
                                default_ready_delta_min=args.default_ready_delta,
                                start_within_min=args.start_within,
                                serviceable_states=_parse_states(args.states),
                                allow_rejection=args.allow_rejection,
                                arm=not args.no_arm,
                                allow_blind_frame=args.allow_blind_frame,
                                follow_ticks=not args.no_follow_ticks,
                                tick_wait_s=args.tick_wait_s)
            if args.json_out:
                Path(args.json_out).write_text(json.dumps(receipts, indent=1, default=str))
            return 0
        if not (args.frame and args.classes):
            ap.error("offline mode needs --frame and --classes (or use --dsn)")
        result = fire(_load_json(args.frame), _load_json(args.classes), site=site,
                      sim_run_id=args.run, depot_id=args.depot,
                      max_assets=args.max_assets, det_budget_s=args.det_budget,
                      default_ready_delta_min=args.default_ready_delta,
                      start_within_min=args.start_within,
                      serviceable_states=_parse_states(args.states),
                      allow_rejection=args.allow_rejection)
        sql = emit_sql(result, sim_run_id=args.run, depot_id=args.depot,
                       ttl_seconds=args.ttl, via=args.via)
        if args.emit_sql:
            Path(args.emit_sql).write_text(sql)
        else:
            sys.stdout.write(sql)
        if args.json_out:
            Path(args.json_out).write_text(json.dumps(result, indent=1, default=str))
        print(_canonical(result["fire"]), file=sys.stderr)
        return 0
    except BridgeIdle as exc:
        if args.idle_ok:
            print(_canonical({"idle": str(exc)}))
            return 0
        print(f"bridge: {exc}", file=sys.stderr)
        return 2
    except BridgeError as exc:
        print(f"bridge: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
