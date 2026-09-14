#!/usr/bin/env python3
"""compile-check.py -- catch the errors in a migration that only surface when it
is applied, BEFORE the apply window, without running any of its effects.

WHY THIS EXISTS
---------------
Two bugs of this class shipped into PENDING migrations in one afternoon:

  0322  RAISE ... '% -> %% ... (still %)', a, b, c, d
        Three placeholders fed four arguments (%% is a literal percent).
        A COMPILE-time error -- and it sits in a guard, so the first time it
        would have run is the first time the guard had to work.

  0321  format('0321 P0: % not found', x)
        RAISE accepts a bare %; format() demands %s. A RUNTIME error.

Both would otherwise have surfaced only during an apply window, after a
certification round had been waited out.

TWO PASSES, BECAUSE ONE PASS CATCHES ONLY ONE OF THEM
-----------------------------------------------------
PASS 1 -- RUN THE FILE. psql -f against a scratch database. Execution stops at
the first precondition that fails, which in a scratch database is early and by
design. Everything evaluated up to that point is checked for real, which is how
0321's format() bug was found: the template is a variable, so PostgreSQL cannot
check it until the RAISE actually evaluates.

PASS 2 -- COMPILE EVERY BLOCK. Because pass 1 stops early, every block after the
first failure is never compiled. So each `DO $tag$ ... $tag$;` is extracted and
wrapped in a throwaway CREATE FUNCTION: PostgreSQL compiles a plpgsql body at
CREATE time without executing it, so the block is syntax-checked and its RAISE
arities validated with no table needing to exist. This is how 0322's RAISE
arity bug is caught.

VERIFIED AGAINST BOTH BUGS. tests/test_compile_check.py reconstructs each one
and requires this script to fail on it, plus a correct control it must pass. An
earlier version of this docstring claimed pass 2 caught the format() bug; the
test disproved that -- pass 2 compiles, and a format() with a variable template
is not a compile-time error. The claim was corrected rather than the test.

WHAT IT CANNOT DO
-----------------
It cannot check that a query returns what the author meant, that a column
exists, that a precondition is TRUE against the live engine, or that a
substitution anchor still matches the live source. plpgsql plans SQL statements
lazily, so a typo'd column inside a query is invisible to both passes. This is a
LINTER, not a dry run, and calling it a dry run would be the exact defect class
this repo keeps convicting: an instrument that answers a narrower question than
its name suggests.

USAGE
  scripts/compile-check.py db/migrations/0321_*.sql
  Needs a scratch server on /var/tmp:55432 (initdb + pg_ctl; see tests).
"""
import os
import re
import subprocess
import sys

# Connection is environment-driven so the same script serves a local scratch
# cluster (unix socket) and a CI service container (TCP). Defaults are the local
# cluster these tests were developed against.
PSQL = ["psql",
        "-h", os.environ.get("PGHOST", "/var/tmp"),
        "-p", os.environ.get("PGPORT", "55432"),
        "-U", os.environ.get("PGUSER", "postgres"),
        "-d", os.environ.get("PGDATABASE", "postgres"),
        "-v", "ON_ERROR_STOP=1", "-q", "-t", "-A"]

# Errors that mean "compiled fine, then could not run here" -- expected, because
# the scratch database deliberately has none of the engine's objects.
RUNTIME_OK = re.compile(
    r"does not exist|no schema has been selected|relation .* does not exist", re.I)


def blocks(sql: str):
    """Yield (kind, statement) for each DO block and CREATE FUNCTION in the file."""
    for m in re.finditer(r"^DO\s+(\$[A-Za-z_]*\$)(.*?)\1\s*;", sql, re.S | re.M):
        yield "DO", m.group(2)
    for m in re.finditer(
            r"^(CREATE\s+OR\s+REPLACE\s+FUNCTION\b.*?LANGUAGE\s+plpgsql.*?"
            r"(\$[A-Za-z_]*\$).*?\2\s*;)", sql, re.S | re.M | re.I):
        yield "FUNCTION", m.group(1)


def tag_for(body: str) -> str:
    for t in ("$ck$", "$ck1$", "$ck2$", "$ck3$", "$ck4$"):
        if t not in body:
            return t
    raise SystemExit("compile-check: every candidate dollar tag occurs in the body")


def run(stmt: str):
    p = subprocess.run(PSQL + ["-c", stmt], capture_output=True, text=True)
    return p.returncode, (p.stderr or "").strip()


def run_file(path):
    """PASS 1: execute the file. Errors that are not 'this object does not exist'
    are real -- including runtime-only ones like a bad format() template."""
    p = subprocess.run(PSQL + ["-f", path], capture_output=True, text=True)
    err = (p.stderr or "").strip()
    if p.returncode == 0:
        return []
    # A precondition that RAISEs its own message is the file working correctly
    # against an empty database, not a defect.
    if RUNTIME_OK.search(err) or re.search(r"ERROR:\s+0\d{3} P\d", err):
        return []
    return [l for l in err.splitlines() if "ERROR" in l][:4]


def main(paths):
    # NO SILENT SKIP. A gate that quietly passes when its database is missing is
    # a gate nobody reads -- the failure mode verify.yml's own comments warn
    # about for the drift check. Exit 2 is distinguishable from exit 1 (a real
    # finding), so a caller that legitimately has no server can tell them apart;
    # CI treats any non-zero as failure, because CI always has one.
    rc, err = run("select 1")
    if rc != 0:
        print("compile-check: NO DATABASE. Set PGHOST/PGPORT/PGUSER/PGDATABASE, or "
              "start a scratch cluster. Refusing to report a pass without checking.")
        print(f"  {err.splitlines()[0] if err else ''}")
        return 2

    # twin/ottoq are referenced by SET search_path on the real functions; a
    # missing schema there is a compile-time error and would be a false positive.
    run("CREATE SCHEMA IF NOT EXISTS twin; CREATE SCHEMA IF NOT EXISTS ottoq;")
    bad = 0
    for path in paths:
        sql = open(path).read()
        problems = []
        for line in run_file(path):
            problems.append(("run", line))
        n = 0
        for kind, body in blocks(sql):
            n += 1
            if kind == "DO":
                t = tag_for(body)
                stmt = (f"CREATE OR REPLACE FUNCTION pg_temp.__ck_{n}() RETURNS void "
                        f"LANGUAGE plpgsql AS {t}{body}{t};")
            else:
                stmt = body
            rc, err = run(stmt)
            if rc != 0 and not RUNTIME_OK.search(err):
                for line in err.splitlines()[:3]:
                    problems.append((f"compile block #{n} ({kind})", line))
        if problems:
            bad += 1
            print(f"FAIL  {path}")
            for where, line in problems:
                print(f"      [{where}] {line}")
        else:
            print(f"ok    {path}: ran, and {n} block(s) compiled")
    if bad:
        print(f"\ncompile-check: {bad} file(s) failed")
        return 1
    print("\ncompile-check: every file ran and every block compiled")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or sys.exit("usage: compile-check.py <file.sql> ...")))
