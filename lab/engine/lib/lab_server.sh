# lab/engine/lib/lab_server.sh -- sourced by the lab's build scripts (build_from_repo.sh,
# build_from_prod.sh). Defines the lab server's settings, makes sure the server is up
# (initdb + configuration on first use), refuses to go on unless no pg_cron job can launch,
# and makes sure the Python driver exists. Never touches production.
#
#   PGBIN, LAB_DATA, LAB_HOST, LAB_PORT, LAB_DB, LAB_VENV override the defaults below;
#   LAB_DB must equal the server's cron.database_name (pg_cron).
PGBIN="${PGBIN:-/usr/lib/postgresql/17/bin}"
LAB_DATA="${LAB_DATA:-/var/tmp/ottoq_lab_pg17}"
LAB_HOST="${LAB_HOST:-/var/tmp}"
LAB_PORT="${LAB_PORT:-55433}"
LAB_DB="${LAB_DB:-ottoq_lab}"
VENV="${LAB_VENV:-/var/tmp/ottoq_lab_venv}"

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

