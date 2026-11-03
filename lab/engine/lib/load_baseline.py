#!/usr/bin/env python3
"""Load db/baseline/ into the lab database, statement by statement, to a fixpoint.

db/baseline/README.md says the dump "is not replayable top-to-bottom as-is": it
is a flattened end state (tables, then functions, then policies) with no
ordering between objects that depend on each other, and it omits sequences.
So this loader:

  1. creates every sequence a column default names with nextval(...) -- the
     dump has the defaults but not the sequences (a repo gap, derived here
     from the dump's own text, not from production);
  2. runs every statement on its own (autocommit: one transaction each), in
     the order tables -> functions -> constraints -> indexes -> views ->
     row-security switches -> policies, with check_function_bodies = off
     (a flattened dump's bodies name objects defined later in it);
  3. retries what failed, in the same order, until a round makes no progress;
  4. gives each nextval sequence to its column (OWNED BY), as serial does;
  5. loads the pg_cron rows with their production job ids. The lab server
     runs with cron.launch_active_jobs = off, and the build deactivates every
     job afterwards, so nothing is ever scheduled to run.

Output: a TSV of every statement that never succeeded (kind, object, SQLSTATE,
first error line) and a JSON summary, both under the --out prefix.
"""
import argparse
import collections
import json
import os
import re
import sys
import time

import psycopg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sqlsplit import split, split_marked  # noqa: E402

PHASES = ["table", "function", "constraint", "index", "view", "rls", "policy"]

NEXTVAL = re.compile(
    r"^\s+(\"?[A-Za-z_][\w$]*\"?)\s+(smallint|integer|bigint)\b[^\n]*?DEFAULT nextval\('([^']+)'::regclass\)",
    re.M)


ID = r'(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*)'
QN = rf"{ID}(?:\.{ID})?"


def classify(stmt: str):
    s = stmt.lstrip()
    m = re.match(rf"CREATE TABLE ({QN})", s)
    if m:
        return "table", m.group(1)
    m = re.match(rf"CREATE OR REPLACE (?:FUNCTION|PROCEDURE) ({QN}\([^)]*\))", s)
    if m:
        return "function", m.group(1)
    m = re.match(rf"ALTER TABLE (?:ONLY )?({QN}) ADD CONSTRAINT ({ID})", s)
    if m:
        return "constraint", m.group(1) + "." + m.group(2)
    m = re.match(rf"ALTER TABLE (?:ONLY )?({QN}) (?:ENABLE|DISABLE|FORCE|NO FORCE) ROW LEVEL SECURITY", s)
    if m:
        return "rls", m.group(1)
    m = re.match(rf"CREATE (?:UNIQUE )?INDEX (?:IF NOT EXISTS )?({ID}) ON (?:ONLY )?({QN})", s)
    if m:
        return "index", m.group(2) + "." + m.group(1)
    m = re.match(rf"CREATE (?:OR REPLACE )?(?:MATERIALIZED )?VIEW ({QN})", s)
    if m:
        return "view", m.group(1)
    m = re.match(rf"CREATE POLICY ({ID}) ON ({QN})", s)
    if m:
        return "policy", m.group(2) + "." + m.group(1)
    return "other", s.split("\n", 1)[0][:80]


