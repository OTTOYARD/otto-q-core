"""db/migrations/0645 and 0646, EXECUTED against a stub engine: the nightly run purge runs again, takes only finished
week-old non-production runs from the six tables the learning never reads, yields to a certification, and the
wall-clock retention spares production rule evaluations.

WHY THIS EXISTS. Both procedures delete irreversibly in production, so their claims are tested here by deleting:
which runs are doomed, which tables are touched, what is stamped, and when a certification stops the purge -- with
real COMMITs and a real concurrent session, not by reading source. tests/fixtures/run_purge_stub_engine.sql holds the
live bodies of both procedures as they were before these migrations (md5-pinned), so each migration's P1 guard meets
the definition production has, and the purge that runs here is the purge production runs.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_operator_start_interrupt_sql.py. It uses
$PGHOST/$PGPORT/$PGUSER/$PGPASSWORD when PGHOST is set, else the local cluster on /var/tmp:55432.
"""
import json
import os
import shutil
import subprocess
import time
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "run_purge_stub_engine.sql")
M0645 = os.path.join(ROOT, "db", "migrations",
                     "0645_the_nightly_run_purge_runs_again_and_never_takes_what_the_learning_reads.sql")
M0646 = os.path.join(ROOT, "db", "migrations",
                     "0646_the_wall_clock_retention_never_takes_a_production_runs_shield_log.sql")

SIX = ["ottoq_rule_evaluations", "ottoq_comms_messages", "ottoq_stall_bookings", "ottoq_variability_cards",
       "ottoq_itinerary_legs", "ottoq_bay_binding_witness"]
ROWS = 7
PURGE = "CALL public.ottoq_retention_purge_runs(60, 3, '7 days', false)"


def _conn_args():
    if os.environ.get("PGHOST"):
        return ["-h", os.environ["PGHOST"], "-p", os.environ.get("PGPORT", "5432"),
                "-U", os.environ.get("PGUSER", "postgres")]
    return ["-h", "/var/tmp", "-p", "55432", "-U", "postgres"]


def _server_up():
    if not shutil.which("psql"):
        return False
    p = subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-Atc", "select 1"], capture_output=True, text=True)
    return p.returncode == 0


pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


