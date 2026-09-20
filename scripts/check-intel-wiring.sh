#!/usr/bin/env bash
# ============================================================================
# check-intel-wiring.sh — is the ottoq-intelligence sidecar actually reachable
# from this project, end to end?
#
# WHY THIS EXISTS. "CP-SAT is dark because the host is not running" was repeated
# for days as a single fact. It is two facts, and on 2026-09-20 only one of them
# was true:
#
#   * the EC2 box did not answer /health  — true;
#   * "the secrets are set, we just need the box" — FALSE. None of
#     OTTOQ_INTEL_URL / OTTOQ_INTEL_TOKEN / OTTOQ_BRIDGE_TOKEN existed on the
#     project at all. Eleven secrets were set and not one of them was these, so
#     bringing the box up would have changed nothing for ottoq-cpsat-propose,
#     which reads both env vars at its line 43-44 and bails when either is null.
#
# Two independent gaps that present as one symptom is exactly the shape a
# checklist loses and a script does not. So this is the script.
#
# It also separates the two functions, which fail DIFFERENTLY and would
# otherwise be diagnosed together:
#
#   ottoq-cpsat-propose   repo == deployed (v5, verified by check-edge-drift.sh).
#                         Fails CLOSED on a missing env var: no host, no call.
#   ottoq-energy-mpc      the DEPLOYED v4 differs from the repo and carries
#                         `?? "<literal>"` fallbacks for all three variables, so
#                         it does NOT fail closed — it silently uses a stale
#                         hardcoded host. That is the acknowledged exception in
#                         check-edge-drift.sh (G69, parked by the founder). This
#                         script does not re-argue it; it just refuses to let a
#                         green energy-mpc be read as "the wiring is fine",
#                         because that green can come from a literal in the
#                         deployed body rather than from configuration.
#
# NEVER PRINTS A SECRET VALUE. The Management API returns `value` alongside
# `name`; this script reads the URL to probe it and emits only a redacted form
# (scheme + host-tail + port). Tokens are reported as present/absent only, never
# echoed, never written to a file — same discipline as the access token itself.
#
# Usage:  SUPABASE_ACCESS_TOKEN=sbp_... scripts/check-intel-wiring.sh
#         exit 0 = every layer wired and the host answered
#         exit 1 = a named gap (missing secret, unreachable host)
#         exit 2 = could not check — NEVER reported as a pass
# ============================================================================
set -uo pipefail

PROJECT_REF="${OTTOQ_PROJECT_REF:-gxdrcyphqjzjsuhxuqtg}"
API="https://api.supabase.com/v1/projects/${PROJECT_REF}"
HEALTH_TIMEOUT="${OTTOQ_HEALTH_TIMEOUT:-15}"
REQUIRED=(OTTOQ_INTEL_URL OTTOQ_INTEL_TOKEN OTTOQ_BRIDGE_TOKEN)

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "check-intel-wiring: SUPABASE_ACCESS_TOKEN is unset, so nothing was checked."
  echo "  REFUSING to report a pass without checking. exit 2"
  exit 2
fi
for bin in curl python3; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "check-intel-wiring: $bin is not available. REFUSING to report a pass. exit 2"
    exit 2
  }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

# ── 1. the three secrets ────────────────────────────────────────────────────
code=$(curl -s -o "$TMP/secrets.json" -w '%{http_code}' \
         -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" "${API}/secrets")
if [[ "$code" != "200" ]]; then
  echo "check-intel-wiring: secrets endpoint returned HTTP $code, nothing compared. exit 2"
  exit 2
fi

echo "── secrets on ${PROJECT_REF}"
for name in "${REQUIRED[@]}"; do
  if python3 - "$TMP/secrets.json" "$name" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
sys.exit(0 if any(r.get("name") == sys.argv[2] for r in rows) else 1)
PY
  then
    printf '   PRESENT  %s\n' "$name"
  else
    printf '   MISSING  %s\n' "$name"
    FAIL=1
  fi
done

# ── 2. the host ─────────────────────────────────────────────────────────────
# Read the URL to probe it; emit it redacted. A host is not a credential, but
# this repo's standing rule is that neither the intel host nor its token is
# written into any committed file, so the script resolves it at runtime.
URL="$(python3 - "$TMP/secrets.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
print(next((r.get("value") or "" for r in rows if r.get("name") == "OTTOQ_INTEL_URL"), ""))
PY
)"

echo "── host"
if [[ -z "$URL" ]]; then
  echo "   SKIPPED  OTTOQ_INTEL_URL is not set, so there is no host to probe."
  echo "            This is the gap, not a flaky network: set the secret first."
  FAIL=1
