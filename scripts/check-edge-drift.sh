#!/usr/bin/env bash
# ============================================================================
# check-edge-drift.sh — compare edge-functions/ against what is DEPLOYED.
#
# WHY THIS EXISTS, and why the two signals it replaces were both wrong.
#
# G67: the repo was stale on the functions that own the agent/solver loop, and
# nothing detected it. Two drift signals were tried before this one and both
# misreported:
#
#   * the manifest's `version` column is not the API's. `ottoq-wave-admit` read
#     v2 in the 2026-08-03 snapshot and v5 live with an IDENTICAL updated_at, so
#     diffing it flagged ~26 of 28 functions when 6 had changed. 77% false
#     positives, withdrawn 2026-09-19.
#   * `updated_at` replaced it and is better but still wrong. Measured by
#     content hash on 2026-09-19 it gave TWO false positives
#     (ottoq-cuopt-propose and ottoq-assign-optimize were flagged and are
#     byte-identical) and ONE FALSE NEGATIVE — ottoq-energy-mpc, whose
#     updated_at predates the snapshot and which differs by 18 lines, including
#     three hardcoded credential fallbacks the repo removed on 2026-09-07 and
#     which are STILL LIVE. A drift detector that misses the one drift with a
#     secret in it is not a detector.
#
# So this script compares SHA-256 of the actual source, which is the only signal
# that cannot be wrong. It needs no Docker: `--use-api` unbundles server-side.
#
# Usage:  SUPABASE_ACCESS_TOKEN=sbp_... scripts/check-edge-drift.sh
#         exit 0 = every ACTIVE function matches the repo (or is an
#                  acknowledged exception below)
#         exit 1 = drift, named
#         exit 2 = could not check (no token, no CLI) -- NEVER reported as a pass
#
# ACKNOWLEDGED EXCEPTIONS — a function listed here is EXPECTED to differ, and
# the reason must be written next to it. This is not a mute button: an exception
# is a finding that has been read and left in place on purpose.
#
#   ottoq-energy-mpc  the repo copy is the CORRECT one. The deployed v4 still
#                     carries `?? "http://…"` and `?? "<27-char secret>"` for
#                     OTTOQ_INTEL_URL / OTTOQ_INTEL_TOKEN / OTTOQ_BRIDGE_TOKEN,
#                     and lacks the fail-closed guard the repo added
#                     2026-09-07. Syncing the deployed body INTO the repo would
#                     re-commit a live credential, so it must never be done;
#                     the fix is to DEPLOY the repo's version and rotate. G69.
# ============================================================================
set -uo pipefail

PROJECT_REF="${OTTOQ_PROJECT_REF:-gxdrcyphqjzjsuhxuqtg}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)/edge-functions"
EXPECTED_DRIFT=("ottoq-energy-mpc")

if ! command -v supabase >/dev/null 2>&1; then
  echo "check-edge-drift: the Supabase CLI is not installed (npm i -g supabase)."
  echo "  REFUSING to report a pass without comparing. exit 2"
  exit 2
fi
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "check-edge-drift: SUPABASE_ACCESS_TOKEN is unset, so nothing was compared."
  echo "  REFUSING to report a pass without comparing. exit 2"
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! (cd "$WORK" && supabase functions download --use-api \
        --project-ref "$PROJECT_REF" >/dev/null 2>"$WORK/err"); then
  echo "check-edge-drift: download failed:"; sed 's/^/  /' "$WORK/err"
  echo "  REFUSING to report a pass without comparing. exit 2"
  exit 2
fi

PULL="$WORK/supabase/functions"
[[ -d "$PULL" ]] || { echo "check-edge-drift: no functions downloaded. exit 2"; exit 2; }

drift=0; unexpected=0; matched=0
while IFS= read -r -d '' src; do
  rel="${src#"$PULL"/}"
  slug="${rel%%/*}"
  repo_file="$REPO_DIR/$rel"
  if [[ ! -f "$repo_file" ]]; then
    echo "MISSING  $rel — deployed but not in the repo"
    drift=$((drift+1)); unexpected=$((unexpected+1)); continue
  fi
  if [[ "$(sha256sum <"$src" | cut -d' ' -f1)" == "$(sha256sum <"$repo_file" | cut -d' ' -f1)" ]]; then
    matched=$((matched+1)); continue
  fi
  drift=$((drift+1))
  if printf '%s\n' "${EXPECTED_DRIFT[@]}" | grep -qx "$slug"; then
    echo "EXPECTED $rel — acknowledged exception, see the header of this script"
  else
    echo "DRIFT    $rel — repo and deployed disagree"
    unexpected=$((unexpected+1))
  fi
done < <(find "$PULL" -name '*.ts' -print0 | sort -z)

echo
echo "check-edge-drift: $matched matched, $drift differ ($unexpected unexpected)"
[[ $unexpected -eq 0 ]] && { echo "OK"; exit 0; }
exit 1