class Db:
    def __init__(self, name):
        self.name = name

    def _cmd(self, sql):
        return ["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql]

    def run(self, sql, check=True):
        p = subprocess.run(self._cmd(sql), capture_output=True, text=True)
        out = [l for l in p.stdout.splitlines() if l.strip()]
        if check and p.returncode != 0:
            raise AssertionError(f"SQL failed ({p.returncode}): {p.stderr}\n--- sql ---\n{sql}")
        return p.returncode, (out[-1] if out else ""), p.stderr

    def val(self, sql):
        return self.run(sql)[1]

    def json(self, sql):
        return json.loads(self.val(sql))

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr

    def background(self, sql, appname="scratch"):
        env = {**os.environ, "PGAPPNAME": appname}
        return subprocess.Popen(self._cmd(sql), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)

    def wait_active(self, marker, timeout=10.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            n = self.val(f"SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND query LIKE '%{marker}%' "
                         f"AND pid <> pg_backend_pid() AND wait_event = 'PgSleep'")
            if n == "1":
                return
            time.sleep(0.1)
        raise AssertionError(f"the background session carrying {marker} never reached its sleep")


@pytest.fixture(scope="module")
def db():
    name = f"ottoq_purge_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub engine did not load: {err}"
        yield d
    finally:
        subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def seed_run(db, run_by, status, started_days_ago, ended_days_ago, archived=True, orders=False):
    """One run with ROWS rows in each of the six tables and in ottoq_events."""
    rid = str(uuid.uuid4())
    ended = "NULL" if ended_days_ago is None else f"now() - interval '{ended_days_ago} days'"
    parts = [f"INSERT INTO ottoq_sim_runs (sim_run_id, run_by, status, started_at, ended_at) VALUES "
             f"('{rid}', '{run_by}', '{status}', now() - interval '{started_days_ago} days', {ended})"]
    if archived:
        parts.append(f"INSERT INTO ottoq_run_archives VALUES ('{rid}')")
    if orders:
        parts.append(f"INSERT INTO ottoq_charge_order_snapshots (sim_run_id) VALUES ('{rid}')")
    for t in SIX + ["ottoq_events"]:
        parts.append(f"INSERT INTO {t} (sim_run_id) SELECT '{rid}' FROM generate_series(1, {ROWS})")
    db.run("; ".join(parts))
    return rid


def counts(db, rid):
    cols = ", ".join(f"'{t}', (SELECT count(*) FROM {t} WHERE sim_run_id = '{rid}')" for t in SIX + ["ottoq_events"])
    return db.json(f"SELECT json_build_object({cols})")


def stamped(db, rid):
    return db.val(f"SELECT purged_at IS NOT NULL FROM ottoq_sim_runs WHERE sim_run_id = '{rid}'") == "t"


def intact(db, rid):
    return all(n == ROWS for n in counts(db, rid).values()) and not stamped(db, rid)


def purged(db, rid):
    c = counts(db, rid)
    return all(c[t] == 0 for t in SIX) and c["ottoq_events"] == ROWS and stamped(db, rid)


def test_before_0645_the_recert_runner_latches_the_purge_shut(db):
    # The defect itself: a finished, archived, 10-day-old research arm, and the old purge does nothing, because the
    # always-on recert runner's command names the pair and the 0269 guard reads that as a scheduled round.
    rid = seed_run(db, "ab_harness", "completed", 10, 10)
    db.run("CALL public.ottoq_retention_purge_runs(60, 3, '48 hours', false)")
    assert intact(db, rid), counts(db, rid)


def test_0645_applies(db):
    rc, err = db.file(M0645)
    assert rc == 0, err
    for v in ("V1", "V2", "V3", "V4", "V5"):
        assert f"0645 {v}" in err, f"0645 {v} did not report:\n{err}"


def test_reapplying_0645_refuses(db):
    rc, err = db.file(M0645)
    assert rc != 0 and "0645 P1" in err, err


def test_0645_classifies_itself_false_false(db):
    row = db.json("SELECT row_to_json(l) FROM ottoq_cert_lineage l "
                  "WHERE name = '0645_the_nightly_run_purge_runs_again_and_never_takes_what_the_learning_reads'")
    assert row["forces_recert"] is False and row["forces_dial_restart"] is False


def test_cron_625_runs_hourly_overnight_inside_the_statement_timeout(db):
    job = db.json("SELECT row_to_json(j) FROM cron.job j WHERE jobid = 625")
    assert job["schedule"] == "17 4-11 * * *" and job["active"] is True
    assert job["command"] == "CALL public.ottoq_retention_purge_runs(100, 2000, '7 days', false);"


def test_the_purge_takes_only_doomed_runs_from_the_six_tables(db):
    doomed = {
        "research arm, ended 10 days ago": seed_run(db, "ab_harness", "completed", 10, 10),
        "certification arm, ended 9 days ago": seed_run(db, "cert_harness", "completed", 9, 9),
        "demo, ended 8 days ago": seed_run(db, "operator_demo", "completed", 8, 8),
        "demo with charge orders, ended 30 days ago": seed_run(db, "operator_demo", "completed", 30, 30, orders=True),
    }
    kept = {
        "production, ended 30 days ago": seed_run(db, "production_live", "completed", 30, 30),
        "running, started 10 days ago": seed_run(db, "operator_demo", "running", 10, None),
        "paused, started 10 days ago": seed_run(db, "ab_harness", "paused", 10, None),
        "started 10 days ago but ended 2 days ago": seed_run(db, "operator_demo", "completed", 10, 2),
        "ended 1 day ago": seed_run(db, "ab_harness", "completed", 1, 1),
        "not archived": seed_run(db, "cert_harness", "completed", 10, 10, archived=False),
        "charge orders, ended 10 days ago": seed_run(db, "operator_demo", "completed", 10, 10, orders=True),
    }
    runs_before = db.val("SELECT count(*) FROM ottoq_sim_runs")
    deleted_before = int(db.val("SELECT pass_deleted FROM ottoq_retention_state WHERE table_name = 'engine_rows'"))

    db.run(PURGE)

    for why, rid in doomed.items():
        assert purged(db, rid), f"{why}: {counts(db, rid)}"
    for why, rid in kept.items():
        assert intact(db, rid), f"{why} was touched: {counts(db, rid)}"
    # ottoq_sim_runs is never deleted, and the run the latched purge left behind is taken now too.
    assert db.val("SELECT count(*) FROM ottoq_sim_runs") == runs_before
    deleted = int(db.val("SELECT pass_deleted FROM ottoq_retention_state WHERE table_name = 'engine_rows'"))
    assert deleted - deleted_before == (len(doomed) + 1) * len(SIX) * ROWS


def test_a_certification_in_flight_stops_it_before_it_starts(db):
    rid = seed_run(db, "ab_harness", "completed", 10, 10)
    m = f"bg_{uuid.uuid4().hex[:10]}"
    runner = db.background(
        f"/* {m} */ DO $runner$ BEGIN\n"
        "  IF NOT pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint) THEN RETURN; END IF;\n"
        "  PERFORM pg_sleep(4);\n"
        "END $runner$;", appname="pg_cron")
    db.wait_active(m)
    db.run(PURGE)
    assert intact(db, rid), counts(db, rid)
    runner.communicate(timeout=30)
    db.run(PURGE)
    assert purged(db, rid), counts(db, rid)


def test_a_certification_starting_mid_purge_stops_it_after_the_batch_in_hand(db):
    rid = seed_run(db, "cert_harness", "completed", 10, 10)
    # Make ottoq_rule_evaluations the largest table, so the purge takes it first, and have a certification "start"
    # the moment its first batch is deleted: the next batch's probe must see it and stop.
    db.run("INSERT INTO ottoq_rule_evaluations (sim_run_id) "
           "SELECT p.sim_run_id FROM (SELECT sim_run_id FROM ottoq_sim_runs WHERE run_by = 'production_live' LIMIT 1) p, "
           "generate_series(1, 3000)")
    db.run("CREATE FUNCTION public.t_cert_starts() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN "
           "PERFORM set_config('ottoq.simulate_certification_in_flight', 'on', false); RETURN NULL; END $$; "
           "CREATE TRIGGER t_cert_starts AFTER DELETE ON public.ottoq_rule_evaluations "
           "FOR EACH STATEMENT EXECUTE FUNCTION public.t_cert_starts()")
    try:
        db.run(PURGE)
        c = counts(db, rid)
        assert c["ottoq_rule_evaluations"] == ROWS - 3, c
        assert all(c[t] == ROWS for t in SIX if t != "ottoq_rule_evaluations"), c
        assert stamped(db, rid), "the batch that was deleted must carry its stamp"
    finally:
        db.run("DROP TRIGGER t_cert_starts ON public.ottoq_rule_evaluations; DROP FUNCTION public.t_cert_starts()")
    db.run(PURGE)
    assert purged(db, rid), counts(db, rid)


def _old_evaluations(db, prod, live, done):
    db.run(f"INSERT INTO ottoq_rule_evaluations (sim_run_id, evaluated_at) "
           f"SELECT r, now() - interval '10 days' FROM unnest(ARRAY['{prod}','{live}','{done}']::uuid[]) r, "
           f"generate_series(1, 4); "
           f"INSERT INTO ottoq_rule_evaluations (sim_run_id, evaluated_at) "
           f"SELECT NULL, now() - interval '10 days' FROM generate_series(1, 4)")


def _old_count(db, rid):
    pred = "sim_run_id IS NULL" if rid is None else f"sim_run_id = '{rid}'"
    return int(db.val(f"SELECT count(*) FROM ottoq_rule_evaluations WHERE {pred} AND evaluated_at < now() - interval '9 days'"))


WORKER = "CALL public.ottoq_retention_purge_worker(60, 3, '48 hours', ARRAY['ottoq_rule_evaluations'])"


def test_before_0646_the_wall_clock_walk_takes_production_rule_evaluations(db):
    prod = seed_run(db, "production_live", "completed", 30, 30)
    live = seed_run(db, "operator_demo", "running", 1, None)
    done = seed_run(db, "operator_demo", "completed", 2, 2)
    _old_evaluations(db, prod, live, done)
    db.run(WORKER)
    assert _old_count(db, prod) == 0 and _old_count(db, live) == 0, "the defect 0646 closes did not reproduce"


def test_0646_applies_and_the_walk_spares_production_and_running_runs(db):
    rc, err = db.file(M0646)
    assert rc == 0, err
    assert "0646 V" in err, err
    prod = seed_run(db, "production_live", "completed", 30, 30)
    live = seed_run(db, "operator_demo", "running", 1, None)
    done = seed_run(db, "operator_demo", "completed", 2, 2)
    _old_evaluations(db, prod, live, done)
    db.run(WORKER)
    assert _old_count(db, prod) == 4, "a production run's rule evaluations were taken by age"
    assert _old_count(db, live) == 4, "a running run's rule evaluations were taken by age"
    assert _old_count(db, done) == 0 and _old_count(db, None) == 0, "the walk stopped deleting what it should"


def test_reapplying_0646_refuses(db):
    rc, err = db.file(M0646)
    assert rc != 0 and "0646 P1" in err, err


def test_0646_classifies_itself_false_false(db):
    row = db.json("SELECT row_to_json(l) FROM ottoq_cert_lineage l "
                  "WHERE name = '0646_the_wall_clock_retention_never_takes_a_production_runs_shield_log'")
    assert row["forces_recert"] is False and row["forces_dial_restart"] is False