def first_line(err: Exception) -> str:
    diag = getattr(err, "diag", None)
    msg = (diag.message_primary if diag and diag.message_primary else str(err)).strip()
    return msg.split("\n", 1)[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--dsn", required=True)
    ap.add_argument("--out", required=True, help="path prefix for .tsv/.json")
    a = ap.parse_args()
    base = os.path.join(a.repo, "db", "baseline")

    stmts = []  # (phase, object, text, source_file, line)
    for f in ("tables.sql", "rls_policies.sql"):
        for text, line in split(open(os.path.join(base, f), encoding="utf-8").read()):
            kind, obj = classify(text)
            stmts.append((kind, obj, text, f, line))
    for f in ("functions_public.sql", "functions_ottoq.sql", "functions_twin.sql"):
        for _name, text, line in split_marked(open(os.path.join(base, f), encoding="utf-8").read()):
            kind, obj = classify(text)
            stmts.append((kind, obj, text, f, line))
    other = [s for s in stmts if s[0] not in PHASES]
    if other:
        print("unclassified statements:", [(s[1], s[3], s[4]) for s in other[:5]], file=sys.stderr)
        sys.exit(2)
    order = {p: i for i, p in enumerate(PHASES)}
    stmts.sort(key=lambda s: order[s[0]])  # stable: keeps file order inside a phase
    attempted = collections.Counter(s[0] for s in stmts)

    t0 = time.time()
    conn = psycopg.connect(a.dsn, autocommit=True)
    cur = conn.cursor()
    cur.execute("SET check_function_bodies = off")
    cur.execute("SET client_min_messages = warning")

    # 1. sequences named by nextval() defaults, typed like the column
    seqs = []
    for kind, obj, text, f, line in stmts:
        if kind != "table":
            continue
        for col, typ, seq in NEXTVAL.findall(text):
            qseq = seq if "." in seq else "public." + seq
            seqs.append((qseq, typ, obj, col))
    for qseq, typ, _t, _c in seqs:
        cur.execute(f"CREATE SEQUENCE IF NOT EXISTS {qseq} AS {typ}")

    # 2-3. statements to a fixpoint
    pending = stmts
    rounds = []
    last_err = {}
    while pending:
        failed = []
        for st in pending:
            try:
                cur.execute(st[2])
            except psycopg.Error as e:
                failed.append(st)
                last_err[id(st)] = (e.sqlstate or "", first_line(e))
        rounds.append({"tried": len(pending), "ok": len(pending) - len(failed)})
        if len(failed) == len(pending):
            break
        pending = failed
    failed = pending if rounds and rounds[-1]["ok"] == 0 else []

    # 4. serial-style ownership for the sequences created in step 1
    owned_fail = 0
    for qseq, _typ, tbl, col in seqs:
        try:
            cur.execute(f"ALTER SEQUENCE {qseq} OWNED BY {tbl}.{col}")
        except psycopg.Error:
            owned_fail += 1

    # 5. cron rows, keeping production's job ids (never launched: see docstring)
    cron_text = open(os.path.join(base, "cron_jobs.sql"), encoding="utf-8").read()
    cron = []
    for m in re.finditer(r"^-- jobid (\d+)\s*\|\s*jobname: (\S+)\s*\|\s*active: (\w+).*?^(SELECT cron\.schedule\(.*?\);)\s*$",
                         cron_text, re.S | re.M):
        jobid, jobname, active, sql = int(m.group(1)), m.group(2), m.group(3).lower() == "true", m.group(4)
        try:
            cur.execute("SELECT setval('cron.jobid_seq', %s, false)", (jobid,))
            cur.execute(sql)
            cur.execute("UPDATE cron.job SET active = %s WHERE jobid = %s", (active, jobid))
            cron.append({"jobid": jobid, "jobname": jobname, "loaded": True})
        except psycopg.Error as e:
            cron.append({"jobid": jobid, "jobname": jobname, "loaded": False, "error": first_line(e)})
    conn.close()

    ok = collections.Counter(s[0] for s in stmts) - collections.Counter(s[0] for s in failed)
    with open(a.out + ".tsv", "w", encoding="utf-8") as fh:
        fh.write("kind\tobject\tsqlstate\tfirst_error\tsource\tline\n")
        for st in failed:
            state, msg = last_err[id(st)]
            fh.write(f"{st[0]}\t{st[1]}\t{state}\t{msg}\t{st[3]}\t{st[4]}\n")
    summary = {
        "seconds": round(time.time() - t0, 1),
        "sequences_created_from_nextval_defaults": len(seqs),
        "sequence_owned_by_failures": owned_fail,
        "rounds": rounds,
        "attempted": dict(attempted),
        "ok": {k: ok.get(k, 0) for k in PHASES},
        "failed": dict(collections.Counter(s[0] for s in failed)),
        "failed_by_cause": collections.Counter(last_err[id(s)][1] for s in failed).most_common(15),
        "cron": cron,
    }
    with open(a.out + ".json", "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=1, default=str)
    print(json.dumps({k: summary[k] for k in ("seconds", "attempted", "ok", "failed", "rounds")}))


if __name__ == "__main__":
    main()
