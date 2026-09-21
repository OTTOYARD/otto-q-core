#!/usr/bin/env bash
# Drive forward_lex (CP-SAT) as a live proposer through the offline bridge route.
#
# No DSN, no edge secret, no host: fetch the frame over the Management API, solve
# locally, execute the emitted ottoq_proposer_submit_batch. This is what makes the
# CP-SAT arm of the comparison possible at all.
#
# Usage: drive_cpsat.sh <sim_run_id> <iterations> [sleep_seconds]
#
# CADENCE IS A KNOWN CONFOUND AND IS LOGGED RATHER THAN HIDDEN. cuOpt fires once
# per decide tick from the edge (~16 ticks/min at speed 1.0). One pass here costs
# a frame fetch + a ~2s deterministic solve + a submit, so this cannot match that
# rate. Every pass records the run's tick_count, so fire coverage (fires / ticks)
# is computable afterwards and the comparison can state what it actually had.
set -u
S="${OTTOQ_WORK:-$(mktemp -d)}"
CORE="${OTTOQ_CORE:-$(cd "$(dirname "$0")/.." && pwd)}"
DEPOT=11111111-1111-1111-1111-111111111111
RUN="${1:?sim_run_id required}"
N="${2:?iterations required}"
SLP="${3:-8}"
OUT="$S/cpsat_drive_${RUN:0:8}.jsonl"
: > "$OUT"

# The class table is a run-invariant input (proposer.class_table.SELECT_VEHICLE_CLASSES),
# so it is fetched ONCE rather than per pass. Fetched rather than required from the
# caller so the script is self-contained: a driver that silently reuses a stale
# classes.json would solve against the wrong battery capacities and never say so.
CLASSES="$S/classes.json"
python3 "${OTTOQ_SQL:?set OTTOQ_SQL to a script that takes SQL on argv or stdin and prints JSON rows}" "
  SELECT vehicle_class_code, battery_capacity_kwh, max_charge_rate_kw,
         charge_kinds, energy_curve, battery_chemistry
    FROM public.ottoq_vehicle_classes
   WHERE status = 'active'
   ORDER BY vehicle_class_code;" > "$CLASSES" 2>&1
if ! python3 -c "
import json, sys
rows = json.load(open('$CLASSES'))
if not isinstance(rows, list) or not rows:
    sys.exit('class table came back empty or malformed')
print('classes:', len(rows))
"; then
  echo "drive-cpsat: could not fetch the vehicle class table; refusing to solve against nothing" >&2
  exit 2
fi

for i in $(seq 1 "$N"); do
  # stop early if the run has ended -- firing into a finished run would write
  # proposals that belong to no live world
  ST=$(python3 "${OTTOQ_SQL:?set OTTOQ_SQL to a script that takes SQL on argv or stdin and prints JSON rows}" "SELECT status, tick_count FROM public.ottoq_sim_runs WHERE sim_run_id='$RUN';" 2>/dev/null \
        | python3 -c "
import sys,json
try:
    r=json.load(sys.stdin)[0]; print(r['status'], r['tick_count'])
except Exception: print('gone 0')
")
  STATUS=${ST% *}; TICK=${ST#* }
  if [ "$STATUS" != "running" ]; then
    echo "{\"stopped_at_pass\":$i,\"run_status\":\"$STATUS\",\"tick\":$TICK}" >> "$OUT"
    break
  fi

  python3 "${OTTOQ_SQL:?set OTTOQ_SQL to a script that takes SQL on argv or stdin and prints JSON rows}" "SELECT public.ottoq_build_decision_frame('$DEPOT','$RUN') AS frame;" \
    > "$S/_fr.json" 2>&1
  python3 -c "
import json,sys
try:
    json.dump(json.load(open('$S/_fr.json'))[0]['frame'], open('$S/_frame.json','w'))
except Exception:
    json.dump({}, open('$S/_frame.json','w'))
"
  ( cd "$CORE" && timeout 300 python3 -m bridge.proposer_bridge \
      --run "$RUN" --depot "$DEPOT" --site bridge/sites/nashville-flagship.json \
      --frame "$S/_frame.json" --classes "$S/classes.json" \
      --via batch --emit-sql "$S/_fire.sql" --json-out "$S/_fire.json" \
      >/dev/null 2>"$S/_fire.err" )

  SUB="none"
  if [ -s "$S/_fire.sql" ]; then
    SUB=$(python3 "${OTTOQ_SQL:?set OTTOQ_SQL to a script that takes SQL on argv or stdin and prints JSON rows}" < "$S/_fire.sql" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)[0]['ottoq_proposer_submit_batch']
    print(json.dumps({'submitted':d.get('submitted'),'fire_id':d.get('fire_id'),'tick_seq':d.get('tick_seq'),'err':d.get('error')}))
except Exception as e: print(json.dumps({'submit_error':str(e)[:120]}))
")
  fi

  python3 - "$i" "$TICK" "$S/_fire.err" "$SUB" >> "$OUT" <<'PY'
import sys, json
i, tick, errfile, sub = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
row = {"pass": int(i), "tick": int(tick)}
try:
    lines = [l for l in open(errfile).read().strip().splitlines() if l.strip().startswith("{")]
    rec = json.loads(lines[-1]) if lines else {}
    row["status"] = rec.get("status")
    row["n_rows"] = rec.get("n_rows")
    row["n_planned"] = rec.get("n_planned")
    row["n_abstained"] = rec.get("n_abstained")
    s = rec.get("solver") or {}
    row["peak_kw"] = s.get("site_peak_kw")
    row["tardy_min"] = s.get("total_tardy_min")
    row["pass1"] = s.get("pass1_status")
    row["reproducible"] = s.get("reproducible")
    row["det_time_s"] = s.get("deterministic_time")
    row["err"] = (rec.get("error") or "")[:120]
except Exception as e:
    row["fire_parse_error"] = str(e)[:120]
try:
    row["submit"] = json.loads(sub) if sub != "none" else None
except Exception:
    row["submit"] = sub[:120]
print(json.dumps(row))
PY
  sleep "$SLP"
done
echo "DRIVER DONE"
