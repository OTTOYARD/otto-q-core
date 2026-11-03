#!/usr/bin/env bash
# lab/engine/build_from_repo.sh -- rebuild the OTTO-Q engine database from THIS
# repository into the local PostgreSQL 17 research lab. Never touches production.
#
#   lab/engine/build_from_repo.sh            # (re)build database ottoq_lab
#   LAB_PORT=55433 ...                       # overrides (defaults shown below); LAB_DB must
#                                            # equal the server's cron.database_name (pg_cron)
#
# What it does, in order (each step's result lands in lab/engine/reports/):
#   0. makes sure the lab server is up (initdb + config on first use)
#   1. drops and recreates the lab database
#   2. 00_roles.sql (cluster roles), 10_supabase_shims.sql, 20_repo_gaps.sql
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
PGBIN="${PGBIN:-/usr/lib/postgresql/17/bin}"
LAB_DATA="${LAB_DATA:-/var/tmp/ottoq_lab_pg17}"
LAB_HOST="${LAB_HOST:-/var/tmp}"
LAB_PORT="${LAB_PORT:-55433}"
LAB_DB="${LAB_DB:-ottoq_lab}"
VENV="${LAB_VENV:-/var/tmp/ottoq_lab_venv}"
STAMP="$(date -u +%Y-%m-%d)"
OUT="$HERE/reports/build_${STAMP}"
BASELINE_CUTOFF="20260803210034"

PSQL=("$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -h "$LAB_HOST" -p "$LAB_PORT" -U postgres)
as_pg() { if [ "$(id -un)" = postgres ]; then "$@"; else su postgres -s /bin/bash -c "$(printf '%q ' "$@")"; fi; }

# ---- 0. server ---------------------------------------------------------------
# The libc locale production's database names (en_US.UTF-8). A running server
# only sees a locale generated before it started, so a fresh one forces a restart.
NEW_LOCALE=0
if ! locale -a 2>/dev/null | grep -qix 'en_US.utf8'; then
  echo "== generating libc locale en_US.UTF-8"
  localedef -i en_US -f UTF-8 en_US.UTF-8
  NEW_LOCALE=1
fi
if [ ! -s "$LAB_DATA/PG_VERSION" ]; then
  echo "== initdb $LAB_DATA"
  install -d -o postgres -g postgres "$LAB_DATA"
  as_pg "$PGBIN/initdb" -D "$LAB_DATA" -U postgres --encoding=UTF8 --locale=C.UTF-8 --auth=trust >/dev/null
  cat >> "$LAB_DATA/postgresql.conf" <<EOF

# ---- OTTO-Q research lab (lab/engine) ------------------------------------
port = $LAB_PORT
listen_addresses = ''
unix_socket_directories = '$LAB_HOST'
timezone = 'UTC'
log_timezone = 'UTC'
shared_preload_libraries = 'pg_cron,pg_stat_statements'
cron.database_name = '$LAB_DB'
cron.launch_active_jobs = off
max_locks_per_transaction = 2048
shared_buffers = 1GB
work_mem = 32MB
maintenance_work_mem = 256MB
synchronous_commit = off
logging_collector = on
log_directory = 'log'
EOF
fi
if [ "$NEW_LOCALE" = 1 ] && "$PGBIN/pg_isready" -q -h "$LAB_HOST" -p "$LAB_PORT"; then
  as_pg "$PGBIN/pg_ctl" -D "$LAB_DATA" -l "$LAB_DATA/startup.log" -w restart -m fast >/dev/null
fi
if ! "$PGBIN/pg_isready" -q -h "$LAB_HOST" -p "$LAB_PORT"; then
  echo "== starting lab server on $LAB_HOST:$LAB_PORT"
  rm -f "$LAB_DATA/postmaster.pid"
  as_pg "$PGBIN/pg_ctl" -D "$LAB_DATA" -l "$LAB_DATA/startup.log" -w start >/dev/null
fi
[ "$("${PSQL[@]}" -d postgres -Atc 'show cron.launch_active_jobs')" = off ] \
  || { echo "refusing to build: cron.launch_active_jobs is not off on the lab server" >&2; exit 1; }

# ---- python driver ---------------------------------------------------------------
if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c 'import psycopg' 2>/dev/null; then
  echo "== venv $VENV (psycopg)"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q "psycopg[binary]==3.3.7"
fi
PY=("$VENV/bin/python" -I)

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
