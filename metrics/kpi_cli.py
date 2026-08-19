"""C6 — the reproducibility CLI: run ID in, five KPIs out, deterministically.

    python3 metrics/kpi_cli.py <sim_run_id>

Connection: set OTTOQ_DB_URL (a postgres:// URL) or standard PG* env vars.
The CLI is a thin, deterministic shell over public.ottoq_kpi_five(uuid)
(migration 0044): pure SQL over committed views, no clock reads. Output is
sorted-key JSON — the same run ID always produces the same bytes, which is the
credibility rule ("no number ships without a run ID") made operational.
"""
import json
import os
import subprocess
import sys
import uuid


def kpi_five(run_id: str) -> dict:
    uuid.UUID(run_id)  # refuse injection-shaped input before it nears psql
    cmd = ["psql", "-X", "-t", "-A", "-v", "ON_ERROR_STOP=1",
           "-c", f"SELECT public.ottoq_kpi_five('{run_id}'::uuid);"]
    url = os.environ.get("OTTOQ_DB_URL")
    if url:
        cmd.insert(1, url)
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.stderr.write(out.stderr)
        raise SystemExit(2)
    payload = out.stdout.strip()
    if not payload or payload == "":
        raise SystemExit(f"no KPI row for run {run_id}")
    return json.loads(payload)


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    print(json.dumps(kpi_five(sys.argv[1]), indent=1, sort_keys=True))


if __name__ == "__main__":
    main()
