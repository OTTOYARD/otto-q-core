#!/usr/bin/env python3
"""Load the twin depot's reference data (lib/export_reference_data.py) into the lab.

Each row arrives as its composite text form and is parsed back with the lab table's own row
type, under the same output settings it was read with, so values are exact. Triggers (and with
them the FK triggers) are off for the load (`session_replication_role = replica`): this is a copy
of rows that already passed production's checks, not new writes for the engine to react to.
Generated columns are recomputed by the lab; identity columns keep production's values.

After the load, two run stamps that point at runs the lab does not hold are cleared (registry
class 'stamp': the row is permanent, only the stamp may dangle), and every foreign key is
checked for rows whose parent was not copied; those are reported, not deleted.

    python -I load_reference_data.py --data DIR --dsn DSN --out REPORT_PREFIX
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

import psycopg

SESSION = [
    "SET session_replication_role = replica",
    "SET extra_float_digits = 3",
    "SET DateStyle = 'ISO, MDY'",
    "SET IntervalStyle = 'postgres'",
    "SET bytea_output = 'hex'",
    "SET TimeZone = 'UTC'",
    "SET search_path = ''",
]

# (table, column, why): run stamps on permanent rows; the runs are not in the lab.
DANGLING_STAMPS = [
    ("public.vehicles", "owning_sim_run_id", "registry class 'stamp': the fleet row is permanent, the run is not copied"),
]


def columns(conn, table: str) -> tuple[list[str], bool]:
    with conn.cursor() as c:
        c.execute("""select a.attname, a.attgenerated <> '' as generated, a.attidentity = 'a' as always
                       from pg_attribute a where a.attrelid = %s::regclass and a.attnum > 0 and not a.attisdropped
                      order by a.attnum""", (table,))
        rows = c.fetchall()
    cols = [r[0] for r in rows if not r[1]]
    always = any(r[2] for r in rows)
    return cols, always


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--dsn", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    files = sorted(f for f in glob.glob(os.path.join(a.data, "*.json")) if not f.endswith("manifest.json"))
    report = {"tables": [], "stamps_cleared": [], "fk_orphans": []}
    with psycopg.connect(a.dsn, autocommit=False) as conn:
        with conn.cursor() as c:
            for s in SESSION:
                c.execute(s)
        for f in files:
            doc = json.load(open(f, encoding="utf-8"))
            table = doc["table"]
            cols, always = columns(conn, table)
            qcols = ", ".join(psycopg.sql.Identifier(x).as_string(conn) for x in cols)
            sel = ", ".join(f"(x).{psycopg.sql.Identifier(x).as_string(conn)}" for x in cols)
            override = " OVERRIDING SYSTEM VALUE" if always else ""
            with conn.cursor() as c:
                c.execute(f"SELECT count(*) FROM {table}")
                before = c.fetchone()[0]
                if before:
                    raise SystemExit(f"refusing: {table} already holds {before} rows")
                c.execute(f"INSERT INTO {table} ({qcols}){override} SELECT {sel} "
                          f"FROM (SELECT r::{table} AS x FROM unnest(%s::text[]) r) q", (doc["rows"],))
                n = c.rowcount
            if n != doc["count"]:
                raise SystemExit(f"{table}: inserted {n} of {doc['count']} rows")
            report["tables"].append({"table": table, "rows": n})
        for table, col, why in DANGLING_STAMPS:
            with conn.cursor() as c:
                c.execute(f"UPDATE {table} SET {col} = NULL WHERE {col} IS NOT NULL")
                report["stamps_cleared"].append({"table": table, "column": col, "rows": c.rowcount, "why": why})
        # every FK whose child holds rows: count children whose parent row is absent
        with conn.cursor() as c:
            c.execute("""
              select co.conname, co.conrelid::regclass::text, co.confrelid::regclass::text,
                     (select array_agg(a.attname order by k.ord) from unnest(co.conkey) with ordinality k(n, ord)
                        join pg_attribute a on a.attrelid = co.conrelid and a.attnum = k.n),
                     (select array_agg(a.attname order by k.ord) from unnest(co.confkey) with ordinality k(n, ord)
                        join pg_attribute a on a.attrelid = co.confrelid and a.attnum = k.n)
                from pg_constraint co join pg_class c on c.oid = co.conrelid join pg_namespace n on n.oid = c.relnamespace
               where co.contype = 'f' and n.nspname in ('public', 'ottoq', 'twin')""")
            fks = c.fetchall()
        for name, child, parent, ccols, pcols in fks:
            with conn.cursor() as c:
                c.execute(f"select exists (select 1 from {child} limit 1)")
                if not c.fetchone()[0]:
                    continue
                notnull = " and ".join(f"ch.{psycopg.sql.Identifier(x).as_string(conn)} is not null" for x in ccols)
                join = " and ".join(f"p.{psycopg.sql.Identifier(y).as_string(conn)} = ch.{psycopg.sql.Identifier(x).as_string(conn)}"
                                    for x, y in zip(ccols, pcols))
                c.execute(f"select count(*) from {child} ch where {notnull} and not exists (select 1 from {parent} p where {join})")
                orphans = c.fetchone()[0]
            if orphans:
                report["fk_orphans"].append({"constraint": name, "child": child, "parent": parent,
                                             "columns": ccols, "rows": orphans})
        conn.commit()
    with open(a.out + ".json", "w") as fh:
        json.dump(report, fh, indent=1)
        fh.write("\n")
    print(f"loaded {sum(t['rows'] for t in report['tables'])} rows into {len(report['tables'])} tables; "
          f"stamps cleared {sum(s['rows'] for s in report['stamps_cleared'])}; FK orphans "
          f"{sum(o['rows'] for o in report['fk_orphans'])} rows in {len(report['fk_orphans'])} constraints")
    for o in report["fk_orphans"]:
        print(f"  orphan: {o['child']}({','.join(o['columns'])}) -> {o['parent']}: {o['rows']} rows ({o['constraint']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
