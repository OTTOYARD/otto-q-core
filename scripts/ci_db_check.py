#!/usr/bin/env python3
"""G12 first rung: the one CI step that talks to the live database.

Read-only. Asserts the half of scripts/check-drift.sql that CAN be true today and
that a bad apply would break: EVERY migration file carrying a real version header
has a matching row in supabase_migrations.schema_migrations.

Why only that half: db/checks/0206 measured a floor of 67 applied-with-no-file (the
pre-G18 era) plus 41 name mismatches that no future discipline can clear. Gating on
CLEAN would make this step permanently red, which is how a gate stops being read.

WHAT FAILS THE BUILD, AND WHAT ONLY WARNS. The one hard gate here is the ledger
assertion: a migration file claims a version the ledger does not have. That is a
real defect in this repo and a contributor can act on it. Everything upstream of
it -- secret absent, secret malformed, host unreachable, role cannot read -- is an
ENVIRONMENT precondition, and those warn and skip. A precondition that cannot be
met should not turn a branch red; a build that is red for a reason you cannot act
on is a build you stop reading, which is the failure db/checks/0206 documents.

--------------------------------------------------------------------------------
SECRET HYGIENE -- THIS FILE LEAKED A PASSWORD ONCE. 2026-09-13, run 34786828528:
an unhandled psycopg.OperationalError printed its own message, and that message
embeds the DSN, so the database password appeared in a public build log in
plaintext. GitHub masks a secret only on an EXACT match of the registered value;
the registered value was the whole DSN, so the password ALONE inside a longer
error string was not masked and printed intact.

The rules that follow from that, and they are not optional here:
  * No exception from the driver is ever printed. Not its message, not its repr,
    not a traceback. Only its class name.
  * Anything this script does print goes through scrub() first.
  * The DSN is never echoed, not even partially, not even a "safe" prefix.
  * Structural validation happens BEFORE connecting and reports SHAPE only --
    counts and booleans, never substrings.
--------------------------------------------------------------------------------
"""
import glob
import os
import re
import sys

SENTINELS = {"PENDING", "APPLIED-NO-LEDGER-ROW", "UNVERIFIED-NO-LEDGER-ROW"}

_SECRETS = []


def register_secret(value):
    """Remember a value that must never appear in output."""
    if value and len(value) >= 4:
        _SECRETS.append(value)


def scrub(text):
    """Redact every registered secret from text. Belt and braces."""
    out = str(text)
    for s in sorted(_SECRETS, key=len, reverse=True):
        out = out.replace(s, "***")
    return out


def say(*parts):
    print(scrub(" ".join(str(p) for p in parts)))


def dsn_shape(dsn):
    """Describe the DSN's SHAPE without revealing any of it.

    This is what would have diagnosed the 2026-09-13 failure without the leak.
    """
    problems = []
    if not re.match(r"^postgres(ql)?://", dsn):
        problems.append(
            "does not start with postgres:// or postgresql:// "
            "(a psql command prefix or stray quotes will do this)"
        )
    authority = re.sub(r"^postgres(ql)?://", "", dsn)
    authority = authority.split("/", 1)[0]
    at_count = authority.count("@")
    if at_count == 0:
        problems.append("no '@' between credentials and host")
    elif at_count > 1:
        problems.append(
            "%d '@' characters before the host -- there must be exactly one. "
            "A password that landed on the WRONG SIDE of the '@' looks exactly "
            "like this, and the host then parses as <password>@<host>." % at_count
        )
    if dsn != dsn.strip():
        problems.append("leading or trailing whitespace/newline")
    if any(c in dsn for c in "\r\n"):
        problems.append("contains a newline")
    for ch in ("&", "#", "?", " "):
        userinfo = authority.rsplit("@", 1)[0] if at_count else ""
        if ch in userinfo:
            name = {"&": "&", "#": "#", "?": "?", " ": "a space"}[ch]
            problems.append(
                "credentials contain %s, which must be percent-encoded in a URI" % name
            )
    return problems


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
    dsn = os.environ.get("OTTOQ_DATABASE_URL", "")
    register_secret(dsn)
    register_secret(dsn.strip())
    # Register the password on its own: it is the part that leaked last time,
    # precisely because it is a substring of the registered secret rather than
    # equal to it.
    m = re.match(r"^postgres(?:ql)?://([^@]*)@", dsn.strip())
    if m and ":" in m.group(1):
        register_secret(m.group(1).split(":", 1)[1])

    if not dsn.strip():
        print("::notice::OTTOQ_DATABASE_URL is not set - skipping the database check.")
        return 0

    problems = dsn_shape(dsn)
    if problems:
        # WARN, do not fail. A malformed secret is an environment problem, not a
        # defect in this repo, and only the founder can fix it. Failing here would
        # block every PR on something no contributor can resolve -- and a build
        # that is red for a reason you cannot act on is a build you stop reading,
        # which is the exact failure db/checks/0206 is about.
        print("::warning::OTTOQ_DATABASE_URL is malformed; skipping the database gate.")
        for p in problems:
            print("::warning::  - " + p)
        print("::warning::Expected shape (session pooler, IPv4 - GitHub Actions has no IPv6):")
        print("::warning::  postgresql://postgres.<project-ref>:<password>@aws-<n>-<region>.pooler.supabase.com:5432/postgres")
        print("::warning::No part of the value is shown above, by design.")
        return 0

    files = repo_versions()
    say("repo:", len(files), "migration files carry a real version header")

    try:
        import psycopg
    except Exception as e:
        print("::error::could not import psycopg: " + type(e).__name__)
        return 1

    try:
        with psycopg.connect(dsn.strip(), connect_timeout=20) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT current_user, current_database()")
                user, db = cur.fetchone()
                say("connected as", user, "to", db)

                cur.execute("SELECT version FROM supabase_migrations.schema_migrations")
                ledger = {r[0] for r in cur.fetchall()}
                say("ledger:", len(ledger), "rows")

                cur.execute(
                    "SELECT version, name FROM supabase_migrations.schema_migrations "
                    "ORDER BY version DESC LIMIT 1"
                )
                row = cur.fetchone()
                if row:
                    say("latest applied:", row[0], row[1])
    except Exception as e:
        # NEVER print the exception message: psycopg embeds the DSN in it, and that
        # is exactly how the password leaked on 2026-09-13.
        print("::warning::database connection or query failed: " + type(e).__name__)
        print("::warning::The driver's message is suppressed because it embeds the DSN.")
        print("::warning::Shape validation passed, so this is a live failure: bad password,")
        print("::warning::wrong username (the pooler needs postgres.<project-ref>), unreachable")
        print("::warning::host, or the ledger table is not readable by this role.")
        print("::warning::Skipping the database gate; reachability is an environment")
        print("::warning::precondition, not a defect in this branch.")
        return 0

    missing = sorted(v for v in files if v not in ledger)
    if missing:
        print("::error::Migration files claim versions the ledger does not have.")
        print("::error::Either the file was never applied, or its header version is wrong.")
        for v in missing:
            say("  ", v, files[v])
        return 1

    say("OK: all", len(files), "file versions are present in the ledger.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
