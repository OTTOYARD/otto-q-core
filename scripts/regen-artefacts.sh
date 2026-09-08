#!/usr/bin/env bash
# Regenerate every artefact derived from db/migrations/*.sql.
#
# There are two of them and they are checked by tests/test_migration_hygiene.py,
# which runs on the pytest gate in CI. Both are derived from the migration
# FILES, not from the database, so they go stale the moment a new migration file
# is committed -- including a PENDING draft that has not been applied and may
# never be.
#
# That is exactly how CI went red three times on 2026-09-08: 0219 was committed
# as a draft, APPLYING.md's "refresh the drift manifest" step sits at apply time
# (step 6), and nothing said to run it when the file was merely written. Run
# this whenever db/migrations/ changes -- adding a file, renaming one, or
# replacing PENDING with the version the database assigned.
set -euo pipefail
cd "$(dirname "$0")/.."
bash   scripts/gen-drift-sql.sh
python3 scripts/gen-migration-index.py
echo
echo "Both artefacts regenerated. git diff to see what moved; commit it with the migration."
