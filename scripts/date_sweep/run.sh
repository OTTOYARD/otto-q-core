#!/bin/bash
# Runs CI's SQL test files as of a later day, to find a check that will stop passing on a date (G482: 0625's V3 held
# only for 21 days after a fixed record and turned every CI run red at 11:53 UTC on 2026-10-21).
#
# A copy of the scratch PostgreSQL (port 55432) is started on port 55433 with its wall clock shifted DAYS ahead by
# faketime.c (LD_PRELOAD; monotonic clocks untouched), and the test process runs under the same shift, so planted times
# and now() agree as they would on that day. Needs root (the server runs as postgres) and gcc.
#
#   scripts/date_sweep/run.sh [DAYS]        (default 30; results in $OUT, default /tmp/date_sweep;
#                                           FILES="tests/a.py ..." runs only those)
set -euo pipefail
DAYS=${1:-30}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR=/var/tmp/ottoq_date_sweep
OUT=${OUT:-/tmp/date_sweep}
PGBIN=/usr/lib/postgresql/16/bin
mkdir -p "$DIR" "$OUT"
gcc -O2 -shared -fPIC -o "$DIR/faketime.so" "$ROOT/scripts/date_sweep/faketime.c" -ldl
chmod 755 "$DIR" "$DIR/faketime.so"
chown postgres:postgres "$DIR"
if [ ! -d "$DIR/data" ]; then
  su postgres -s /bin/bash -c "$PGBIN/pg_basebackup -h /var/tmp -p 55432 -U postgres -D $DIR/data -X stream"
fi
su postgres -s /bin/bash -c "LD_PRELOAD=$DIR/faketime.so FAKE_OFFSET_S=$((DAYS*86400)) $PGBIN/pg_ctl -D $DIR/data \
  -o \"-k /var/tmp -p 55433 -c listen_addresses=\" -l $DIR/server.log restart"
PGHOST=/var/tmp PGPORT=55433 PGUSER=postgres psql -d postgres -Atc "select 'server clock: ' || now()"
cd "$ROOT"
if [ -n "${FILES:-}" ]; then          # a few files only: FILES="tests/a.py tests/b.py"
  echo "$FILES" | tr ' ' '\n' | grep . > "$OUT/files.txt"
else                                   # every file CI's SQL steps run
  awk 'NR>=130' .github/workflows/verify.yml | grep -oE 'tests/test_[a-z0-9_]+\.py' | awk '!seen[$0]++' > "$OUT/files.txt"
fi
: > "$OUT/summary.txt"
for f in $(cat "$OUT/files.txt"); do
  r=$(LD_PRELOAD=$DIR/faketime.so FAKE_OFFSET_S=$((DAYS*86400)) PGHOST=/var/tmp PGPORT=55433 PGUSER=postgres \
      timeout 2400 python3 -m pytest -q -p no:cacheprovider "$f" 2>&1 | tee -a "$OUT/full.log" | tail -1)
  echo "$f :: $r" | tee -a "$OUT/summary.txt"
done
su postgres -s /bin/bash -c "$PGBIN/pg_ctl -D $DIR/data stop -m fast"
echo "not passed:"; grep -vE ":: [0-9]+ passed in" "$OUT/summary.txt" || echo "none"
