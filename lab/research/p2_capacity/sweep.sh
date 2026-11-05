#!/usr/bin/env bash
# lab/research/p2_capacity/sweep.sh -- the capacity curve: one lab depot-day per (scenario, fleet, seed), four at a time
# (one per core), each in its own replica, kept for E5 (lab/research/p2_perfect_day/). LAB ONLY.
#
#   bash lab/research/p2_capacity/sweep.sh "normal_day busy_day" "80 116 150 200 250" "171717 424242" [results.jsonl]
#
# Each line of the results file is one day: capacity_day.py's scorecard, owners, resources and walls.
set -u
SCENARIOS=${1:-"normal_day"}
FLEETS=${2:-"116"}
SEEDS=${3:-"171717"}
OUT=${4:-"$(dirname "$0")/results.jsonl"}
PY=${PY:-/var/tmp/ottoq_lab_venv/bin/python}
HERE="$(cd "$(dirname "$0")" && pwd)"
LOGDIR=${LOGDIR:-/var/tmp/ottoq_cap_logs}
mkdir -p "$LOGDIR"
jobs_list=()
for s in $SCENARIOS; do for f in $FLEETS; do for seed in $SEEDS; do jobs_list+=("$s $f $seed"); done; done; done
echo "$(date -u +%FT%TZ) ${#jobs_list[@]} days, 4 at a time -> $OUT"
i=0
for j in "${jobs_list[@]}"; do
  set -- $j
  "$PY" -I "$HERE/capacity_day.py" --scenario "$1" --fleet "$2" --seed "$3" --keep --out "$OUT" \
      > "$LOGDIR/${1}_${2}_${3}.log" 2>&1 &
  i=$((i + 1))
  sleep 4   # the replicas are cloned one after another from the same template
  while [ "$(jobs -rp | wc -l)" -ge 4 ]; do sleep 5; done
done
wait
echo "$(date -u +%FT%TZ) done"
tail -n +1 "$LOGDIR"/*.log | grep -E "fleet|Error|error" | tail -40
