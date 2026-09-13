#!/usr/bin/env python3
"""G12 first rung: the one CI step that talks to the live database.

Read-only. It asserts the half of scripts/check-drift.sql that CAN be true today
and that a bad apply would break: EVERY migration file carrying a real version
header has a matching row in supabase_migrations.schema_migrations.

Why only that half. db/checks/0206 measured the other two sections and both have a
known non-zero floor that no future discipline can clear: 67 migrations were applied
between 2026-08-10 and 08-16 with no file ever written (the pre-G18 era), and 41
file headers carry names the ledger spells differently. Gating on CLEAN would make
this step permanently red, which is how a gate stops being read -- the exact defect
0206 is about. So this asserts the direction that is currently at zero and that a
mistake would move: file exists -> ledger row exists.

Soft-skips when OTTOQ_DATABASE_URL is absent so secretless PRs still pass.
"""
import os
import re
import sys
import glob

SENTINELS = {"PENDING", "APPLIED-NO-LEDGER-ROW", "UNVERIFIED-NO-LEDGER-ROW"}


def repo_versions():
    out = {}
    for path in sorted(glob.glob("db/migrations/*.sql")):
        if "EXAMPLE" in os.path.basename(path):
            continue
        head = open(path, errors="replace").read(4000)
        mv = re.search(r"^--\s*migration-version:\s*(\S+)", head, re.M)
        if not mv:
            continue
        ver = mv.group(1)
        if ver in SENTINELS:
            continue
        out[ver] = os.path.basename(path)
        also = re.search(r"^--\s*migration-also-covers:\s*(.+)$", head, re.M)
        if also:
            for v in also.group(1).split(","):
                v = v.strip()
                if v and v not in SENTINELS:
                    out[v] = os.path.basename(path)
    return out


def main():
    dsn = os.environ.get("OTTOQ_DATABASE_URL", "").strip()
    if not dsn:
        print("::notice::OTTOQ_DATABASE_URL is not set - skipping the database check.")
        return 0

    import psycopg

    files = repo_versions()
    print(f"repo: {len(files)} migration files carry a real version header")

    with psycopg.connect(dsn, connect_timeout=20) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT current_user, current_database(), version()")
            user, db, ver = cur.fetchone()
            print(f"connected as {user} to {db}")
            print(f"server: {ver.split(',')[0]}")

            cur.execute("SELECT version FROM supabase_migrations.schema_migrations")
            ledger = {r[0] for r in cur.fetchall()}
            print(f"ledger: {len(ledger)} rows")

            cur.execute(
                "SELECT version, name FROM supabase_migrations.schema_migrations "
                "ORDER BY version DESC LIMIT 1"
            )
            row = cur.fetchone()
            if row:
                print(f"latest applied: {row[0]}  {row[1]}")

    missing = sorted(v for v in files if v not in ledger)
    if missing:
        print("")
        print("::error::Migration files claim versions the ledger does not have.")
        print("::error::Either the file was never applied, or its header version is wrong.")
        for v in missing:
            print(f"  {v}  {files[v]}")
        return 1

    print("")
    print(f"OK: all {len(files)} file versions are present in the ledger.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
