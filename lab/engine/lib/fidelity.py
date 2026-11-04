#!/usr/bin/env python3
"""Measure how faithfully the lab database matches production, object by object.

Nothing here connects to production. Production is read through a read-only
channel (on 2026-11-03: the Supabase MCP tool's execute_sql), so this script
PRINTS the production queries and the person or agent with that channel runs
them and saves the answers under reports/fidelity_<date>/.

  fidelity.py lab        --dsn DSN --out DIR   lab side: lab_objects.tsv (every object,
                                               its identity and content hashes), lab_tokens.txt
  fidelity.py prod-sql   KIND --out DIR        print the production query for KIND:
                                               aggregate | routines | relations | types
  fidelity.py summarize  --out DIR             print the per-schema tables the report quotes

How a comparison stays small. Both sides run the same object census
(sql/fidelity_objects.sql). Each lab object becomes a 20-character token:
8 base64 characters of md5(kind:schema:identity) and three 4-character base64
digests of its content hashes (routines: body, header, comment-blind body;
tables: columns in order, columns by name; views: columns, definition;
triggers: definition). The lab's tokens travel inside the production query, so
production classifies its own objects against them and returns only counts and
the names of what differs or is missing. No body or row leaves production.
Collision odds: 48-bit identities over ~2,000 objects ~ 1e-8; 24-bit content
digests ~ 6e-8 per compared pair.
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OBJECTS_SQL = os.path.join(HERE, "..", "sql", "fidelity_objects.sql")

TOKEN = ("encode(substring(decode(md5(kind || ':' || s || ':' || ident), 'hex') FROM 1 FOR 6), 'base64') || "
         "encode(substring(decode(md5(h1), 'hex') FROM 1 FOR 3), 'base64') || "
         "encode(substring(decode(md5(h2), 'hex') FROM 1 FOR 3), 'base64') || "
         "encode(substring(decode(md5(h3), 'hex') FROM 1 FOR 3), 'base64')")


def objects_cte():
    text = open(OBJECTS_SQL, encoding="utf-8").read()
    lines = [ln.strip() for ln in text.splitlines() if ln.strip() and not ln.strip().startswith("--")]
    return re.sub(r"\s+", " ", " ".join(lines))


def psql(dsn, sql):
    p = subprocess.run(["psql", "-X", "-At", "-F", "\t", "-v", "ON_ERROR_STOP=1", dsn],
                       input=sql, capture_output=True, text=True, check=True)
    return p.stdout


def cmd_lab(a):
    os.makedirs(a.out, exist_ok=True)
    cte = objects_cte()
    rows = psql(a.dsn, cte + " SELECT kind, s, ident, encode(substring(decode(md5(kind || ':' || s || ':' || ident), "
                "'hex') FROM 1 FOR 6), 'base64'), h1, h2, h3, now() FROM o ORDER BY kind, s, ident COLLATE \"C\";")
    with open(os.path.join(a.out, "lab_objects.tsv"), "w", encoding="utf-8") as fh:
        fh.write("kind\tschema\tident\tid_token\th1\th2\th3\n")
        read_at = ""
        for ln in rows.splitlines():
            parts = ln.split("\t")
            read_at = parts[7]
            fh.write("\t".join(parts[:7]) + "\n")
    toks = psql(a.dsn, cte + f" SELECT kind, count(*), string_agg({TOKEN}, '' ORDER BY s, ident COLLATE \"C\") "
                "FROM o GROUP BY kind ORDER BY kind;")
    with open(os.path.join(a.out, "lab_tokens.txt"), "w", encoding="utf-8") as fh:
        fh.write(f"# lab tokens, read {read_at}\n")
        fh.write(toks)
    print(f"lab read at {read_at}; objects -> {a.out}/lab_objects.tsv; tokens -> {a.out}/lab_tokens.txt")


def lab_tokens(out, kinds):
    got = {}
    for ln in open(os.path.join(out, "lab_tokens.txt"), encoding="utf-8"):
        if ln.startswith("#"):
            continue
        kind, _n, tok = ln.rstrip("\n").split("\t")
        got[kind] = tok
    return "".join(got.get(k, "") for k in kinds)


def cmd_prod_sql(a):
    cte = objects_cte()
    if a.kind == "aggregate":
        print(cte + " SELECT now() AS read_at, current_setting('search_path') AS sp, string_agg(kind || ' ' || s || "
              "' ' || n || ' ' || h, E'\\n' ORDER BY kind, s) AS blob FROM (SELECT kind, s, count(*) AS n, "
              "left(md5(string_agg(ident || '|' || h1 || '|' || h2, E'\\n' ORDER BY ident COLLATE \"C\")), 12) AS h "
              "FROM o GROUP BY 1, 2) x;")
        return
    if a.kind == "routines":
        tok = lab_tokens(a.out, ["routine"])
        print(cte.replace("WITH o AS (", "WITH o0 AS (", 1) + ", o AS (SELECT * FROM o0 WHERE kind = 'routine'), "
              "p AS (SELECT s, split_part(ident, '(', 1) AS nm, "
              "substr(" + TOKEN + ", 1, 8) AS i, substr(" + TOKEN + ", 9, 4) AS a, substr(" + TOKEN + ", 13, 4) AS b, "
              "substr(" + TOKEN + ", 17, 4) AS c FROM o), "
              f"t AS (SELECT '{tok}'::text AS x), "
              "l AS (SELECT substr(x, 1 + 20 * (g - 1), 8) AS i, substr(x, 9 + 20 * (g - 1), 4) AS a, "
              "substr(x, 13 + 20 * (g - 1), 4) AS b, substr(x, 17 + 20 * (g - 1), 4) AS c "
              "FROM t, generate_series(1, length(x) / 20) g), "
              "j AS (SELECT p.s, p.nm, CASE WHEN l.i IS NULL THEN 'missing_in_lab' WHEN p.a = l.a AND p.b = l.b THEN "
              "'identical' WHEN p.a = l.a THEN 'header_only' WHEN p.c = l.c THEN 'comments_only' ELSE 'body_different' "
              "END AS cls FROM p LEFT JOIN l ON l.i = p.i) "
              "SELECT now() AS read_at, (SELECT count(*) FROM l) AS lab_n, (SELECT count(*) FROM p) AS prod_n, "
              "(SELECT string_agg(l.i, ',') FROM l WHERE l.i NOT IN (SELECT i FROM p)) AS extra_tokens, "
              "(SELECT string_agg(s || ':' || cls || ':' || n, ' ' ORDER BY s, cls) FROM (SELECT s, cls, count(*) AS n "
              "FROM j GROUP BY 1, 2) z) AS counts, (SELECT string_agg(s || '|' || cls || '|' || names, E'\\n' ORDER BY "
              "s, cls) FROM (SELECT s, cls, string_agg(DISTINCT nm, ',' ORDER BY nm) AS names FROM j WHERE cls <> "
              "'identical' GROUP BY 1, 2) z) AS names;")
        return
    if a.kind == "relations":
        tok = lab_tokens(a.out, ["table", "view", "trigger"])
        print(cte.replace("WITH o AS (", "WITH o0 AS (", 1) + ", o AS (SELECT * FROM o0 WHERE kind IN "
              "('table', 'view', 'trigger')), p AS (SELECT kind, s, ident, substr(" + TOKEN + ", 1, 8) AS i, "
              "substr(" + TOKEN + ", 9, 4) AS a, substr(" + TOKEN + ", 13, 4) AS b FROM o), "
              f"t AS (SELECT '{tok}'::text AS x), "
              "l AS (SELECT substr(x, 1 + 20 * (g - 1), 8) AS i, substr(x, 9 + 20 * (g - 1), 4) AS a, "
              "substr(x, 13 + 20 * (g - 1), 4) AS b FROM t, generate_series(1, length(x) / 20) g), "
              "j AS (SELECT p.kind, p.s, p.ident, CASE WHEN l.i IS NULL THEN 'missing_in_lab' WHEN p.a = l.a AND "
              "p.b = l.b THEN 'identical' WHEN p.kind = 'table' AND p.b = l.b THEN 'column_order_only' WHEN p.kind = "
              "'view' AND p.a = l.a THEN 'definition_only' ELSE 'columns_different' END AS cls FROM p LEFT JOIN l ON "
              "l.i = p.i) SELECT now() AS read_at, (SELECT count(*) FROM l) AS lab_n, (SELECT count(*) FROM p) AS "
              "prod_n, (SELECT string_agg(l.i, ',') FROM l WHERE l.i NOT IN (SELECT i FROM p)) AS extra_tokens, "
              "(SELECT string_agg(kind || ':' || s || ':' || cls || ':' || n, ' ' ORDER BY kind, s, cls) FROM (SELECT "
              "kind, s, cls, count(*) AS n FROM j GROUP BY 1, 2, 3) z) AS counts, (SELECT string_agg(kind || '|' || s "
              "|| '|' || cls || '|' || names, E'\\n' ORDER BY kind, s, cls) FROM (SELECT kind, s, cls, "
              "string_agg(ident, ',' ORDER BY ident) AS names FROM j WHERE cls <> 'identical' AND kind <> 'trigger' "
              "GROUP BY 1, 2, 3) z) AS names, (SELECT string_agg(tb || '(' || n || ')', ',' ORDER BY tb) FROM (SELECT "
              "s || '.' || split_part(ident, '.', 1) AS tb, count(*) AS n FROM j WHERE kind = 'trigger' AND cls <> "
              "'identical' GROUP BY 1) z) AS trigger_gaps_by_table;")
        return
    if a.kind == "types":
        tok = lab_tokens(a.out, ["type"])
        # the type rows carry 20-char tokens like the others; only identity + h1 are compared
        print(cte.replace("WITH o AS (", "WITH o0 AS (", 1) + ", o AS (SELECT * FROM o0 WHERE kind = 'type'), "
              "p AS (SELECT ident, substr(" + TOKEN + ", 1, 8) AS i, substr(" + TOKEN + ", 9, 4) AS a FROM o), "
              f"l AS (SELECT substr(x, 1 + 20 * (g - 1), 8) AS i, substr(x, 9 + 20 * (g - 1), 4) AS a FROM (SELECT "
              f"'{tok}'::text AS x) t, generate_series(1, length(x) / 20) g) "
              "SELECT now() AS read_at, count(*) FILTER (WHERE l.i IS NOT NULL AND l.a = p.a) AS identical, "
              "string_agg(p.ident, ',') FILTER (WHERE l.i IS NOT NULL AND l.a <> p.a) AS different, "
              "string_agg(p.ident, ',') FILTER (WHERE l.i IS NULL) AS missing_in_lab, (SELECT count(*) FROM l WHERE "
              "l.i NOT IN (SELECT i FROM p)) AS extra_in_lab FROM p LEFT JOIN l ON l.i = p.i;")
        return
    sys.exit(f"unknown kind {a.kind}")


def parse_classified(path):
    meta, lists = {}, []
    for ln in open(path, encoding="utf-8"):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        if "\t" in ln:
            k, v = ln.split("\t", 1)
            meta[k] = v
        else:
            lists.append(ln.split("|"))
    return meta, lists


def cmd_summarize(a):
    meta, lists = parse_classified(os.path.join(a.out, "prod_routines_classified.txt"))
    counts = {}
    for item in meta["counts"].split():
        s, cls, n = item.split(":")
        counts.setdefault(s, {})[cls] = int(n)
    extra = len([t for t in meta.get("extra_tokens", "").split(",") if t])
    lab_rows = [ln.split("\t") for ln in open(os.path.join(a.out, "lab_objects.tsv"), encoding="utf-8")][1:]
    extra_by_schema = {}
    toks = set(meta.get("extra_tokens", "").split(","))
    for r in lab_rows:
        if r[0] == "routine" and r[3] in toks:
            extra_by_schema[r[1]] = extra_by_schema.get(r[1], 0) + 1
    print("| schema | production | identical | body differs (code) | body differs (comments only) | header only | "
          "missing in lab | extra in lab |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")
    tot = {}
    for s in ("public", "ottoq", "twin"):
        c = counts.get(s, {})
        prod = sum(c.values())
        row = [prod, c.get("identical", 0), c.get("body_different", 0), c.get("comments_only", 0),
               c.get("header_only", 0), c.get("missing_in_lab", 0), extra_by_schema.get(s, 0)]
        tot = {i: tot.get(i, 0) + v for i, v in enumerate(row)}
        print(f"| {s} | " + " | ".join(f"{v:,}" for v in row) + " |")
    print("| **all** | " + " | ".join(f"**{tot[i]:,}**" for i in range(7)) + " |")
    assert tot[6] == extra, (tot[6], extra)


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("lab")
    p.add_argument("--dsn", required=True)
    p.add_argument("--out", required=True)
    p = sp.add_parser("prod-sql")
    p.add_argument("kind")
    p.add_argument("--out", required=True)
    p = sp.add_parser("summarize")
    p.add_argument("--out", required=True)
    a = ap.parse_args()
    {"lab": cmd_lab, "prod-sql": cmd_prod_sql, "summarize": cmd_summarize}[a.cmd](a)


if __name__ == "__main__":
    main()
