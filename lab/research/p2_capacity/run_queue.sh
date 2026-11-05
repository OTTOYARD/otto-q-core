#!/usr/bin/env bash
# lab/research/p2_capacity/run_queue.sh JOBS_FILE [PARALLEL] -- lab days from a list, PARALLEL at a time (default 4, one
# per core), skipping every day the results file already holds whole (all its ticks, no error). LAB ONLY.
#
# A lab day runs in one transaction, so a container restart that kills it rolls it back and leaves nothing half-written;
# running the same list again picks up where it stopped (the lab server must be up: it needs crash recovery after a
# restart, `pg_ctl start` as postgres, see lab/engine/README.md).
#
#   each line of JOBS_FILE:  <log label>|<capacity_day.py arguments>      (blank lines and # comments are skipped)
#   OUT (results file), PY (the lab venv's python), LOGDIR (one log per day) override the defaults below.
set -u
JOBS=$1
PAR=${2:-4}
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT=${OUT:-$HERE/results.jsonl}
PY=${PY:-/var/tmp/ottoq_lab_venv/bin/python}
LOGDIR=${LOGDIR:-/var/tmp/ottoq_cap_logs}
mkdir -p "$LOGDIR"
cd "$ROOT" || exit 1

day_done() {   # scenario tag fleet seed ticks -> exit 0 when the results file holds that day whole
  python3 -I - "$OUT" "$@" <<'EOF'
import json
import sys
out, scen, tag, fleet, seed, ticks = sys.argv[1:]
try:
    with open(out) as f:
        for line in f:
            if not line.strip():
                continue
            d = json.loads(line)
            if ((d["scenario"], d.get("tag") or "", str(d["fleet"]), str(d["seed"])) == (scen, tag, fleet, seed)
                    and str(d.get("ticks")) == ticks and not d.get("error")):
                sys.exit(0)
except FileNotFoundError:
    pass
sys.exit(1)
EOF
}

while IFS= read -r line <&3; do
  [ -z "${line// }" ] && continue
  case "$line" in \#*) continue ;; esac
  label=${line%%|*}
  args=${line#*|}
  scen=normal_day; tag=""; fleet=""; seed=171717; ticks=144
  set -- $args
  while [ $# -gt 0 ]; do
    case "$1" in
      --scenario) scen=$2; shift ;;
      --tag) tag=$2; shift ;;
      --fleet) fleet=$2; shift ;;
      --seed) seed=$2; shift ;;
      --ticks) ticks=$2; shift ;;
    esac
    shift
  done
  if day_done "$scen" "$tag" "$fleet" "$seed" "$ticks"; then
    echo "$(date -u +%T) skip $label (in $(basename "$OUT") already)"
    continue
  fi
  while [ "$(jobs -rp | wc -l)" -ge "$PAR" ]; do sleep 10; done
  echo "$(date -u +%T) start $label"
  # shellcheck disable=SC2086
  "$PY" -I "$HERE/capacity_day.py" $args --keep --out "$OUT" < /dev/null > "$LOGDIR/$label.log" 2>&1 &
  sleep 6      # the replicas are cloned one after another from the same template
done 3< "$JOBS"
wait
echo "$(date -u +%T) queue done"
