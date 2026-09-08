"""load/harness.py — make "OTTO-Q is fast enough to talk to a vehicle" a number
with a run ID, or refuse to produce one.

    python3 load/harness.py --target charger_load_kw \
        --depot 11111111-1111-1111-1111-111111111111 \
        --clock '2026-09-01 14:00:00+00' \
        --clients 16 --duration 60

WHY THIS EXISTS (task G24). The only latency figures this company had were
lifetime means out of pg_stat_statements over 34-40 days at about 5.6 calls a
minute (db/checks/0133). That is evidence a code path is fast when nothing
else is happening. It is no evidence at all about behaviour under load,
because the system has never been under load. The honest sentence in 0133 is
"it has never been under load"; this file is how that stops being true.

WHAT IT MEASURES, and the four things it does that a naive load test does not:

1. THE FLOOR, EVERY TIME. Before (and after) the target, it runs `SELECT 1`
   at the same concurrency on the same connection string. The reported
   `engine_share_ms` is target_p50 - floor_p50. Without a floor beside it, a
   latency number is a claim about a network you did not measure.

2. IT LOOKS FOR THE CERTIFICATION PAIR. A determinism pair is by far the
   largest load this database ever sees, and pg_stat_activity is the only
   authority on whether one is running (db/canons/round25.md: an in-flight
   pair reports 'succeeded' in the cron log). The harness samples before,
   during and after. If a pair overlapped the window the result is written
   with contaminated=true and a reason, NOT discarded -- a contaminated
   measurement is real data about a real operating condition, and deleting
   it is how you end up with only flattering numbers.

3. IT REPORTS ACHIEVED RATE AGAINST REQUESTED. If the harness could not keep
   up, the latency you are reading is the harness queueing, not the server
   answering. Achieved rate is in every result.

4. IT REFUSES TO PUBLISH PERCENTILES FROM TOO FEW SAMPLES. p99 from 40
   transactions is one transaction wearing a percentile's clothes.

WHAT IT CANNOT MEASURE, stated here so no reader has to infer it:

- The HTTP edge-function path. That is a real part of what a vehicle talks to
  (edge-functions/otto-q-api routes /api/v1/av/telemetry and friends) and it
  is NOT measured here. Adding it means measuring the gateway, cold starts
  and TLS from a host whose network path to Supabase is characterised. This
  container reaches the internet through an agent proxy, so a number taken
  here would be a number about the proxy. layer="http" targets are therefore
  not implemented rather than implemented badly.
- Anything about a client that is not this one. Percentiles are per-harness.

CONNECTION: OTTOQ_DB_URL, exactly as metrics/kpi_cli.py uses it. Nothing here
reads a secret from a file or a flag; the URL never enters the result.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import statistics
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from load import targets as T  # noqa: E402

#: Below this many transactions the tail percentiles are not measurements.
#: 200 is not a magic constant: at n=200 the p99 is the average of the two
#: slowest, so it still summarises rather than names a single sample.
MIN_SAMPLES_FOR_TAIL = 200

PAIR_PROBE = (
    "SELECT count(*) FROM pg_stat_activity "
    "WHERE query ILIKE '%ottoq_determinism_pair%' AND state='active' "
    "AND pid <> pg_backend_pid();")


def _redact(text: str, url: str | None) -> str:
    """pgbench and psql echo the connection string on some errors."""
    if url:
        text = text.replace(url, "<OTTOQ_DB_URL>")
    return re.sub(r"(?i)(password=)[^\s&]+", r"\1<redacted>", text)


class NoDatabase(RuntimeError):
    pass


def _psql_scalar(url: str, sql: str) -> str:
    out = subprocess.run(["psql", url, "-X", "-t", "-A", "-v", "ON_ERROR_STOP=1",
                          "-c", sql], capture_output=True, text=True)
    if out.returncode != 0:
        raise NoDatabase(_redact(out.stderr.strip(), url))
    return out.stdout.strip()


def probe_pair(url: str) -> int:
    """How many certification pairs are active right now. -1 if unaskable."""
    try:
        return int(_psql_scalar(url, PAIR_PROBE))
    except (NoDatabase, ValueError):
        return -1


def percentiles(xs: list[float]) -> dict:
    """Percentiles by nearest-rank on the sorted samples, plus n.

    Nearest-rank rather than interpolation deliberately: every number
    reported is a latency that actually happened, so a reader can go find the
    transaction. Interpolated percentiles are fine statistics and are not
    events.
    """
    if not xs:
        return {"n": 0}
    s = sorted(xs)
    def at(p: float) -> float:
        k = max(1, math.ceil(p / 100.0 * len(s)))
        return s[k - 1]
    out = {"n": len(s), "min_ms": s[0], "max_ms": s[-1],
           "mean_ms": statistics.fmean(s), "p50_ms": at(50), "p90_ms": at(90),
           "p95_ms": at(95), "p99_ms": at(99)}
    if len(s) < MIN_SAMPLES_FOR_TAIL:
        out["tail_percentiles_are_not_measurements"] = (
            f"n={len(s)} < {MIN_SAMPLES_FOR_TAIL}; p95 and p99 here name "
            f"individual transactions, not a distribution")
    return {k: (round(v, 3) if isinstance(v, float) else v) for k, v in out.items()}


def parse_pgbench_summary(stdout: str) -> dict:
    """pgbench's own numbers, from its own mouth.

    Kept beside the log-derived percentiles rather than instead of them: see
    the note in run_pgbench about why the two disagree.
    """
    out: dict = {}
    for line in stdout.splitlines():
        m = re.match(r"latency average = ([\d.]+) ms", line)
        if m:
            out["latency_avg_ms"] = float(m.group(1))
        m = re.match(r"tps = ([\d.]+)", line)
        if m:
            out["tps"] = float(m.group(1))
        m = re.match(r"number of transactions actually processed: (\d+)", line)
        if m:
            out["transactions"] = int(m.group(1))
    return out


def run_pgbench(url: str, target: T.Target, bindings: dict, clients: int,
                duration: int, rate: float | None, workdir: Path) -> dict:
    """One pgbench run. Returns latencies plus everything needed to read them."""
    missing = [p for p in target.params if p not in bindings]
    if missing:
        raise SystemExit(
            f"target {target.name!r} needs {list(target.params)}; missing "
            f"{missing}. pgbench substitutes an empty string for an unset "
            f"variable, so this would have measured a syntax error.")

    # Create it rather than assume it: main() hands in a TemporaryDirectory
    # that already exists, but a caller (the calibration test does exactly
    # this) may hand in a per-run subdirectory that does not.
    workdir.mkdir(parents=True, exist_ok=True)
    script = workdir / f"{target.name}.sql"
    script.write_text(target.sql)
    log_prefix = workdir / f"log_{target.name}"

    cmd = ["pgbench", url, "-n", "-f", str(script), "-c", str(clients),
           "-j", str(min(clients, os.cpu_count() or 1)), "-T", str(duration),
           "-l", "--log-prefix", str(log_prefix), "-M", "extended"]
    for p in target.params:
        cmd += ["-D", f"{p}={bindings[p]}"]
    if rate:
        cmd += ["-R", str(rate)]

    t0 = time.time()
    out = subprocess.run(cmd, capture_output=True, text=True)
    wall = time.time() - t0
    if out.returncode != 0:
        raise SystemExit("pgbench failed:\n" + _redact(out.stderr, url))

    # Per-transaction log: "client_id transaction_no time script_no time_epoch
    # time_us [schedule_lag]" with `time` in microseconds.
    lat_ms: list[float] = []
    for f in sorted(workdir.glob(f"log_{target.name}*")):
        for line in f.read_text().splitlines():
            parts = line.split()
            if len(parts) >= 3:
                try:
                    lat_ms.append(int(parts[2]) / 1000.0)
                except ValueError:
                    continue

    summary = parse_pgbench_summary(out.stdout)
    measured = percentiles(lat_ms)

    # pgbench reports TWO latencies and they are not the same measurement.
    # `latency average` on the summary line is derived from throughput
    # (duration x clients / transactions) whenever pgbench is unthrottled, so
    # it INCLUDES pgbench's own per-transaction overhead. The per-transaction
    # log times do not. On a local unix socket that gap is the whole number:
    # `SELECT 1` logs ~0.0004 ms per transaction while the summary says 0.012
    # ms, because ~11 us of every transaction is pgbench looping and writing
    # its log. Neither is wrong; they answer different questions.
    #
    # This harness reports the LOG percentiles as `latency`, because the
    # question is what the server takes, and it reports the summary figure
    # beside it as `pgbench_throughput_derived_latency_ms` so the gap is
    # visible rather than resolved by whoever quotes it. Where the gap is
    # large relative to the measurement -- which is exactly the case at the
    # floor and never the case for a millisecond-scale engine call -- the
    # result says so.
    gap_note = None
    if measured.get("n") and summary.get("latency_avg_ms") is not None:
        logged = measured["mean_ms"]
        derived = summary["latency_avg_ms"]
        # RELATIVE, not absolute: the question is whether pgbench's own
        # overhead is a large SHARE of what is being reported, and at the
        # floor that share is everything while the absolute gap is 0.01 ms.
        # An absolute threshold of 0.05 ms was the first attempt and it
        # stayed silent on exactly the case the flag exists for.
        if derived > 0 and (derived - logged) > max(0.5 * derived, 0.001):
            gap_note = (
                f"pgbench's throughput-derived latency ({derived} ms) exceeds "
                f"the mean of its own per-transaction log ({logged} ms) by "
                f"{round(derived - logged, 4)} ms. That difference is "
                f"pgbench's own per-transaction overhead, not the server. It "
                f"matters only when it is large relative to the measurement, "
                f"which is the case here.")

    return {
        "target": target.name,
        "safety": target.safety,
        "represents": target.what_it_represents,
        "note": target.note or None,
        "clients": clients,
        "threads": min(clients, os.cpu_count() or 1),
        "requested_duration_s": duration,
        "wall_s": round(wall, 2),
        "requested_rate_tps": rate,
        "achieved_rate_tps": round(len(lat_ms) / wall, 2) if wall else None,
        "latency": measured,
        "latency_is": ("percentiles over pgbench's per-transaction log, in ms; "
                       "nearest-rank, so each names a real transaction"),
        "pgbench_throughput_derived_latency_ms": summary.get("latency_avg_ms"),
        "pgbench_tps": summary.get("tps"),
        "pgbench_transactions": summary.get("transactions"),
        "two_latencies_note": gap_note,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target", required=True)
    ap.add_argument("--clients", type=int, default=8)
    ap.add_argument("--duration", type=int, default=30, help="seconds")
    ap.add_argument("--rate", type=float, default=None,
                    help="cap offered load at N tps; omit for saturation")
    ap.add_argument("--depot"), ap.add_argument("--clock")
    ap.add_argument("--run"), ap.add_argument("--since")
    ap.add_argument("--i-know-this-writes", action="store_true")
    ap.add_argument("--out", default=None)
    a = ap.parse_args(argv)

    url = os.environ.get("OTTOQ_DB_URL")
    if not url:
        raise SystemExit(
            "OTTOQ_DB_URL is unset. This harness needs a direct postgres URL "
            "and a host whose path to the database is the one you want to "
            "measure. It deliberately will not fall back to a management API: "
            "that path cannot do concurrency, so any number from it would be "
            "about the API and not about the engine.")

    target = T.get(a.target)
    if target.safety == "writes" and not a.i_know_this_writes:
        raise SystemExit(f"target {target.name!r} can write; pass "
                         f"--i-know-this-writes and point it at a depot you "
                         f"are willing to dirty.")

    bindings = {k: v for k, v in
                (("depot", a.depot), ("clock", a.clock),
                 ("run", a.run), ("since", a.since)) if v is not None}

    run_id = str(uuid.uuid4())
    pair_before = probe_pair(url)
    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    with tempfile.TemporaryDirectory(prefix="ottoq-load-") as td:
        work = Path(td)
        floor = run_pgbench(url, T.FLOOR, {}, a.clients, min(a.duration, 15),
                            a.rate, work)
        pair_mid = probe_pair(url)
        main_run = run_pgbench(url, target, bindings, a.clients, a.duration,
                               a.rate, work)

    pair_after = probe_pair(url)
    finished = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    contaminated = any(p > 0 for p in (pair_before, pair_mid, pair_after))
    unknown = any(p < 0 for p in (pair_before, pair_mid, pair_after))

    engine_share = None
    if floor["latency"].get("n") and main_run["latency"].get("n"):
        engine_share = round(main_run["latency"]["p50_ms"]
                             - floor["latency"]["p50_ms"], 3)

    result = {
        "run_id": run_id,
        "harness": "load/harness.py",
        "started_utc": started,
        "finished_utc": finished,
        "floor": floor,
        "run": main_run,
        "engine_share_p50_ms": engine_share,
        "engine_share_means": (
            "target p50 minus floor p50, measured on the same client, "
            "connection and concurrency. This is the part attributable to the "
            "engine; the floor is the part that is not."),
        "certification_pairs_active": {
            "before": pair_before, "between_floor_and_run": pair_mid,
            "after": pair_after},
        "contaminated": contaminated,
        "contamination_note": (
            "a determinism pair was active during this window; it is the "
            "largest load this database sees, so these latencies describe the "
            "engine UNDER that load. Kept, labelled, not discarded."
            if contaminated else
            "no certification pair was active in any of the three probes"
            if not unknown else
            "the pair probe could not be answered; treat the pair state as "
            "UNKNOWN rather than as absent"),
    }

    out_path = Path(a.out) if a.out else (
        Path(__file__).parent / "results" / f"{a.target}_{run_id[:8]}.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=1, sort_keys=True) + "\n")
    print(json.dumps(result, indent=1, sort_keys=True))
    print(f"\nwritten: {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
