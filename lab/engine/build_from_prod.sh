#!/usr/bin/env bash
# lab/engine/build_from_prod.sh -- build the OTTO-Q research lab's engine database from an
# export of PRODUCTION's catalog (lib/export_prod.py), i.e. from what ran, not from what the
# repository's migration files say (G509). Never writes to production: the export is read
# through the Management API's read-only endpoint, before this script runs.
#
#   lab/engine/build_from_prod.sh EXPORT_DIR [DATA_DIR]
#
#   EXPORT_DIR  a directory written by lib/export_prod.py (schema, ledger versions, cron jobs)
#   DATA_DIR    optional: a directory written by lib/export_reference_data.py (the twin
#               depot's reference data); loaded with triggers off, after the schema
#
# Steps (each step's result lands in lab/engine/reports/):
#   0. the lab server is up (lib/lab_server.sh; cron.launch_active_jobs must be off)
#   1. drops and recreates the lab database (production's locale)
#   2. 00_roles.sql, 10_supabase_shims.sql; then the shims' default privileges are cleared,
#      so the export's objects get production's explicit ACLs and nothing else
#   3. the export, phase by phase, to a fixpoint (lib/load_export.py)
#   4. the reference data, if given (lib/load_reference_data.py)
#   5. 31_post_build_prod.sql: every cron job inactive; lab.build_info records the export
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
EXPORT_DIR="$(cd "${1:?usage: build_from_prod.sh EXPORT_DIR [DATA_DIR]}" && pwd)"
DATA_DIR="${2:-}"
STAMP="$(date -u +%Y-%m-%d)"
OUT="$HERE/reports/build_${STAMP}_prod"

source "$HERE/lib/lab_server.sh"
DSN="host=$LAB_HOST port=$LAB_PORT dbname=$LAB_DB user=postgres"

# ---- 1. database -------------------------------------------------------------
echo "== (re)creating database $LAB_DB"
"${PSQL[@]}" -d postgres -c "DROP DATABASE IF EXISTS $LAB_DB WITH (FORCE)"
# Production's database: UTF8, ICU locale en-US (collation version 153.121),
# LC_COLLATE/LC_CTYPE en_US.UTF-8 (export manifest: production.database_locale).
"${PSQL[@]}" -d postgres -c "CREATE DATABASE $LAB_DB TEMPLATE template0 ENCODING 'UTF8' LOCALE_PROVIDER icu ICU_LOCALE 'en-US' LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8'"

# ---- 2. roles and Supabase shims -------------------------------------------------
echo "== roles, Supabase shims"
"${PSQL[@]}" -d postgres -f "$HERE/sql/00_roles.sql"
"${PSQL[@]}" -d "$LAB_DB" -f "$HERE/sql/10_supabase_shims.sql"
# The shims install a guess at postgres' default privileges in public. Production's are in the
# export (phase 23) and go on last; until then none may apply, or every object the export
# creates would carry grants production's does not.
"${PSQL[@]}" -d "$LAB_DB" -c "
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES    FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;"
[ "$("${PSQL[@]}" -d "$LAB_DB" -Atc "select count(*) from pg_default_acl")" = 0 ] \
  || { echo "refusing to load: default privileges still in force" >&2; exit 1; }

# ---- 3. the export -------------------------------------------------------------
echo "== production export $EXPORT_DIR"
set +e
"${PY[@]}" "$HERE/lib/load_export.py" --export "$EXPORT_DIR" --dsn "$DSN" --out "${OUT}_schema" | tee "${OUT}_schema.log" | head -60
set -e

# ---- 4. reference data ----------------------------------------------------------
if [ -n "$DATA_DIR" ]; then
  echo "== reference data $DATA_DIR"
  "${PY[@]}" "$HERE/lib/load_reference_data.py" --data "$DATA_DIR" --dsn "$DSN" --out "${OUT}_data"
fi

# ---- 5. post-build -------------------------------------------------------------
"${PSQL[@]}" -d "$LAB_DB" \
  -v repo_commit="$(git -C "$REPO" rev-parse HEAD)" \
  -v repo_branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" \
  -v export_dir="$EXPORT_DIR" \
  -v data_dir="${DATA_DIR:-none}" \
  -v manifest="$(cat "$EXPORT_DIR/manifest.json")" \
  -f "$HERE/sql/31_post_build_prod.sql"
echo "== done: ${OUT}_schema.{tsv,json,log}${DATA_DIR:+, ${OUT}_data.{tsv,json}}"
