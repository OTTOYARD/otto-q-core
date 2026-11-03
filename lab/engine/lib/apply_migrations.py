#!/usr/bin/env python3
"""Apply db/migrations/ to the lab database, one file per transaction, in ledger order.

WHICH FILES. Every NNNN_*.sql whose header `-- migration-version:` is
  * a ledger timestamp (applied to production through apply_migration), or
  * APPLIED-NO-LEDGER-ROW (applied, e.g. pasted into the SQL editor, no row), or
  * UNVERIFIED-NO-LEDGER-ROW (no row and no record either way; see G18),
is applied. PENDING files (not applied to production) are skipped and listed.

ORDER. Ledger files sort by their version. A file with no ledger version has no
timestamp to sort by, so it is placed immediately after its numeric
predecessor's version (the nearest lower-numbered file that has one); a run of
such files keeps its numeric order. This is an inference and the report says
so: file numbers and ledger versions disagree in places (153 files carry a
version lower than some lower-numbered file's), so numeric order alone would
also be a guess.

HOW. `psql -X -1 -v ON_ERROR_STOP=1 -f FILE`: one transaction per file, exactly
the file's text (psql handles its meta-commands; every file has at most one
BEGIN/COMMIT pair and nothing after the COMMIT, checked 2026-11-03). Production
creates functions with check_function_bodies = on (its default, read
2026-11-03), and so does the first attempt here. A file whose first error is an
undefined-object error (SQLSTATE 42P01 table, 42883 function, 42703 column,
42704 object, 3F000 schema) is retried ONCE with check_function_bodies = off:
that error can come from a SQL-language function naming an object production
had and the lab does not, so success on the retry is recorded as
`ok_bodies_unchecked`, with the first attempt's error kept. Any other first
error (a syntax error, a guard's RAISE) is final: production would have
refused the file too. A file
that applies and carries a ledger version gets its row in the lab's
supabase_migrations.schema_migrations (statements = the file's text).

Output: TSV (one row per file) and JSON summary under the --out prefix.
"""
import argparse
import collections
import json
import os
import re
import subprocess
import sys
import time

import psycopg

TS = re.compile(r"^\d{14}$")
NUM = re.compile(r"^(\d{4})([a-z]?)_")
FIRST_ERR = re.compile(r"(?:ERROR|FATAL):\s+(?:([0-9A-Z]{5}):\s+)?(.*)")
RETRY_STATES = {"42P01", "42883", "42703", "42704", "3F000"}


def header(path):
    v = n = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh):
            if v is None:
                m = re.match(r"--\s*migration-version:\s*(\S+)", line)
                if m:
                    v = m.group(1)
            if n is None:
                m = re.match(r"--\s*migration-name:\s*(\S+)", line)
                if m:
                    n = m.group(1)
            if (v and n) or i > 60:
                break
    return v, n


def plan(mig_dir):
    files = []
    for f in sorted(os.listdir(mig_dir)):
        m = NUM.match(f)
        if not m or not f.endswith(".sql") or "EXAMPLE" in f:
            continue
        v, n = header(os.path.join(mig_dir, f))
        files.append({"file": f, "num": (int(m.group(1)), m.group(2)), "version": v, "name": n})
    files.sort(key=lambda x: x["num"])
    last = "0"
    for x in files:
        if x["version"] and TS.match(x["version"]):
            x["key"] = (x["version"], 0, x["num"])
            last = x["version"]
        else:
            x["key"] = (last, 1, x["num"])
    files.sort(key=lambda x: x["key"])
    return files


def run_psql(psql, conn_args, path, extra_opts=""):
    env = dict(os.environ)
    env["PGOPTIONS"] = ("-c client_min_messages=warning " + extra_opts).strip()
    t0 = time.time()
    p = subprocess.run([psql, "-X", "-q", "-1", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose",
                        *conn_args, "-f", path],
                       capture_output=True, text=True, env=env)
    err, state = "", ""
    if p.returncode != 0:
        for line in (p.stderr or "").splitlines():
            m = FIRST_ERR.search(line)
            if m:
                state, err = (m.group(1) or ""), m.group(2).strip()
                break
        if not err:
            err = ((p.stderr or p.stdout or "").strip().splitlines()[-1:] or ["(no message)"])[0]
    return p.returncode == 0, state, err, time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--psql", required=True)
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    mig = os.path.join(a.repo, "db", "migrations")
    conn_args = ["-h", a.host, "-p", a.port, "-U", "postgres", "-d", a.db]
    rows = []
    t_all = time.time()
    lconn = psycopg.connect(f"host={a.host} port={a.port} dbname={a.db} user=postgres", autocommit=True)
    ledger = lconn.cursor()
    for i, x in enumerate(plan(mig), 1):
        v = x["version"] or "(none)"
        path = os.path.join(mig, x["file"])
        if v == "PENDING":
            rows.append({**x, "seq": i, "status": "skipped_pending", "sqlstate": "", "error": "", "seconds": 0.0})
            continue
        ok, state, err, secs = run_psql(a.psql, conn_args, path)
        status, first_err = ("ok", "") if ok else ("failed", err)
        if not ok and state in RETRY_STATES:
            ok2, _s2, _e2, secs2 = run_psql(a.psql, conn_args, path, "-c check_function_bodies=off")
            secs += secs2
            if ok2:
                status = "ok_bodies_unchecked"
        if status.startswith("ok") and TS.match(v):
            text = open(path, encoding="utf-8", errors="replace").read()
            try:
                ledger.execute(
                    "INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by) "
                    "VALUES (%s, %s, ARRAY[%s], 'lab/engine build') ON CONFLICT (version) DO NOTHING",
                    (v, x["name"], text))
            except psycopg.Error:
                status += "+ledger_row_failed"
        rows.append({**x, "seq": i, "status": status, "sqlstate": state, "error": first_err,
                     "seconds": round(secs, 2)})
        print(f"{i:4d} {status:20s} {x['file'][:70]}", flush=True)

    lconn.close()
    with open(a.out + ".tsv", "w", encoding="utf-8") as fh:
        fh.write("seq\tfile\tversion\tstatus\tseconds\tsqlstate\tfirst_error\n")
        for r in rows:
            fh.write(f"{r['seq']}\t{r['file']}\t{r['version']}\t{r['status']}\t{r['seconds']}\t"
                     f"{r['sqlstate']}\t{r['error']}\n")
    by_status = collections.Counter(r["status"] for r in rows)
    by_class = collections.defaultdict(collections.Counter)
    for r in rows:
        by_class[(r["version"] if not TS.match(r["version"] or "") else "ledger")][r["status"]] += 1
    summary = {
        "seconds": round(time.time() - t_all, 1),
        "files": len(rows),
        "by_status": dict(by_status),
        "by_header_class": {k: dict(c) for k, c in by_class.items()},
        "first_errors_top": collections.Counter(
            re.sub(r"\d+", "N", r["error"])[:160] for r in rows if r["status"] != "ok" and r["error"]).most_common(25),
    }
    with open(a.out + ".json", "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=1)
    print(json.dumps({k: summary[k] for k in ("seconds", "files", "by_status")}))


if __name__ == "__main__":
    main()
