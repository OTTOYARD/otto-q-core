#!/usr/bin/env python3
"""Is each committed migration file the SQL production actually applied?

  compare_ledger_text.py REPO DIGEST OUT_TSV

DIGEST is production's ledger, one line per row with statements: "version length
md5[:10] md5(trimmed)[:10]", from this read-only query:

  SELECT version || ' ' || length(statements[1]) || ' ' || left(md5(statements[1]), 10) || ' ' ||
         left(md5(btrim(statements[1], E' \\n\\t\\r')), 10)
    FROM supabase_migrations.schema_migrations
   WHERE version >= '20260804140958' AND statements IS NOT NULL;

(every such row holds exactly one statement: 670 rows on 2026-11-03; 46 more rows
in that range have statements = NULL and cannot be compared.)

A file "matches" if its text, or its text with the version header put back to
`PENDING` (the house rule writes the real version into the header only AFTER the
apply), hashes to the ledger's statement. Anything else is a file that is not, byte
for byte, what ran.
"""
import hashlib
import os
import re
import sys


def h(x):
    return hashlib.md5(x.encode("utf-8")).hexdigest()[:10]


def main():
    repo, digest, out = sys.argv[1:4]
    prod = {}
    for ln in open(digest, encoding="utf-8"):
        if ln.strip() and not ln.startswith("#"):
            v, n, a, b = ln.split()
            prod[v] = (int(n), a, b)
    mig = os.path.join(repo, "db", "migrations")
    rows, counts = [], {}
    for f in sorted(os.listdir(mig)):
        if not f.endswith(".sql") or "EXAMPLE" in f:
            continue
        t = open(os.path.join(mig, f), encoding="utf-8").read()
        m = re.search(r"--\s*migration-version:\s*(\S+)", t)
        v = m.group(1) if m else ""
        if not re.fullmatch(r"\d{14}", v):
            continue
        if v not in prod:
            res = "ledger_row_has_no_statements"
            delta = ""
        else:
            n, a, b = prod[v]
            pend = re.sub(r"(--\s*migration-version:\s*)\d{14}", r"\g<1>PENDING", t, count=1)
            if h(t) == a or h(t.strip(" \n\t\r")) == b:
                res = "identical"
            elif h(pend) == a or h(pend.strip(" \n\t\r")) == b:
                res = "identical_but_version_header"
            else:
                res = "different"
            delta = str(len(t) - n)
        counts[res] = counts.get(res, 0) + 1
        rows.append((f, v, res, delta))
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("file\tversion\tvs_ledger_statement\tfile_minus_statement_chars\n")
        for r in rows:
            fh.write("\t".join(r) + "\n")
    print(counts)


if __name__ == "__main__":
    main()
