#!/usr/bin/env bash
# ============================================================================
# gen-drift-sql.sh — refresh the manifest block inside scripts/check-drift.sql
# ============================================================================
# The migration FILES are the source of truth. Each one declares, in its header:
#
#     -- migration-version: 20260804153000     (or PENDING, before it is applied)
#     -- migration-name:    p3_short_name
#
# This script reads those two lines out of every db/migrations/*.sql, and
# rewrites the GENERATED MANIFEST block in scripts/check-drift.sql in place.
# Commit check-drift.sql together with the migration.
#
# Usage:   bash scripts/gen-drift-sql.sh
# Safe:    touches nothing but scripts/check-drift.sql. Never contacts the DB.
# Exit 1:  a migration file is missing its header lines (that file would be
#          invisible to the drift check, which is exactly the failure this
#          whole repo exists to prevent).
# ============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIG_DIR="$REPO/db/migrations"
TARGET="$REPO/scripts/check-drift.sql"

BEGIN='-- >>> BEGIN GENERATED MANIFEST'
END='-- <<< END GENERATED MANIFEST'

[ -f "$TARGET" ] || { echo "FATAL: $TARGET not found" >&2; exit 1; }

sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }

rows=()
missing=()

shopt -s nullglob
for f in "$MIG_DIR"/*.sql; do
  base="$(basename "$f")"
  # The template is documentation, not a migration. Skip it.
  case "$base" in *_EXAMPLE_*|*EXAMPLE*) continue ;; esac

  ver="$(grep -m1 -E '^--[[:space:]]*migration-version:' "$f" \
         | sed -E 's/^--[[:space:]]*migration-version:[[:space:]]*//' \
         | tr -d '[:space:]' || true)"
  nam="$(grep -m1 -E '^--[[:space:]]*migration-name:' "$f" \
         | sed -E 's/^--[[:space:]]*migration-name:[[:space:]]*//' \
         | sed -E 's/[[:space:]]+$//' || true)"

  if [ -z "$ver" ] || [ -z "$nam" ]; then
    missing+=("$base")
    continue
  fi
  rows+=("    ('$(sql_escape "$ver")'::text, '$(sql_escape "$nam")'::text, '$(sql_escape "$base")'::text)")
done
shopt -u nullglob

if [ "${#missing[@]}" -gt 0 ]; then
  echo "FATAL: these migration files have no 'migration-version:' / 'migration-name:' header:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "" >&2
  echo "Add both lines (use PENDING as the version until the file is applied)." >&2
  echo "Nothing was written. See db/migrations/README.md." >&2
  exit 1
fi

# Build the replacement block.
block="$BEGIN — do not edit by hand; run scripts/gen-drift-sql.sh"$'\n'
if [ "${#rows[@]}" -eq 0 ]; then
  block+="    (NULL::text, NULL::text, NULL::text)  -- placeholder: repo holds no migration files yet"$'\n'
else
  for i in "${!rows[@]}"; do
    if [ "$i" -lt $(( ${#rows[@]} - 1 )) ]; then
      block+="${rows[$i]},"$'\n'
    else
      block+="${rows[$i]}"$'\n'
    fi
  done
fi
block+="$END"

# Splice it in, replacing everything between the markers inclusive.
tmp="$(mktemp)"
BLOCK="$block" awk -v b="$BEGIN" -v e="$END" '
  index($0, b) == 1 { print ENVIRON["BLOCK"]; skipping = 1; next }
  index($0, e) == 1 { skipping = 0; next }
  !skipping { print }
' "$TARGET" > "$tmp"

if ! grep -q -- "$BEGIN" "$tmp"; then
  rm -f "$tmp"
  echo "FATAL: marker '$BEGIN' not found in $TARGET — refusing to write." >&2
  exit 1
fi

mv "$tmp" "$TARGET"
echo "check-drift.sql manifest refreshed: ${#rows[@]} migration file(s)."
[ "${#rows[@]}" -gt 0 ] && printf '  %s\n' "${rows[@]}" | sed 's/^    //'
echo ""
echo "Next: commit scripts/check-drift.sql, then run it against the live database."
