#!/usr/bin/env bash
# lab/research/p2_perfect_day/bound_all.sh -- E5 on every finished capacity day the lab kept (LAB ONLY).
# For each ottoq_cap_* replica not yet bounded: the operations bound (engine order, per owner, the fair day) and the
# battery's bound, one day at a time so the solver has the cores.
#   bash lab/research/p2_perfect_day/bound_all.sh [seconds per solve]
set -u
SECS=${1:-90}
PY=${PY:-/var/tmp/ottoq_lab_venv/bin/python}
HERE="$(cd "$(dirname "$0")" && pwd)"
DONE="$HERE/bound_ops.jsonl"
for db in $(psql -h /var/tmp -p 55433 -U postgres -X -q -A -t -d postgres -c \
            "SELECT datname FROM pg_database WHERE datname LIKE 'ottoq_cap_%' ORDER BY 1"); do
  # a day still running holds an open transaction and has no committed run yet
  n=$(psql -h /var/tmp -p 55433 -U postgres -X -q -A -t -d "$db" -c \
      "SELECT count(*) FROM ottoq_sim_runs WHERE run_by = 'ab_harness'" 2>/dev/null || echo 0)
  [ "$n" = "0" ] && { echo "$db: not finished"; continue; }
  if grep -q "\"db\": \"$db\", \"run\"" "$DONE" 2>/dev/null && grep "\"db\": \"$db\"" "$DONE" | grep -q '"engine_order": true'; then
    echo "$db: bounded already"; continue
  fi
  echo "== $db ($(date -u +%T))"
  "$PY" -I "$HERE/bound_ops.py" --db "$db" --seconds "$SECS" --owners --engine-order
  "$PY" -I "$HERE/bound_energy.py" --db "$db" > /dev/null && echo "battery bound written"
done
