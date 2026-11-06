#!/usr/bin/env bash
# lab/research/p2_capacity/planner_study_0801.sh fit|jobs|bill SEED... -- the battery planner study on the 0801 lab copy
# (2026-11-06; LAB ONLY). Run from the repository root.
#   fit   for every seed, the learned forecasts that never saw it, fitted on the other seeds' base days
#         (forecast_audit_0801.jsonl): the mean, and the mean plus the 80th, 90th and 95th percentile of the misses each
#         training day had when it was left out of the fit (forecast_learn.py --offset-from cv)
#   jobs  the planner days, five per seed, to jobs_2026-11-06_p801.txt (run with LAB_DB=ottoq_lab_0801)
#   bill  every day's bill (bound_energy.py): the base days with the forecast ladder and again holding the 600 kWh call
#         reserve, the planner days without the ladder; a day already billed is skipped
set -eu
cmd=$1; shift
PY=${PY:-/var/tmp/ottoq_lab_venv/bin/python}
D=lab/research/p2_capacity
E=lab/research/p2_perfect_day/bound_energy.jsonl
case "$cmd" in
  fit)
    for s in "$@"; do
      $PY -I $D/forecast_learn.py $D/forecast_audit_0801.jsonl --save $D/forecast_model_0801_mean_ex$s.json --exclude-seed $s
      for q in 80 90 95; do
        $PY -I $D/forecast_learn.py $D/forecast_audit_0801.jsonl --save $D/forecast_model_0801_q${q}cv_ex$s.json \
            --exclude-seed $s --quantile 0.$q --offset-from cv
      done
    done ;;
  jobs)
    J=$D/jobs_2026-11-06_p801.txt
    {
      echo "# The battery planner on the 0801 lab copy (2026-11-06; LAB ONLY; LAB_DB=ottoq_lab_0801): five planner days per seed,"
      echo "# each against its base day (<seed>_b801) car for car. The shape is seed 171717's day (424242's for 171717 itself);"
      echo "# the learned forecasts were fitted on the other seeds' base days only (planner_study_0801.sh fit)."
      for s in "$@"; do
        shape=$D/load_shape_normal_day_116_171717.json
        [ "$s" = 171717 ] && shape=$D/load_shape_normal_day_116_424242.json
        base="--fleet 116 --scenario normal_day --seed $s --battery-lp $shape"
        echo "normal_day_116_${s}_p801shape|$base --tag p801shape"
        echo "normal_day_116_${s}_p801mean|$base --battery-lp-learned $D/forecast_model_0801_mean_ex$s.json --tag p801mean"
        for q in 80 90 95; do
          echo "normal_day_116_${s}_p801q$q|$base --battery-lp-learned $D/forecast_model_0801_q${q}cv_ex$s.json --tag p801q$q"
        done
      done
    } > $J
    wc -l $J ;;
  bill)
    for s in "$@"; do
      for tag in b801 p801shape p801mean p801q80 p801q90 p801q95; do
        db=ottoq_cap_normal_day_116_${s}_$tag
        psql -h /var/tmp -p 55433 -U postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -q 1 || continue
        # only a finished day: its row in the results file, whole and without an error (a day still running has a replica)
        $PY -I - "$db" <<'PYEOF' || continue
import json, sys
db = sys.argv[1]
ok = any(d["db"] == db and not d.get("error") and d.get("ticks") == 144
         for d in (json.loads(l) for l in open("lab/research/p2_capacity/results.jsonl") if l.strip()))
sys.exit(0 if ok else 1)
PYEOF
        if [ "$tag" = b801 ]; then
          grep -q "\"db\": \"$db\"" $E 2>/dev/null || $PY -I lab/research/p2_perfect_day/bound_energy.py --db $db > /dev/null
          grep "\"db\": \"$db\"" $E | grep -q '"dr_reserve": {' || \
            $PY -I lab/research/p2_perfect_day/bound_energy.py --db $db --dr-reserve-kwh 600 --no-ladder > /dev/null
        else
          grep -q "\"db\": \"$db\"" $E 2>/dev/null || $PY -I lab/research/p2_perfect_day/bound_energy.py --db $db --no-ladder > /dev/null
        fi
        echo "billed $db"
      done
    done ;;
esac
