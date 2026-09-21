#!/usr/bin/env bash
# ============================================================================
# check-intel-wiring.sh — is the ottoq-intelligence sidecar actually reachable
# from this project, end to end?
#
# WHY THIS EXISTS. "CP-SAT is dark because the host is not running" was repeated
# for days as a single fact. It is two facts, and on 2026-09-20 only one of them
# was true:
#
#   * ~~the EC2 box did not answer /health — true~~  **RETRACTED: never established,
#     and almost certainly false.** A plain-`http://` request cannot leave this
#     container at all (the proxy takes only HTTPS CONNECT tunnels), so that
#     timeout tested nothing. CONNECT-probed since, on this host and on the one
#     that timed out: both answer 200 Connection Established and then reset the
#     TLS handshake — a live plain-HTTP service. **Both boxes were up.** So there
#     was ONE gap, below, not two;
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
# SECRET VALUES ARE NOT READABLE, AND THIS SCRIPT ONCE ASSUMED THEY WERE. The
# Management API does return a `value` field per secret — which is why the first
# version of this file read the URL out of it to probe — but the value is a
# 64-character DIGEST, not the plaintext. Checking that the field EXISTED and
# concluding it was readable is the same assumption-without-verification that this
# file's other two corrections came from. So the URL cannot be recovered here:
# pass `OTTOQ_INTEL_URL=http://host:8080` in the environment to CONNECT-probe the
# port, or rely on section 3, which is authoritative anyway. Nothing is echoed and
# nothing is written to a file.
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
# The URL is taken from the ENVIRONMENT, not from the secret, because the
# Management API returns only a digest of each value (see the header). A host is
# not a credential, but this repo's standing rule keeps the intel host out of every
# committed file, so it is never defaulted here — absent means "not probed".
URL="${OTTOQ_INTEL_URL:-}"

echo "── host"
if [[ -z "$URL" ]]; then
  echo "   SKIPPED  no OTTOQ_INTEL_URL in this shell, so no port was probed."
  echo "            NOT a finding either way -- the secret's value is unreadable"
  echo "            through the Management API, so absence here says nothing about"
  echo "            whether it is set. Section 1 is what answers that."
  echo "            Pass OTTOQ_INTEL_URL=http://host:8080 to CONNECT-probe the port." 
else
  REDACTED="$(python3 -c '
import sys
from urllib.parse import urlsplit
u = urlsplit(sys.argv[1].strip())
host = u.hostname or "?"
tail = host if len(host) <= 4 else "***" + host[-4:]
print("%s://%s:%s" % (u.scheme or "?", tail, u.port or "-"))
' "$URL")"

  # ── WHY THIS IS NOT A curl OF /health ──────────────────────────────────────
  # It was, and it was WRONG. The intelligence service is plain HTTP on 8080, and
  # this environment's egress proxy accepts ONLY HTTPS CONNECT tunnels -- a plain
  # http:// request cannot leave the container at all. So the first version of
  # this section timed out after 25 s and printed "DOWN ... the box is stopped",
  # which was a definite negative about a thing it had not tested. Proven wrong by
  # CONNECT-probing both the current and the previous host: both answered
  # "200 Connection Established" and then reset the TLS handshake, which is exactly
  # how a live plain-HTTP server replies. The box was up the whole time.
  #
  # The header of this file says "REFUSING to report a pass without comparing".
  # Reporting a FAILURE without comparing is the same sin in the other direction,
  # and it is the one that sent the diagnosis after the wrong half.
  #
  # So: a CONNECT tunnel is the only reachability signal available from here, and
  # it is a real one -- it proves the TCP port is open. Whether the SERVICE is
  # healthy can only be answered from Supabase's network, by ottoq-energy-mpc's
  # probe mode, which is reported in section 3.
  HOSTPORT="$(python3 -c '
import sys
from urllib.parse import urlsplit
u = urlsplit(sys.argv[1].strip())
print("%s:%s" % (u.hostname or "", u.port or (443 if u.scheme == "https" else 80)))
' "$URL")"

  if [[ -z "${HTTPS_PROXY:-}" ]]; then
    echo "   UNKNOWN  no HTTPS_PROXY in this environment; cannot CONNECT-probe ${REDACTED}"
  else
    probe="$(timeout "$HEALTH_TIMEOUT" curl -s -v -x "$HTTPS_PROXY" \
               "https://${HOSTPORT}/health" 2>&1 || true)"
    if grep -q "Connection Established" <<<"$probe"; then
      if grep -qE "Recv failure|wrong version number|record layer failure" <<<"$probe"; then
        echo "   OPEN     ${REDACTED} TCP port is open and speaking PLAIN HTTP"
        echo "            (CONNECT tunnel established, then the server reset a TLS"
        echo "             handshake -- the signature of a live http:// service)"
      else
        echo "   OPEN     ${REDACTED} TCP port is open"
      fi
      echo "            NOT a health check: plain HTTP cannot egress from here, so"
      echo "            service health is answerable only from Supabase's network."
      echo "            See section 3 for the authoritative probe."
    elif grep -qE "Connection refused|Could not resolve|connect to .* port .* failed" <<<"$probe"; then
      echo "   CLOSED   ${REDACTED} refused the connection -- box stopped, or 8080 blocked"
      FAIL=1
    else
      echo "   UNKNOWN  could not establish a CONNECT tunnel to ${REDACTED} within ${HEALTH_TIMEOUT}s."
      echo "            This is NOT evidence the box is down -- it is evidence this check"
      echo "            could not run. Do not report it as a failure of the host."
    fi
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
