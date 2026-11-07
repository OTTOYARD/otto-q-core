# lab/engine/lib/lab_server.sh -- sourced by the lab's build scripts (build_from_repo.sh,
# build_from_prod.sh). Defines the lab server's settings, makes sure the server is up
# (initdb + configuration on first use), refuses to go on unless no job scheduler is loaded,
# and makes sure the Python driver exists. Never touches production.
#
#   PGBIN, LAB_DATA, LAB_HOST, LAB_PORT, LAB_DB, LAB_VENV override the defaults below;
#   (The server loads no pg_cron: see sql/12_cron_standin.sql.)
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
shared_preload_libraries = 'pg_stat_statements'
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
# Production's session settings, SERVER-WIDE (2026-11-04). Production sets them in its configuration file, so every
# database on its server has them. The shims also set them on the lab database, but a replica made by
# CREATE DATABASE ... TEMPLATE does not inherit database-level settings: measured 2026-11-04, replicas ran with
# jit on, extra_float_digits 1 and no extensions on the search path. Set here, every database on the lab server
# runs as production's does. (Reloadable settings: no restart. search_path is a LIST: written as one, never as a
# single quoted string, which would make the whole list one schema name.)
"${PSQL[@]}" -d postgres \
  -c "ALTER SYSTEM SET jit = off" \
  -c "ALTER SYSTEM SET extra_float_digits = 0" \
  -c 'ALTER SYSTEM SET search_path = "$user", public, extensions' \
  -c "ALTER SYSTEM SET timezone = 'UTC'" \
  -c "ALTER SYSTEM SET lc_monetary = 'en_US.UTF-8'" \
  -c "ALTER SYSTEM SET lc_numeric = 'en_US.UTF-8'" \
  -c "ALTER SYSTEM SET lc_time = 'en_US.UTF-8'" \
  -c "ALTER SYSTEM SET default_text_search_config = 'pg_catalog.english'" \
  -c "SELECT pg_reload_conf()" >/dev/null

# No job scheduler, ever (2026-11-04). pg_cron's scheduler held a session open in the lab database even with
# cron.launch_active_jobs = off, and CREATE DATABASE ... TEMPLATE refuses a template anyone is connected to, which
# the parallel replicas and long forks need. A server set up before then is switched over here.
if "${PSQL[@]}" -d postgres -Atc 'show shared_preload_libraries' | grep -q pg_cron; then
  echo "== the lab server preloads pg_cron: removing it (no scheduler in the lab) and restarting"
  "${PSQL[@]}" -d postgres -c "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements'"
  as_pg "$PGBIN/pg_ctl" -D "$LAB_DATA" -l "$LAB_DATA/startup.log" -w restart -m fast >/dev/null
fi
[ "$("${PSQL[@]}" -d postgres -Atc "select count(*) from pg_stat_activity where backend_type ilike '%cron%'")" = 0 ] \
  && ! "${PSQL[@]}" -d postgres -Atc 'show shared_preload_libraries' | grep -q pg_cron \
  || { echo "refusing to build: a pg_cron scheduler is loaded on the lab server" >&2; exit 1; }

# A lab day runs in ONE transaction with a savepoint per tick, as the engine's own sweep arm and determinism pair do, so
# the rows it locks and then changes in later subtransactions make MultiXacts. Five such days at once spent about two
# thirds of their time waiting on the cluster-wide MultiXact caches at PostgreSQL 17's defaults (128 kB of offsets,
# 256 kB of members; sampled 2026-11-05: MultiXactOffsetSLRU, SlruRead, MultiXactMemberSLRU against CPU 21 of 60).
# These caches are the server's own working memory and change no result. They take effect at a restart, so a lab day in
# flight is never cut short here: the settings are written, and the restart happens when no lab day is running.
if [ "$("${PSQL[@]}" -d postgres -Atc 'show multixact_offset_buffers')" != "64MB" ]; then
  echo "== the lab server's MultiXact and subtransaction caches: 64 MB / 128 MB / 64 MB (at the next restart)"
  "${PSQL[@]}" -d postgres -c "ALTER SYSTEM SET multixact_offset_buffers = '64MB'" \
                           -c "ALTER SYSTEM SET multixact_member_buffers = '128MB'" \
                           -c "ALTER SYSTEM SET subtransaction_buffers = '64MB'" >/dev/null
  if [ "$("${PSQL[@]}" -d postgres -Atc "select count(*) from pg_stat_activity where datname like 'ottoq_%' and state <> 'idle'")" = 0 ]; then
    as_pg "$PGBIN/pg_ctl" -D "$LAB_DATA" -l "$LAB_DATA/startup.log" -w restart -m fast >/dev/null
  fi
fi

# ---- python driver ---------------------------------------------------------------
if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c 'import psycopg' 2>/dev/null; then
  echo "== venv $VENV (psycopg)"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q "psycopg[binary]==3.3.7"
fi
PY=("$VENV/bin/python" -I)

