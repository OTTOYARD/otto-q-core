#!/usr/bin/env bash
# FRAME-MATCHED plan comparison: cuOpt vs CP-SAT on IDENTICAL inputs.
#
# Why this exists alongside the run-level A/B: the A/B compares two runs driven at
# different cadences (cuOpt fires from the edge every decide tick; a bridge pass
# costs a frame fetch + ~2s solve + a submit), so its KPI delta carries a confound
# that cannot be removed, only named. This has no such problem -- both solvers see
# the SAME decision frame, so any difference is the solver.
#
# IT NEVER SUBMITS. The emitted SQL is written and deliberately not executed, so
# Arm A stays a clean cuOpt-only arm. Contamination is asserted afterwards by
# counting forward_lex rows on the run, which must stay 0.
set -u
S="${OTTOQ_WORK:-$(mktemp -d)}"
CORE="${OTTOQ_CORE:-$(cd "$(dirname "$0")/.." && pwd)}"
DEPOT=11111111-1111-1111-1111-111111111111
RUN="${1:?run id}"
N="${2:-20}"
SLP="${3:-25}"
OUT="$S/matched_${RUN:0:8}.jsonl"
: > "$OUT"

# Run-invariant input, fetched ONCE and by this script rather than taken from the
# caller: a stale classes.json would solve against the wrong battery capacities
# and say nothing about it.
CLASSES="$S/classes.json"
python3 "${OTTOQ_SQL:?set OTTOQ_SQL to a script taking SQL on argv or stdin and printing JSON rows}" "
  SELECT vehicle_class_code, battery_capacity_kwh, max_charge_rate_kw,
         charge_kinds, energy_curve, battery_chemistry
    FROM public.ottoq_vehicle_classes
   WHERE status = 'active'
   ORDER BY vehicle_class_code;" > "$CLASSES" 2>&1
python3 -c "
import json, sys
rows = json.load(open('$CLASSES'))
if not isinstance(rows, list) or not rows:
    sys.exit('class table empty or malformed')
" || { echo "compare-plans: could not fetch the vehicle class table; refusing to solve against nothing" >&2; exit 2; }

for i in $(seq 1 "$N"); do
  ROW=$(python3 "${OTTOQ_SQL:?set OTTOQ_SQL to a script taking SQL on argv or stdin and printing JSON rows}" "
    SELECT r.status, r.tick_count,
           (SELECT count(*) FROM public.ottoq_external_proposals p
             WHERE p.sim_run_id=r.sim_run_id AND p.source='cuopt') AS cuopt_total,
           (SELECT count(*) FROM public.ottoq_external_proposals p
             WHERE p.sim_run_id=r.sim_run_id AND p.source='cuopt' AND p.status='enacted') AS cuopt_enacted,
           (SELECT count(*) FROM public.ottoq_external_proposals p
             WHERE p.sim_run_id=r.sim_run_id AND p.source='forward_lex') AS contamination,
           (SELECT count(*) FROM public.stalls s
             WHERE s.depot_id='$DEPOT' AND s.stall_type IN ('dcfc','l2')
               AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
               AND s.status='available') AS charge_free
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id='$RUN';" 2>/dev/null)

  STATUS=$(echo "$ROW" | python3 -c "import sys,json;print(json.load(sys.stdin)[0]['status'])" 2>/dev/null || echo gone)
  if [ "$STATUS" != "running" ]; then
    echo "{\"stopped_at_pass\":$i,\"run_status\":\"$STATUS\"}" >> "$OUT"; break
  fi

  # the frame BOTH solvers are judged on
  python3 "${OTTOQ_SQL:?set OTTOQ_SQL to a script taking SQL on argv or stdin and printing JSON rows}" "SELECT public.ottoq_build_decision_frame('$DEPOT','$RUN') AS frame;" > "$S/_mf.json" 2>&1
  python3 -c "
import json
try: json.dump(json.load(open('$S/_mf.json'))[0]['frame'], open('$S/_mframe.json','w'))
except Exception: json.dump({}, open('$S/_mframe.json','w'))
"
  # CP-SAT on that frame. --emit-sql is written and NEVER executed.
  ( cd "$CORE" && timeout 300 python3 -m bridge.proposer_bridge \
      --run "$RUN" --depot "$DEPOT" --site bridge/sites/nashville-flagship.json \
      --frame "$S/_mframe.json" --classes "$CLASSES" \
      --via batch --emit-sql "$S/_m_notexecuted.sql" --json-out "$S/_mfire.json" \
      >/dev/null 2>"$S/_mfire.err" )

  python3 - "$i" "$ROW" "$S/_mfire.err" "$S/_mframe.json" >> "$OUT" <<'PY'
import sys, json
i, rowjson, errfile, framefile = sys.argv[1:5]
out = {"pass": int(i)}
try:
    r = json.load(open("/dev/stdin")) if False else json.loads(rowjson)[0]
    out.update({k: r[k] for k in ("tick_count","cuopt_total","cuopt_enacted",
                                  "contamination","charge_free")})
except Exception as e:
    out["row_error"] = str(e)[:120]
try:
    fr = json.load(open(framefile))
    out["frame_vehicles"] = len(fr.get("vehicles") or [])
    out["frame_stalls"] = len(fr.get("stalls") or [])
except Exception:
    pass
try:
    lines = [l for l in open(errfile).read().strip().splitlines() if l.strip().startswith("{")]
    rec = json.loads(lines[-1]) if lines else {}
    s = rec.get("solver") or {}
    out.update({
        "cpsat_status": rec.get("status"),
        "cpsat_rows": rec.get("n_rows"),
        "cpsat_planned": rec.get("n_planned"),
        "cpsat_abstained": rec.get("n_abstained"),
        "cpsat_peak_kw": s.get("site_peak_kw"),
        "cpsat_tardy_min": s.get("total_tardy_min"),
        "cpsat_pass1": s.get("pass1_status"),
        "cpsat_reproducible": s.get("reproducible"),
        "cpsat_stalls_blocked": rec.get("stalls_blocked"),
        "cpsat_err": (rec.get("error") or "")[:140],
    })
except Exception as e:
    out["fire_error"] = str(e)[:120]
print(json.dumps(out))
PY
  sleep "$SLP"
done
echo "MATCHED CAPTURE DONE"
