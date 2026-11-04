#!/usr/bin/env bash
# lab/engine/build_from_repo.sh -- rebuild the OTTO-Q engine database from THIS
# repository into the local PostgreSQL 17 research lab. Never touches production.
#
#   lab/engine/build_from_repo.sh            # (re)build database ottoq_lab
#   LAB_PORT=55433 ...                       # overrides (defaults in lib/lab_server.sh)
#
# What it does, in order (each step's result lands in lab/engine/reports/):
#   0. makes sure the lab server is up (initdb + config on first use)
#   1. drops and recreates the lab database
#   2. 00_roles.sql (cluster roles), 10_supabase_shims.sql, 12_cron_standin.sql, 20_repo_gaps.sql
#   3. db/baseline/ via lib/load_baseline.py (statement by statement, to a fixpoint)
#   4. every post-baseline migration that is not PENDING, one transaction each,
#      via lib/apply_migrations.py
#   5. 30_post_build.sql (all cron jobs inactive; lab.build_info row)
#
# The baseline cutoff is ledger version 20260803210034: db/baseline/README.md
# verified the export against a ledger of exactly 621 rows on 2026-08-04, and on
# 2026-11-03 production's ledger holds exactly 621 versions below 0002's
# (20260804140958), the last of them 20260803210034. So the baseline stands for
# ledger rows <= 20260803210034, and db/migrations/ starts at 0002.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STAMP="$(date -u +%Y-%m-%d)"
OUT="$HERE/reports/build_${STAMP}"
BASELINE_CUTOFF="20260803210034"

# ---- 0. server and python driver (shared with build_from_prod.sh) -------------
source "$HERE/lib/lab_server.sh"

# ---- 1. database -------------------------------------------------------------
echo "== (re)creating database $LAB_DB"
"${PSQL[@]}" -d postgres -c "DROP DATABASE IF EXISTS $LAB_DB WITH (FORCE)"
# Production's database: UTF8, ICU locale en-US (collation version 153.121),
# LC_COLLATE/LC_CTYPE en_US.UTF-8 (read 2026-11-03). Text sorts the same way here.
"${PSQL[@]}" -d postgres -c "CREATE DATABASE $LAB_DB TEMPLATE template0 ENCODING 'UTF8' LOCALE_PROVIDER icu ICU_LOCALE 'en-US' LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8'"

# ---- 2. roles, shims, repo gaps ------------------------------------------------
echo "== roles, Supabase shims, repo gaps"
"${PSQL[@]}" -d postgres -f "$HERE/sql/00_roles.sql"
"${PSQL[@]}" -d "$LAB_DB" -f "$HERE/sql/10_supabase_shims.sql"
"${PSQL[@]}" -d "$LAB_DB" -f "$HERE/sql/12_cron_standin.sql"
"${PSQL[@]}" -d "$LAB_DB" -f "$HERE/sql/20_repo_gaps.sql"

# ---- 3. baseline -------------------------------------------------------------
echo "== baseline (db/baseline, cutoff ledger version $BASELINE_CUTOFF)"
"${PY[@]}" "$HERE/lib/load_baseline.py" --repo "$REPO" \
  --dsn "host=$LAB_HOST port=$LAB_PORT dbname=$LAB_DB user=postgres" --out "${OUT}_baseline"

# ---- 4. migrations ------------------------------------------------------------
echo "== post-baseline migrations (db/migrations)"
"${PY[@]}" "$HERE/lib/apply_migrations.py" --repo "$REPO" --psql "$PGBIN/psql" \
  --host "$LAB_HOST" --port "$LAB_PORT" --db "$LAB_DB" --out "${OUT}_migrations" > "${OUT}_migrations.log"
tail -1 "${OUT}_migrations.log"

# ---- 5. post-build ----------------------------------------------------------------
"${PSQL[@]}" -d "$LAB_DB" \
  -v repo_commit="$(git -C "$REPO" rev-parse HEAD)" \
  -v repo_branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" \
  -v baseline_cutoff="$BASELINE_CUTOFF" \
  -f "$HERE/sql/30_post_build.sql"
echo "== done: ${OUT}_baseline.{tsv,json}, ${OUT}_migrations.{tsv,json,log}"
