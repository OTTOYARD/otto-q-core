#!/usr/bin/env bash
# lab/engine/install_server.sh -- install the lab's PostgreSQL 17 (with PostGIS) on Ubuntu 24.04, as root.
#
# The steps the 2026-11-04 session ran, in order; the build scripts (build_from_prod.sh, build_from_repo.sh) do the
# rest (initdb, configuration, the Python driver) on first use. No Docker: no Docker daemon was available to test a
# container, and an untested Dockerfile is not shipped.
#
#   - the PGDG apt source (apt.postgresql.org), keyed by its published key
#   - create_main_cluster = false, so no default cluster appears on 5432
#   - a FULL apt-get update: updating only the PGDG list leaves PostGIS's Ubuntu dependencies unresolvable
#     ("held broken packages", measured 2026-11-04)
#   - postgresql-17 and postgresql-17-postgis-3. Not pg_cron: the lab loads no job scheduler
#     (sql/12_cron_standin.sql says why).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
. /etc/os-release
install -d /usr/share/postgresql-common/pgdg
curl -fsS -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
mkdir -p /etc/postgresql-common
grep -qs '^create_main_cluster' /etc/postgresql-common/createcluster.conf \
  || echo "create_main_cluster = false" >> /etc/postgresql-common/createcluster.conf
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql-17 postgresql-17-postgis-3
/usr/lib/postgresql/17/bin/postgres --version
