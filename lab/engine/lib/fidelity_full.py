#!/usr/bin/env python3
"""Compare the lab with production object by object, now that production can be read directly.

lib/fidelity.py (2026-11-03) was built for a channel that could not move rows out of
production, so it shipped tokens in and counts out. With the Management API's read-only
endpoint (lib/prod_read.py) both sides simply run the same census and the comparison happens
here. The census is unchanged -- sql/fidelity_objects.sql, the one the 2026-11-03 report used,
so the numbers are comparable -- plus sql/fidelity_extra.sql for what it did not cover (ACLs,
comments, sequences, default privileges, cron jobs, the ledger's versions).

    /var/tmp/ottoq_lab_venv/bin/python -I lab/engine/lib/fidelity_full.py --dsn DSN --out DIR

writes DIR/lab_census.tsv, DIR/prod_census.tsv (kind, schema, ident, h1, h2, h3), DIR/diff.tsv
(every object that is not identical, with how it differs) and DIR/summary.json, and prints the
summary table. Both censuses run with search_path "$user", public, extensions.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fidelity  # noqa: E402  (objects_cte: the 2026-11-03 census, comments stripped)
import prod_read  # noqa: E402

EXTRA_SQL = os.path.join(HERE, "..", "sql", "fidelity_extra.sql")
SEARCH_PATH = "select pg_catalog.set_config('search_path', '\"$user\", public, extensions', true); "


def extra_sql() -> str:
    lines = [ln for ln in open(EXTRA_SQL, encoding="utf-8").read().splitlines() if not ln.strip().startswith("--")]
    return "\n".join(lines)


def census_queries() -> list[str]:
    base = fidelity.objects_cte() + " SELECT kind, s, ident, h1, h2, h3 FROM o"
    return [base, extra_sql()]


def lab_rows(dsn: str) -> tuple[str, list[tuple]]:
    import psycopg
    rows: list[tuple] = []
    with psycopg.connect(dsn, autocommit=True) as conn, conn.cursor() as c:
        c.execute("SET search_path TO \"$user\", public, extensions")
        c.execute("SELECT now()::text")
        at = c.fetchone()[0]
        for q in census_queries():
            c.execute(q)
            rows += [tuple("" if v is None else str(v) for v in r) for r in c.fetchall()]
    return at, rows


def prod_rows() -> tuple[str, list[tuple]]:
    rows: list[tuple] = []
    at = prod_read.query("select now()::text as at")[0]["at"]
    for q in census_queries():
        for r in prod_read.query(SEARCH_PATH + q):
            rows.append(tuple("" if r[k] is None else str(r[k]) for k in ("kind", "s", "ident", "h1", "h2", "h3")))
    return at, rows


def write_tsv(path: str, rows: list[tuple]) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("kind\tschema\tident\th1\th2\th3\n")
        for r in sorted(rows):
            fh.write("\t".join(v.replace("\t", " ").replace("\n", " ") for v in r) + "\n")


def classify(kind: str, p: tuple, l: tuple) -> str:
    if p[3:] == l[3:]:
        return "identical"
    if kind == "routine":
        if p[3] == l[3] and p[4] != l[4]:
            return "header_only"
        if p[3] != l[3] and p[5] == l[5]:
            return "comments_only"
        return "code_differs"
    if kind == "table":
        return "order_only" if p[4] == l[4] else "columns_differ"
    if kind == "view":
        return "definition_differs" if p[3] == l[3] else "columns_differ"
    if kind == "acl":
        return "owner_differs" if p[3] == l[3] else "acl_differs"
    return "differs"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lab_at, lab = lab_rows(a.dsn)
    prod_at, prod = prod_rows()
    write_tsv(os.path.join(a.out, "lab_census.tsv"), lab)
    write_tsv(os.path.join(a.out, "prod_census.tsv"), prod)
    key = lambda r: (r[0], r[1], r[2])  # noqa: E731
    dup_l = [k for k, n in Counter(key(r) for r in lab).items() if n > 1]
    dup_p = [k for k, n in Counter(key(r) for r in prod).items() if n > 1]
    L = {key(r): r for r in lab}
    P = {key(r): r for r in prod}
    summary: dict = defaultdict(lambda: defaultdict(Counter))
    diffs = []
    for k in sorted(set(L) | set(P)):
        kind, s = k[0], k[1]
        if k not in L:
            cls = "missing_in_lab"
        elif k not in P:
            cls = "extra_in_lab"
        else:
            cls = classify(kind, P[k], L[k])
        summary[kind][s][cls] += 1
        if cls != "identical":
            diffs.append((kind, s, k[2], cls, "|".join(P.get(k, ("",) * 6)[3:]), "|".join(L.get(k, ("",) * 6)[3:])))
    with open(os.path.join(a.out, "diff.tsv"), "w", encoding="utf-8") as fh:
        fh.write("kind\tschema\tident\tclass\tprod(h1|h2|h3)\tlab(h1|h2|h3)\n")
        for d in diffs:
            fh.write("\t".join(v.replace("\t", " ").replace("\n", " ") for v in d) + "\n")
    out = {"lab_read_at": lab_at, "prod_read_at": prod_at, "duplicate_keys": {"lab": dup_l, "prod": dup_p},
           "by_kind": {k: {s: dict(c) for s, c in v.items()} for k, v in summary.items()}}
    with open(os.path.join(a.out, "summary.json"), "w") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print(f"lab read {lab_at}; production read {prod_at}")
    classes = sorted({c for v in summary.values() for cs in v.values() for c in cs})
    print("kind".ljust(12) + "schema".ljust(22) + "".join(c[:14].rjust(15) for c in classes))
    for kind in sorted(summary):
        for s in sorted(summary[kind]):
            c = summary[kind][s]
            print(kind.ljust(12) + s.ljust(22) + "".join(str(c.get(x, "")).rjust(15) for x in classes))
    if dup_l or dup_p:
        print(f"duplicate census keys: lab {len(dup_l)}, production {len(dup_p)} (overloads collapse by identity args)")
    print(f"{len(diffs)} objects not identical -> {os.path.join(a.out, 'diff.tsv')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
