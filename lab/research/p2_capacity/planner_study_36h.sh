#!/usr/bin/env bash
# lab/research/p2_capacity/planner_study_36h.sh fit|jobs|bill SEED... -- the battery planner in steady state (2026-11-06; LAB
# ONLY; run from the repository root). 36-hour days (6 AM day 1 to 6 PM day 2) billed over the last 24 hours.
#   fit   for every seed, the learned forecast that never saw it, fitted on the other seeds' 36-hour base days
#         (forecast_audit_36h.jsonl, every hour of the day and night), plus its 80th-percentile out-of-sample miss
#   jobs  two planner days per seed to jobs_2026-11-06_p36.txt (run with LAB_DB=ottoq_lab_0801): the next seed's 36-hour
#         load as the copied shape, and the learned forecast with its band (the shape beyond its four hours)
#   bill  every finished day's bill over the window from hour 12 (6 PM day 1) to the end (bound_energy.py
#         TAGS="..." bills other arms' days, e.g. TAGS="p36prof dp36learn"
#         --window-start-h 12); the base days also holding the 600 kWh call reserve
set -eu
cmd=$1; shift
PY=${PY:-/var/tmp/ottoq_lab_venv/bin/python}
D=lab/research/p2_capacity
E=lab/research/p2_perfect_day/bound_energy.jsonl
case "$cmd" in
  fit)
    for s in "$@"; do
      $PY -I $D/forecast_learn.py $D/forecast_audit_36h.jsonl --save $D/forecast_model_36h_q80cv_ex$s.json \
          --exclude-seed $s --quantile 0.8 --offset-from cv
    done ;;
  jobs)
    J=$D/jobs_2026-11-06_p36.txt
    seeds=("$@")
    {
      echo "# The battery planner in steady state, two planner days per seed (2026-11-06; LAB ONLY; LAB_DB=ottoq_lab_0801), each"
      echo "# against its 36-hour base day (<seed>_b36) car for car, billed from 6 PM day 1. The copied shape is the next seed's"
      echo "# 36-hour base load; the learned forecast was fitted on the other seeds' 36-hour base days only."
      for i in "${!seeds[@]}"; do
        s=${seeds[$i]}; o=${seeds[$(( (i + 1) % ${#seeds[@]} ))]}
        shape=$D/load_shape_normal_day_116_${o}_b36.json
        [ -f "$shape" ] || $PY -I $D/make_load_shape.py --from-db ottoq_cap_normal_day_116_${o}_b36 > /dev/null
        base="--fleet 116 --scenario normal_day --seed $s --ticks 432 --run-hours 36 --dial bess_plan_bill_from_min=720 --battery-lp $shape --battery-lp-bill-from-min 720"
        echo "normal_day_116_${s}_p36shape|$base --tag p36shape"
        echo "normal_day_116_${s}_p36q80|$base --battery-lp-learned $D/forecast_model_36h_q80cv_ex$s.json --tag p36q80"
      done
    } > $J
    wc -l $J ;;
  bill)
    for s in "$@"; do
      for tag in ${TAGS:-b36 p36shape p36q80}; do
        db=ottoq_cap_normal_day_116_${s}_$tag
        psql -h /var/tmp -p 55433 -U postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -q 1 || continue
        $PY -I - "$db" <<'PYEOF' || continue
import json, sys
db = sys.argv[1]
ok = any(d["db"] == db and not d.get("error") and d.get("ticks") == 432
         for d in (json.loads(l) for l in open("lab/research/p2_capacity/results.jsonl") if l.strip()))
sys.exit(0 if ok else 1)
PYEOF
        has() { grep "\"db\": \"$db\"" $E 2>/dev/null | grep '"window_start_h": 12' | grep -q "$1"; }
        has '"dr_reserve": null' || $PY -I lab/research/p2_perfect_day/bound_energy.py --db $db --window-start-h 12 --no-ladder > /dev/null
        if [ "$tag" = b36 ]; then
          has '"dr_reserve": {' || $PY -I lab/research/p2_perfect_day/bound_energy.py --db $db --window-start-h 12 \
              --dr-reserve-kwh 600 --no-ladder > /dev/null
        fi
        echo "billed $db"
      done
    done ;;
esac
