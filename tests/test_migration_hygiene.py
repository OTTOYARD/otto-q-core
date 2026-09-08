"""
The three things APPLYING.md requires of a migration file, tested.

WHY THIS FILE EXISTS. On 2026-09-08 the drift check was found to have been blind
since migration 0024 -- 193 migrations. Two separate failures kept it that way,
and neither was visible to CI because CI never ran anything that touched
db/migrations at all:

  1. 93 of 215 files had no `-- migration-version:` header, and
     scripts/gen-drift-sql.sh exits 1 if ANY file is missing one, so the
     manifest inside scripts/check-drift.sql could not be regenerated and still
     ended at 0023.
  2. 98 of the files that DID have a header carried round-number timestamps
     (20260819031500, 20260830000000, ...) that appear nowhere in
     supabase_migrations.schema_migrations. They were written to satisfy the
     format rather than read from the ledger.

Both are now fixed. These tests exist so neither can come back quietly. They
need no database: every check here is a property of the committed files, which
is exactly the class of failure that went unnoticed for 193 migrations.

What they deliberately do NOT check: whether a migration is correct, or whether
the version in a header is the RIGHT ledger version. Only the database knows
that, and `scripts/check-drift.sql` is where it is asked. See task G18.
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIG = ROOT / "db" / "migrations"

#: The three values that mean "there is no ledger version to compare against",
#: each meaning something different. Keeping them apart is the point: calling an
#: applied migration PENDING would be a comfortable lie.
NO_VERSION = {
    "PENDING",                    # written, deliberately not yet applied
    "APPLIED-NO-LEDGER-ROW",      # applied via a path that writes no ledger row
    "UNVERIFIED-NO-LEDGER-ROW",   # no ledger row AND no APPLIED note; state unknown
}
TIMESTAMP = re.compile(r"^\d{12,14}$")


def _migration_files():
    return sorted(p for p in MIG.glob("*.sql") if "EXAMPLE" not in p.name)


def test_there_are_migrations_to_check():
    """A glob that silently matches nothing turns every test below into a pass."""
    files = _migration_files()
    assert len(files) > 200, f"only {len(files)} migration files found — is MIG wrong?"


def test_every_migration_declares_a_version_and_a_name():
    """The header scripts/gen-drift-sql.sh needs. Missing it on ONE file blinds
    the whole drift check, which is how 193 migrations went unwatched."""
    missing = []
    for f in _migration_files():
        head = f.read_text(errors="replace").split("\n", 4)[:4]
        if not any(l.startswith("-- migration-version:") for l in head):
            missing.append(f.name + " (no version)")
        elif not any(l.startswith("-- migration-name:") for l in head):
            missing.append(f.name + " (no name)")
    assert not missing, "migration files with no header:\n  " + "\n  ".join(missing)


def test_every_version_is_a_real_timestamp_or_a_declared_non_version():
    """Round-number timestamps like 20260830000000 are the shape of a value that
    was invented to satisfy the format. A real ledger version is a wall-clock
    stamp to the second; 98 files carried invented ones until 2026-09-08."""
    bad = []
    for f in _migration_files():
        first = f.read_text(errors="replace").split("\n", 1)[0]
        ver = first.split(":", 1)[1].strip()
        if ver in NO_VERSION:
            continue
        if not TIMESTAMP.match(ver):
            bad.append(f"{f.name}: {ver!r} is neither a timestamp nor one of {sorted(NO_VERSION)}")
            continue
        # A ledger version is minute-and-second precise. Six trailing zeros is a
        # human rounding a number, not a database recording an event.
        if ver.endswith("0000") and len(ver) == 14:
            bad.append(f"{f.name}: {ver} ends in 0000 — that is a hand-written timestamp, "
                       "not a ledger version. Resolve it from "
                       "supabase_migrations.schema_migrations by name.")
    assert not bad, "\n  ".join([""] + bad)


def test_every_declared_name_is_well_formed_and_unique():
    """The declared name becomes a SQL string literal in the generated manifest
    and the join key Section C of the drift check compares against the ledger.
    It must therefore be a single bare identifier and no two files may claim the
    same one.

    NOTE ON WHAT THIS DOES NOT CHECK, because the first version of this test got
    it wrong. It does NOT require the declared name to equal the file stem.
    `0160r_repair_the_anchor_must_be_unique_not_merely_present.sql` legitimately
    declares `repair_0160_the_anchor_must_be_unique_not_merely_present`, because
    that is the name the LEDGER holds, and matching the ledger is the entire
    purpose of the field. A file-only test cannot check name-against-ledger --
    only `scripts/check-drift.sql` Section C can, and it does. Asserting the
    stem instead would have been checking a convention the repo does not have.
    """
    seen, bad = {}, []
    for f in _migration_files():
        declared = None
        for l in f.read_text(errors="replace").split("\n", 4)[:4]:
            if l.startswith("-- migration-name:"):
                declared = l.split(":", 1)[1].strip()
        if not declared:
            bad.append(f"{f.name}: no name declared")
            continue
        if not re.fullmatch(r"[A-Za-z0-9_]+", declared):
            bad.append(f"{f.name}: name {declared!r} is not a bare identifier")
        if declared in seen:
            bad.append(f"{f.name}: name {declared!r} is already claimed by {seen[declared]}")
        seen[declared] = f.name
    assert not bad, "\n  ".join([""] + bad)


def _generator_is_idempotent(script, target):
    """Run a generator and assert it changed nothing. If it did, the committed
    artefact is stale — which is the state check-drift.sql was in for 193
    migrations."""
    before = (ROOT / target).read_text()
    r = subprocess.run(script, cwd=ROOT, capture_output=True, text=True)
    after = (ROOT / target).read_text()
    if after != before:
        (ROOT / target).write_text(before)  # leave the tree as we found it
    assert r.returncode == 0, f"{script} failed:\n{r.stderr}"
    assert after == before, (
        f"{target} is stale — running {script} changes it. "
        f"Run it and commit the result."
    )


def test_the_drift_manifest_matches_the_migration_files():
    _generator_is_idempotent(["bash", "scripts/gen-drift-sql.sh"], "scripts/check-drift.sql")


def test_the_migration_log_index_matches_the_migration_files():
    _generator_is_idempotent(["python3", "scripts/gen-migration-index.py"], "MIGRATION_LOG.md")
