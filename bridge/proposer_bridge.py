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
    propose,
)

SOURCE = "forward_lex"
ACTION_CONTEXT = "stall_assignment"
ENTITY_TYPE = "vehicle"
DOOR = "public.ottoq_submit_external_proposal"
BATCH = "public.ottoq_proposer_submit_batch"
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


def fire(frame: dict, class_rows: list[dict], *, site: dict,
         sim_run_id: str, depot_id: str,
         hour_of_day: int | None = None,
         max_assets: int | None = None,
         det_budget_s: float = DEFAULT_DET_BUDGET_S,
         ready_by_min: dict[str, int] | None = None,
         allow_rejection: bool = False,
         fired_at: str | None = None) -> dict:
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
    n_in_serviceable_state = sum(
        1 for v in vehicles if v.get("state") in DEFAULT_SERVICEABLE_STATES)

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
        "n_stalls": len(frame.get("stalls") or []),
        "hour_of_day": hour_of_day,
        "max_assets": max_assets,
        "det_budget_s": det_budget_s,
        "allow_rejection": allow_rejection,
    }

    try:
        result = propose(frame, class_table, site=site,
                         hour_of_day=hour_of_day, max_assets=max_assets,
                         det_budget_s=det_budget_s, ready_by_min=ready_by_min,
                         allow_rejection=allow_rejection)
    except FrameError as exc:
        #: e.g. "frame has no charge-capable stalls that declare an accepted
        #: inlet". Nothing to propose ON, which is a fact about the frame and is
        #: recorded as one; it must not take a loop down.
        record.update(status="empty", n_rows=0, n_planned=0, n_abstained=0,
                      n_deferred=0, solver=None, error=str(exc))
        return {"rows": [], "fire": record}

    rows = list(result.get("proposals") or [])
    for row in rows:
        if row.get("source") != SOURCE:
            raise BridgeError(f"proposer stamped source {row.get('source')!r}; "
                              f"this bridge submits only {SOURCE!r}")
        if row.get("action_context") != ACTION_CONTEXT:
            raise BridgeError(f"unexpected action_context {row.get('action_context')!r}")

    record.update(
        status="proposed" if rows else "empty",
        n_rows=len(rows),
        n_planned=int(result.get("planned") or 0),
        n_abstained=int(result.get("abstained") or 0),
        n_deferred=int(result.get("deferred") or 0),
        solver=result.get("solver"),
        note=result.get("note"),
    )
    return {"rows": rows, "fire": record}


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
    return (f"SELECT {BATCH}('{run}'::uuid, '{depot}'::uuid, '{SOURCE}', "
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


def run_live(dsn: str, *, sim_run_id: str, depot_id: str, site: dict,
             ttl_seconds: int = DEFAULT_TTL_S, max_assets: int | None = None,
             det_budget_s: float = DEFAULT_DET_BUDGET_S, via: str = "door",
             regime: bool = False, loop: bool = False, interval_s: float = 10.0,
             max_fires: int | None = None, log=print) -> list[dict]:
    """Fetch → propose → submit, once or in a loop while the run is running.

    Every fire is committed in its own transaction so the door's tick_seq stamp
    (0236) names the tick the batch actually landed in. Returns the receipts.
    """
    psycopg = _import_psycopg()
    sim_run_id = _require_uuid(sim_run_id, "sim_run_id")
    depot_id = _require_uuid(depot_id, "depot_id")
    receipts: list[dict] = []
    with psycopg.connect(dsn) as conn:
        n = 0
        while True:
            n += 1
            with conn.cursor() as cur:
                run = _run_row(cur, sim_run_id)
                if run["depot_id"].lower() != depot_id:
                    raise BridgeError(f"run {sim_run_id} is on depot {run['depot_id']}, "
                                      f"not {depot_id}")
                if run["status"] != "running":
                    log(f"run {sim_run_id} is {run['status']}; stopping")
                    break
                frame = _fetch_frame(cur, depot_id, sim_run_id)
                class_rows = _fetch_class_rows(cur)
                result = fire(frame, class_rows, site=site, sim_run_id=sim_run_id,
                              depot_id=depot_id,
                              hour_of_day=(run["sim_hour"] if regime else None),
                              max_assets=max_assets, det_budget_s=det_budget_s)
                rows, record = result["rows"], result["fire"]
                record["tick_count_at_fetch"] = run["tick_count"]
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
            if not loop or (max_fires is not None and n >= max_fires):
                break
            time.sleep(interval_s)
    return receipts


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _load_json(path: str) -> Any:
    return json.loads(Path(path).read_text())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="python3 -m bridge.proposer_bridge",
        description="CP-SAT proposer -> ottoq_submit_external_proposal. "
                    "Offline: --frame + --classes + --emit-sql. Live: --dsn.")
    ap.add_argument("--run", required=True, help="sim_run_id (uuid)")
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
    ap.add_argument("--regime", action="store_true",
                    help="live only: resolve the regime from the run's sim hour "
                         "(the expensive chain; default is the cheap two-pass)")
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--interval-s", type=float, default=10.0)
    ap.add_argument("--max-fires", type=int, default=None)
    ap.add_argument("--json-out", help="write the fire result (rows + record) here")
    args = ap.parse_args(argv)

    site = _load_json(args.site)
    try:
        if args.dsn:
            receipts = run_live(args.dsn, sim_run_id=args.run, depot_id=args.depot,
                                site=site, ttl_seconds=args.ttl,
                                max_assets=args.max_assets,
                                det_budget_s=args.det_budget, via=args.via,
                                regime=args.regime, loop=args.loop,
                                interval_s=args.interval_s, max_fires=args.max_fires)
            if args.json_out:
                Path(args.json_out).write_text(json.dumps(receipts, indent=1, default=str))
            return 0
        if not (args.frame and args.classes):
            ap.error("offline mode needs --frame and --classes (or use --dsn)")
        result = fire(_load_json(args.frame), _load_json(args.classes), site=site,
                      sim_run_id=args.run, depot_id=args.depot,
                      max_assets=args.max_assets, det_budget_s=args.det_budget)
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
    except BridgeError as exc:
        print(f"bridge: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
