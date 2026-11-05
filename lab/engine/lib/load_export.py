#!/usr/bin/env python3
"""Load a production schema export (lib/export_prod.py) into the lab database.

Each phase file is a list of statements, each preceded by a `-- @@ <kind> <identity>` marker.
Phases run in file-name order (default privileges, phase 23, only after the fixpoint below), one statement per transaction, with search_path = '' (every name
in the export is schema-qualified) and check_function_bodies = off (as pg_dump loads: a body may
name an object a later phase creates). A failed statement is retried after the remaining phases,
until a whole retry pass changes nothing (a fixpoint). Whatever still fails is reported, never
skipped silently.

    python -I load_export.py --export DIR --dsn DSN --out REPORT_PREFIX
writes REPORT_PREFIX.tsv (one row per statement that did not load on its first attempt: phase,
kind, identity, outcome, attempts, sqlstate, error) and REPORT_PREFIX.json (counts per phase).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import time

import psycopg

MARK = "-- @@ "
FINAL_PHASES = {"23_default_privileges"}


def parse(path: str) -> list[dict]:
    stmts: list[dict] = []
    cur: dict | None = None
    phase = os.path.basename(path)[:-4]
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith(MARK):
                if cur:
                    stmts.append(cur)
                kind, _, ident = line[len(MARK):].rstrip("\n").partition(" ")
                cur = {"phase": phase, "kind": kind, "ident": ident, "sql": ""}
            elif cur is not None:
                cur["sql"] += line
    if cur:
        stmts.append(cur)
    return stmts


def run(conn: psycopg.Connection, st: dict) -> tuple[bool, str, str]:
    try:
        with conn.cursor() as c:
            c.execute(st["sql"])
        return True, "", ""
    except psycopg.Error as e:
        diag = e.diag
        msg = (diag.message_primary or str(e)).splitlines()[0] if (diag.message_primary or str(e)) else ""
        return False, diag.sqlstate or "", msg[:400]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--export", required=True)
    ap.add_argument("--dsn", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--skip", default="", help="comma-separated phase names to leave out")
    a = ap.parse_args()
    skip = {s for s in a.skip.split(",") if s}
    files = sorted(glob.glob(os.path.join(a.export, "[0-9][0-9]_*.sql")))
    stmts = [s for f in files for s in parse(f) if s["phase"] not in skip]
    # Default privileges go on only after every object exists: an object created by a retry
    # must not pick them up, or its ACL would carry grants production's does not.
    final = [s for s in stmts if s["phase"] in FINAL_PHASES]
    stmts = [s for s in stmts if s["phase"] not in FINAL_PHASES]
    t0 = time.time()
    conn = psycopg.connect(a.dsn, autocommit=True)
    with conn.cursor() as c:
        c.execute("SELECT pg_catalog.set_config('search_path', '', false)")
        c.execute("SET check_function_bodies = off")
        c.execute("SET client_min_messages = warning")
        c.execute("SET statement_timeout = 0")
    pending: list[dict] = []
    for st in stmts:
        ok, code, msg = run(conn, st)
        st.update(ok=ok, sqlstate=code, error=msg, attempts=1)
        if not ok:
            pending.append(st)
    rounds = 0
    while pending:
        rounds += 1
        still = []
        for st in pending:
            ok, code, msg = run(conn, st)
            st["attempts"] += 1
            if ok:
                st.update(ok=True, sqlstate="", error="", recovered_in_round=rounds)
            else:
                st.update(sqlstate=code, error=msg)
                still.append(st)
        if len(still) == len(pending):
            break
        pending = still
    for st in final:
        ok, code, msg = run(conn, st)
        st.update(ok=ok, sqlstate=code, error=msg, attempts=1)
    stmts += final
    conn.close()
    secs = round(time.time() - t0, 1)

    # Only the statements that did not load first time are listed (the rest is every other
    # statement of the export, loaded on the first attempt; the JSON counts them).
    with open(a.out + ".tsv", "w", encoding="utf-8") as fh:
        fh.write("phase\tkind\tident\toutcome\tattempts\tsqlstate\terror\n")
        for st in stmts:
            if st["ok"] and st["attempts"] == 1:
                continue
            outcome = "ok" if st["ok"] else "failed"
            fh.write(f"{st['phase']}\t{st['kind']}\t{st['ident']}\t{outcome}\t{st['attempts']}\t{st['sqlstate']}\t"
                     f"{st['error'].replace(chr(9), ' ')}\n")
    summary: dict = {"statements": len(stmts), "ok": sum(s["ok"] for s in stmts),
                     "failed": sum(not s["ok"] for s in stmts), "retry_rounds": rounds,
                     "recovered_on_retry": sum(1 for s in stmts if s["ok"] and s["attempts"] > 1),
                     "seconds": secs, "by_phase": {}}
    for st in stmts:
        p = summary["by_phase"].setdefault(st["phase"], {"ok": 0, "failed": 0})
        p["ok" if st["ok"] else "failed"] += 1
    with open(a.out + ".json", "w") as fh:
        json.dump(summary, fh, indent=1)
        fh.write("\n")
    print(f"loaded {summary['ok']} of {summary['statements']} statements "
          f"({summary['failed']} failed, {summary['recovered_on_retry']} on retry, {rounds} retry rounds) in {secs}s")
    for st in stmts:
        if not st["ok"]:
            print(f"  FAILED {st['phase']} {st['kind']} {st['ident'][:100]}: {st['sqlstate']} {st['error'][:200]}")
    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