else
  REDACTED="$(python3 - "$URL" <<'PY'
import sys
from urllib.parse import urlsplit
u = urlsplit(sys.argv[1])
host = u.hostname or "?"
tail = host if len(host) <= 4 else "***" + host[-4:]
print(f"{u.scheme}://{tail}:{u.port or '-'}")
PY
)"
  hcode=$(curl -s -o "$TMP/health.json" -m "$HEALTH_TIMEOUT" \
            -w '%{http_code}' "${URL%/}/health" 2>/dev/null || echo 000)
  if [[ "$hcode" == "200" ]]; then
    echo "   OK       ${REDACTED}/health -> 200"
    python3 - "$TMP/health.json" <<'PY' || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("            optimizers:", d.get("optimizers"), "service:", d.get("service"))
except Exception:
    pass
PY
  elif [[ "$hcode" == "000" ]]; then
    echo "   DOWN     ${REDACTED}/health did not answer within ${HEALTH_TIMEOUT}s"
    echo "            The box is stopped, the security group blocks 8080, or the IP moved."
    FAIL=1
  else
    echo "   FAIL     ${REDACTED}/health -> HTTP ${hcode}"
    echo "            503 with a reachable box means OTTOQ_API_TOKEN is unset in the"
    echo "            container — the service refuses every request rather than serving"
    echo "            them unauthenticated (deploy/DEPLOY_EC2.md, since 2026-09-07)."
    FAIL=1
  fi
fi

# ── 3. the callers ──────────────────────────────────────────────────────────
code=$(curl -s -o "$TMP/fns.json" -w '%{http_code}' \
         -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" "${API}/functions")
echo "── callers"
if [[ "$code" != "200" ]]; then
  echo "   UNKNOWN  functions endpoint returned HTTP $code"
  FAIL=1
else
  python3 - "$TMP/fns.json" <<'PY'
import json, sys
want = {"ottoq-cpsat-propose": "/assign  (CP-SAT)",
        "ottoq-energy-mpc":    "/optimize/energy  (MPC)"}
rows = {x.get("slug"): x for x in json.load(open(sys.argv[1]))}
for slug, what in want.items():
    r = rows.get(slug)
    if not r:
        print(f"   MISSING  {slug} is not deployed at all -> {what}")
    else:
        print(f"   {r.get('status','?'):8} {slug} v{r.get('version')} -> {what}")
PY
  echo "            ottoq-energy-mpc reaching the host proves nothing about"
  echo "            configuration: its DEPLOYED body carries literal fallbacks for all"
  echo "            three variables (check-edge-drift.sh's acknowledged exception), so it"
  echo "            can succeed against a stale hardcoded host with every secret absent."
  echo "            ottoq-cpsat-propose has no fallback and is the honest signal."
fi

# ── 4. what the ledger says actually happened ───────────────────────────────
# Evidence rather than configuration: ottoq_intelligence_ledger is class=evidence
# and survives the demo purge, so this answers "when did the sidecar last really
# answer" even after ottoq_energy_commands and the invocation log are gone.
echo "── evidence (public.ottoq_intelligence_ledger)"
SQL="SELECT provider, calls, last_call FROM public.ottoq_intelligence_ledger \
WHERE provider IN ('cpsat_service','nvidia_cuopt','nvidia_nemotron') ORDER BY provider"
code=$(curl -s -o "$TMP/led.json" -w '%{http_code}' -X POST \
         -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
         -H 'Content-Type: application/json' \
         -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$SQL")" \
         "${API}/database/query")
#: The query endpoint answers 201, not 200 -- accept both rather than reporting a
#: healthy ledger as UNKNOWN, which is how this section read on its first run.
if [[ "$code" != "200" && "$code" != "201" ]]; then
  echo "   UNKNOWN  query returned HTTP $code"
else
  python3 - "$TMP/led.json" <<'PY'
import json, sys
try:
    for r in json.load(open(sys.argv[1])):
        print(f"   {r.get('provider','?'):18} calls={r.get('calls')}  last={r.get('last_call')}")
except Exception as e:
    print("   UNKNOWN  could not parse:", e)
PY
  echo "            A cpsat_service last_call far in the past with the secrets absent is"
  echo "            consistent, not contradictory: those calls predate their removal."
fi

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "check-intel-wiring: wired and reachable. OK"
  exit 0
fi
echo "check-intel-wiring: gaps named above. exit 1"
exit 1
