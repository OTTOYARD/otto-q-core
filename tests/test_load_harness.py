"""The load harness, calibrated against a known quantity before it is pointed
at an unknown one.

WHY CALIBRATION AND NOT JUST UNIT TESTS. The harness exists to answer "is
OTTO-Q fast enough to talk to a vehicle", and the only reason to believe its
answer is that it reads a workload whose latency we already know and reports
that latency. So the central test here builds a throwaway local Postgres,
asks it for a statement that sleeps for a known 20 ms, and requires the
harness to say 20 ms -- and requires the FLOOR beside it to say nearly zero,
because a floor that is not near zero means the subtraction that produces
`engine_share_p50_ms` is measuring the wrong thing.

The database tests skip rather than fail when the cluster cannot be built
(no initdb, no pgbench, or running as root, which initdb refuses). A skip is
honest; a green tick from a test that silently did nothing is not, so the
skip reasons below all name what was missing.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from load import harness as H
from load import targets as T


# --------------------------------------------------------------------------
# Pure: the statistics, and the guards that fire before any process starts.
# --------------------------------------------------------------------------

def test_percentiles_name_samples_that_actually_happened():
    """Nearest-rank, so every reported latency is a transaction a reader can
    go and find. Interpolated percentiles are respectable statistics and are
    not events, and this harness reports events."""
    xs = [float(i) for i in range(1, 101)]
    p = H.percentiles(xs)
    assert p["n"] == 100
    assert p["min_ms"] == 1.0 and p["max_ms"] == 100.0
    assert p["p50_ms"] == 50.0 and p["p90_ms"] == 90.0
    assert p["p95_ms"] == 95.0 and p["p99_ms"] == 99.0
    for k in ("p50_ms", "p95_ms", "p99_ms"):
        assert p[k] in xs, f"{k} is not one of the samples"


def test_percentiles_of_nothing_claim_nothing():
    assert H.percentiles([]) == {"n": 0}


def test_the_tail_is_labelled_when_there_is_not_enough_of_it():
    """p99 of 40 transactions is one transaction wearing a percentile's
    clothes. The harness still reports it -- suppressing it would hide a real
    measurement -- but it says so in the result, in the result file, where a
    reader quoting the number will see it."""
    few = H.percentiles([1.0] * 40)
    assert "tail_percentiles_are_not_measurements" in few
    assert "40" in few["tail_percentiles_are_not_measurements"]

    many = H.percentiles([1.0] * H.MIN_SAMPLES_FOR_TAIL)
    assert "tail_percentiles_are_not_measurements" not in many


def test_a_target_with_unbound_parameters_is_refused_before_pgbench_starts():
    """pgbench substitutes an EMPTY STRING for a variable that was never set
    with -D. `SELECT f(::uuid)` is a syntax error, which fails very fast, and
    a load test that measures a syntax error reports an excellent number."""
    with pytest.raises(SystemExit) as e:
        H.run_pgbench("postgresql://nowhere", T.get("charger_load_kw"),
                      {"depot": "x"},  # `clock` deliberately missing
                      clients=1, duration=1, rate=None, workdir=Path("/tmp"))
    msg = str(e.value)
    assert "clock" in msg and "empty string" in msg


def test_the_floor_does_no_work():
    """The floor's entire value is that it does nothing, so that subtracting
    it isolates the engine. A floor that grew a WHERE clause would quietly
    make every engine_share in every committed result too small."""
    assert T.FLOOR.sql.strip() == "SELECT 1;"
    assert T.FLOOR.safety == "read_only"


def test_every_declared_target_states_its_safety_and_what_it_represents():
    for name, tgt in T.TARGETS.items():
        assert tgt.safety in ("read_only", "writes"), name
        assert tgt.what_it_represents.strip(), name
        assert tgt.sql.strip().endswith(";"), name
        for p in tgt.params:
            assert f":{p}" in tgt.sql, f"{name} declares param {p} it never uses"
        # `(?<!:)` so a `::uuid` cast is not read as a variable named uuid.
        for used in set(re.findall(r"(?<!:):([a-z_]+)", tgt.sql)):
            assert used in tgt.params, f"{name} uses :{used} without declaring it"


def test_the_connection_string_never_reaches_a_result():
    url = "postgresql://someone:hunter2@db.example/postgres"
    dirty = f"could not connect to {url} — password=hunter2"
    clean = H._redact(dirty, url)
    assert "hunter2" not in clean and url not in clean


# --------------------------------------------------------------------------
# The calibration: a known 20 ms, read back by the instrument.
# --------------------------------------------------------------------------

PGBIN = next((p for p in sorted(Path("/usr/lib/postgresql").glob("*/bin"),
                                reverse=True)), None)
SLEEP_MS = 20


def _skip_reason() -> str | None:
    if not shutil.which("pgbench"):
        return "pgbench is not installed"
    if PGBIN is None or not (PGBIN / "initdb").exists():
        return "no postgres server binaries (only the client is installed)"
    if os.geteuid() == 0:
        return ("running as root; initdb refuses to run as root and this test "
                "will not silently drop privileges")
    return None


@pytest.fixture(scope="module")
def local_cluster():
    reason = _skip_reason()
    if reason:
        pytest.skip(reason)
    with tempfile.TemporaryDirectory(prefix="ottoq-cal-") as td:
        base = Path(td)
        data = base / "data"
        subprocess.run([str(PGBIN / "initdb"), "-D", str(data), "-A", "trust",
                        "-U", "postgres"], check=True, capture_output=True)
        subprocess.run(
            [str(PGBIN / "pg_ctl"), "-D", str(data), "-l", str(base / "log"),
             "-o", f"-p 55433 -k {base} -c listen_addresses='' "
                   f"-c log_min_messages=warning", "start"],
            check=True, capture_output=True)
        url = f"postgresql:///postgres?host={base}&port=55433&user=postgres"
        try:
            time.sleep(1)
            yield url
        finally:
            subprocess.run([str(PGBIN / "pg_ctl"), "-D", str(data), "-m",
                            "immediate", "stop"], capture_output=True)


def test_the_instrument_reads_a_known_latency(local_cluster, tmp_path):
    """The whole argument for trusting this harness, in one test.

    A statement that sleeps 20 ms must come back as about 20 ms, and the
    floor beside it must come back as about nothing. If the first fails the
    harness cannot measure; if the second fails, `engine_share_p50_ms` --
    the number the harness exists to produce -- is subtracting noise from
    signal and the result files are wrong in a direction nobody would spot.
    """
    known = T.Target(
        name="calibration_sleep",
        layer="db", safety="read_only",
        what_it_represents=f"a statement whose latency is known to be {SLEEP_MS} ms",
        sql=f"SELECT pg_sleep({SLEEP_MS / 1000.0});\n")

    floor = H.run_pgbench(local_cluster, T.FLOOR, {}, clients=4, duration=4,
                          rate=None, workdir=tmp_path / "floor")
    meas = H.run_pgbench(local_cluster, known, {}, clients=4, duration=4,
                         rate=None, workdir=tmp_path / "known")

    assert floor["latency"]["n"] > 0, "the floor produced no transactions"
    assert meas["latency"]["n"] > 0, "the calibration produced no transactions"

    # The floor is a local unix socket doing nothing: sub-millisecond, and
    # certainly a small fraction of the known sleep. If this fails the
    # subtraction is not isolating anything.
    assert floor["latency"]["p50_ms"] < SLEEP_MS / 4, (
        f"floor p50 {floor['latency']['p50_ms']} ms is not near zero on a "
        f"local socket; engine_share would be subtracting real work")

    # pg_sleep is a FLOOR on the duration, never a ceiling -- the backend
    # still has to be scheduled -- so the band is one-sided-tight and
    # generous upward rather than symmetric.
    p50 = meas["latency"]["p50_ms"]
    assert SLEEP_MS <= p50 < SLEEP_MS * 3, (
        f"asked for {SLEEP_MS} ms and the instrument read {p50} ms")

    share = p50 - floor["latency"]["p50_ms"]
    assert abs(share - SLEEP_MS) < SLEEP_MS, (
        f"engine share {share:.2f} ms should recover the known {SLEEP_MS} ms")


def test_achieved_rate_is_reported_so_a_slow_harness_cannot_masquerade(
        local_cluster, tmp_path):
    """4 clients each sleeping 20 ms is at most 200 tps. If the harness ever
    reports a rate far above what the workload physically permits, the
    latencies are the harness's bookkeeping and not the server's answers."""
    known = T.Target(name="calibration_sleep", layer="db", safety="read_only",
                     what_it_represents="known sleep",
                     sql=f"SELECT pg_sleep({SLEEP_MS / 1000.0});\n")
    r = H.run_pgbench(local_cluster, known, {}, clients=4, duration=3,
                      rate=None, workdir=tmp_path / "rate")
    ceiling = 4 * 1000.0 / SLEEP_MS
    assert 0 < r["achieved_rate_tps"] <= ceiling * 1.2, (
        f"{r['achieved_rate_tps']} tps against a physical ceiling of "
        f"{ceiling} tps for this workload")


def test_pgbench_reports_two_latencies_and_the_harness_keeps_both():
    """Measured on the local cluster while building this: `SELECT 1` over a
    unix socket logs a mean of 0.0004 ms per transaction while pgbench's own
    summary line says 0.011 ms -- a factor of 29. Neither is a lie. The
    summary figure is derived from throughput (duration x clients /
    transactions) and therefore carries pgbench's own per-transaction
    overhead; the log times do not.

    Picking one silently is how a floor ends up 29x wrong. The harness keeps
    both and flags the gap when it is large relative to the measurement."""
    s = ("number of transactions actually processed: 1085724\n"
         "latency average = 0.011 ms\n"
         "tps = 362089.648307 (without initial connection time)\n")
    got = H.parse_pgbench_summary(s)
    assert got == {"transactions": 1085724, "latency_avg_ms": 0.011,
                   "tps": 362089.648307}


def test_the_gap_between_the_two_latencies_is_flagged_only_when_it_matters(
        local_cluster, tmp_path):
    """At the floor the gap is the whole number and must be flagged. For a
    20 ms workload pgbench's ~0.01 ms of overhead is noise and flagging it
    would be alarm fatigue, so it must NOT be flagged."""
    floor = H.run_pgbench(local_cluster, T.FLOOR, {}, clients=4, duration=3,
                          rate=None, workdir=tmp_path / "gapf")
    assert floor["two_latencies_note"], (
        "the floor's two latencies differ by orders of magnitude and the "
        "result said nothing about it")

    known = T.Target(name="calibration_sleep", layer="db", safety="read_only",
                     what_it_represents="known sleep",
                     sql=f"SELECT pg_sleep({SLEEP_MS / 1000.0});\n")
    slow = H.run_pgbench(local_cluster, known, {}, clients=4, duration=3,
                         rate=None, workdir=tmp_path / "gaps")
    assert slow["two_latencies_note"] is None, (
        f"flagged a gap that does not matter: {slow['two_latencies_note']}")


def test_a_second_run_into_the_same_directory_is_refused(local_cluster, tmp_path):
    """Found by running the CLI end to end rather than by testing its parts.

    `python3 load/harness.py --target floor` ran the floor and then ran the
    target -- also the floor -- into one TemporaryDirectory. The per-
    transaction logs are read back with a glob, so the second run measured both
    and reported 685,632 tps where pgbench's own summary said 349,191: exactly
    double, over exactly twice the samples. The percentiles were computed over
    two runs while describing one, and nothing about them looked wrong. Only
    the rate disagreeing with pgbench's own number gave it away.

    So the invariant is enforced at the door, and it is loud."""
    d = tmp_path / "shared"
    first = H.run_pgbench(local_cluster, T.FLOOR, {}, clients=2, duration=2,
                          rate=None, workdir=d)
    assert first["latency"]["n"] > 0

    with pytest.raises(SystemExit) as e:
        H.run_pgbench(local_cluster, T.FLOOR, {}, clients=2, duration=2,
                      rate=None, workdir=d)
    assert "own directory" in str(e.value)


def test_the_reported_rate_agrees_with_pgbenchs_own(local_cluster, tmp_path):
    """The cross-check that caught the shared-directory bug, kept as a test.

    achieved_rate_tps is computed from the number of log lines over wall time;
    pgbench_tps is pgbench's own. They are derived independently and must agree
    within the slack of the harness's extra wall-clock (process spawn, log
    read). If they diverge by more than that, the harness is counting
    transactions that are not this run's."""
    r = H.run_pgbench(local_cluster, T.FLOOR, {}, clients=2, duration=3,
                      rate=None, workdir=tmp_path / "agree")
    mine, theirs = r["achieved_rate_tps"], r["pgbench_tps"]
    assert 0.5 < mine / theirs < 1.05, (
        f"harness says {mine} tps, pgbench says {theirs} — a ratio near 2 "
        f"means a foreign log file was globbed into this run")
