"""db/migrations/0768, EXECUTED: the demo metronome's pg_cron job gets a 57-second budget, so a live twin run rests about 3
seconds a minute instead of 10-12.

WHY THIS EXISTS. On run 78c0624c (2026-10-24) the metronome ticked for its 50-second budget and returned each minute, so
564 of the run's 3,432 s (16.4%) had no tick and the tick after each rest moved the world 35-54 sim-seconds at once.
Executed here against a stand-in for pg_cron's job table and cron.alter_job (live's signature, read 2026-10-24):
  - the job's command becomes CALL public.ottoq_demo_metronome(57); its schedule, name and state do not move;
  - 0768 refuses a job that is not the one it read (another budget, another schedule, two jobs of the name), a second
    apply, and nothing changes when it refuses;
  - a Windows paste applies the same, and the header's ROLLBACK puts 50 back.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import re
import subprocess
import tempfile
import uuid

import pytest

import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
M0768 = os.path.join(ROOT, "db", "migrations", "0768_the_demo_metronome_ticks_through_the_whole_minute.sql")
L0768 = "0768_the_demo_metronome_ticks_through_the_whole_minute"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

WORLD = """
CREATE SCHEMA cron;
CREATE TABLE cron.job (jobid bigserial PRIMARY KEY, schedule text NOT NULL, command text NOT NULL,
  nodename text DEFAULT 'localhost', nodeport int DEFAULT 5432, database text DEFAULT 'postgres',
  username text DEFAULT 'postgres', active boolean DEFAULT true, jobname text);
-- live's signature: cron.alter_job(job_id, schedule, command, database, username, active)
CREATE FUNCTION cron.alter_job(job_id bigint, schedule text DEFAULT NULL, command text DEFAULT NULL,
                               database text DEFAULT NULL, username text DEFAULT NULL, active boolean DEFAULT NULL)
RETURNS void LANGUAGE sql AS $f$
  UPDATE cron.job j SET schedule = COALESCE(alter_job.schedule, j.schedule), command = COALESCE(alter_job.command, j.command),
                        database = COALESCE(alter_job.database, j.database), username = COALESCE(alter_job.username, j.username),
                        active = COALESCE(alter_job.active, j.active)
   WHERE j.jobid = alter_job.job_id $f$;
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql AS 'SELECT 0';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean NOT NULL DEFAULT false, note text NOT NULL, classified_at timestamptz NOT NULL);
INSERT INTO cron.job (schedule, command, jobname) VALUES
  ('* * * * *', 'CALL public.ottoq_demo_metronome(50)', 'ottoq-demo-metronome'),
  ('*/5 * * * *', 'SELECT 1', 'ottoq-something-else');
"""


@pytest.fixture()
def db():
    name = f"ottoq_metronome_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        fd, path = tempfile.mkstemp(suffix="_0768_world.sql")
        with os.fdopen(fd, "w") as f:
            f.write(WORLD)
        try:
            rc, err = d.file(path)
        finally:
            os.remove(path)
        assert rc == 0, err
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _job(d):
    return d.val("""SELECT schedule || ' | ' || command || ' | ' || active::text FROM cron.job
                     WHERE jobname = 'ottoq-demo-metronome'""")


def _other(d):
    return d.val("SELECT schedule || ' | ' || command FROM cron.job WHERE jobname = 'ottoq-something-else'")


def test_0768_applies_and_its_assertions_pass(db):
    rc, err = db.file(M0768)
    assert rc == 0, err
    assert _job(db) == "* * * * * | CALL public.ottoq_demo_metronome(57) | true"
    assert _other(db) == "*/5 * * * * | SELECT 1"
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM ottoq_cert_lineage WHERE name = '{L0768}'") \
        == "falsefalse"


def test_0768_applies_from_a_windows_paste(db):
    with open(M0768, encoding="utf-8") as f:
        text = f.read().replace("\n", "\r\n")
    fd, path = tempfile.mkstemp(suffix="_0768_crlf.sql")
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    try:
        rc, err = db.file(path)
    finally:
        os.remove(path)
    assert rc == 0, err
    assert _job(db) == "* * * * * | CALL public.ottoq_demo_metronome(57) | true"


@pytest.mark.parametrize("change", [
    "UPDATE cron.job SET command = 'CALL public.ottoq_demo_metronome(45)' WHERE jobname = 'ottoq-demo-metronome'",
    "UPDATE cron.job SET schedule = '*/2 * * * *' WHERE jobname = 'ottoq-demo-metronome'",
    "INSERT INTO cron.job (schedule, command, jobname) VALUES ('* * * * *', 'CALL public.ottoq_demo_metronome(50)', "
    "'ottoq-demo-metronome')",
    "DELETE FROM cron.job WHERE jobname = 'ottoq-demo-metronome'",
])
def test_0768_refuses_a_job_that_is_not_the_one_it_read_and_changes_nothing(db, change):
    db.val(change)
    before = db.val("SELECT string_agg(jobid || ':' || schedule || ':' || command, ';' ORDER BY jobid) FROM cron.job")
    rc, err = db.file(M0768)
    assert rc != 0 and "0768 P1" in err, err
    assert db.val("SELECT string_agg(jobid || ':' || schedule || ':' || command, ';' ORDER BY jobid) FROM cron.job") == before
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage") == "0"


def test_0768_refuses_a_second_apply_and_its_rollback_puts_fifty_back(db):
    rc, err = db.file(M0768)
    assert rc == 0, err
    rc, err = db.file(M0768)
    assert rc != 0 and "0768 P1" in err              # the job no longer reads 50
    with open(M0768, encoding="utf-8") as f:
        header = f.read()
    rollback = re.search(r"-- ROLLBACK: (SELECT cron\.alter_job\(.*?\);)", header, re.S).group(1)
    db.val(re.sub(r"\n--\s*", " ", rollback))
    assert _job(db) == "* * * * * | CALL public.ottoq_demo_metronome(50) | true"
    rc, err = db.file(M0768)
    assert rc != 0 and "0768 P2" in err              # the job reads 50 again, but the lineage says it was applied
