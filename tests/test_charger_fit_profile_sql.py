"""db/migrations/0604, EXECUTED: a read-only measure of whether a run's fast chargers went to the cars that needed them.

WHY THIS EXISTS. Night 1 showed OTTO-Q's seat spending 52% of its fast-charger hours on cars that started at 80% or more,
against fifo's 41% and greedy's 28% on the same seed, and nothing in the scorecard said so (G315). 0604 adds
`ottoq_charger_fit_profile`. Its arithmetic is pinned here on sessions whose answers are worked by hand: hours to the
run's horizon for an open session, the nearly-full and arrived-low splits, the picks of the other kind of charger, and
rule 8's depot predicate (another depot's and another run's sessions never count). Then the refusals and the rollback.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_throughput_sweep_sql.py.
"""
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M0604 = os.path.join(ROOT, "db", "migrations",
                     "0604_every_test_day_can_say_whether_its_fast_chargers_went_to_the_cars_that_needed_them.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
OTHER = "22222222-2222-2222-2222-222222222222"
RUN = "a0000000-0000-0000-0000-000000000001"
RUN2 = "a0000000-0000-0000-0000-000000000002"


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

# Two fast chargers and two L2 at the twin depot, one fast charger at another depot. Horizon: the run's last energy
# sample, 13:00.  Fast: a car at 90% for 30 min (7.5 kWh) and one at 30% for 60 min (60 kWh).  L2: a car at 25% still
# plugged in at the horizon (2 h, 20 kWh) and one at 85% for 30 min (4 kWh).  Noise that must not count: a session at
# the other depot, and one in another run.
STUB = f"""
DO $r$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $r$;
CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid NOT NULL, stall_type text NOT NULL);
CREATE TABLE public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stall_id uuid, depot_id uuid,
  sim_run_id uuid, started_at timestamptz, ended_at timestamptz, soc_start numeric, energy_delivered_kwh numeric);
CREATE TABLE public.site_energy_snapshots (depot_id uuid, sim_run_id uuid, "timestamp" timestamptz);
CREATE TABLE public.ottoq_decisions (sim_run_id uuid, depot_id uuid, action_context text, outcome_status text,
  proposed_action jsonb);
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean NOT NULL DEFAULT false, note text, classified_at timestamptz);
CREATE TABLE public.stub_in_flight (n int NOT NULL);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false) RETURNS integer
  LANGUAGE sql STABLE AS $$ SELECT n FROM public.stub_in_flight $$;

INSERT INTO public.stalls VALUES
  ('f0000000-0000-0000-0000-000000000001', '{DEPOT}', 'dcfc'), ('f0000000-0000-0000-0000-000000000002', '{DEPOT}', 'dcfc'),
  ('f0000000-0000-0000-0000-000000000003', '{DEPOT}', 'l2'),   ('f0000000-0000-0000-0000-000000000004', '{DEPOT}', 'l2'),
  ('f0000000-0000-0000-0000-000000000005', '{OTHER}', 'dcfc'), ('f0000000-0000-0000-0000-000000000006', '{DEPOT}', 'staging');
INSERT INTO public.site_energy_snapshots VALUES ('{DEPOT}', '{RUN}', '2026-09-01 11:00+00'), ('{DEPOT}', '{RUN}', '2026-09-01 13:00+00');
INSERT INTO public.ocpp_sessions (stall_id, depot_id, sim_run_id, started_at, ended_at, soc_start, energy_delivered_kwh) VALUES
  ('f0000000-0000-0000-0000-000000000001', '{DEPOT}', '{RUN}', '2026-09-01 11:00+00', '2026-09-01 11:30+00', 90, 7.5),
  ('f0000000-0000-0000-0000-000000000002', '{DEPOT}', '{RUN}', '2026-09-01 11:00+00', '2026-09-01 12:00+00', 30, 60),
  ('f0000000-0000-0000-0000-000000000003', '{DEPOT}', '{RUN}', '2026-09-01 11:00+00', NULL, 25, 20),
  ('f0000000-0000-0000-0000-000000000004', '{DEPOT}', '{RUN}', '2026-09-01 12:00+00', '2026-09-01 12:30+00', 85, 4),
  ('f0000000-0000-0000-0000-000000000005', '{OTHER}', '{RUN}', '2026-09-01 11:00+00', '2026-09-01 12:00+00', 95, 9),
  ('f0000000-0000-0000-0000-000000000001', '{DEPOT}', '{RUN2}', '2026-09-01 11:00+00', '2026-09-01 12:00+00', 99, 1);
INSERT INTO public.ottoq_decisions VALUES
  ('{RUN}', '{DEPOT}', 'stall_assignment', 'enacted', '{{"stall_type": "dcfc", "rationale": {{"wanted_type": "l2"}}}}'),
  ('{RUN}', '{DEPOT}', 'stall_assignment', 'enacted', '{{"stall_type": "dcfc", "rationale": {{"wanted_type": "l2"}}}}'),
  ('{RUN}', '{DEPOT}', 'stall_assignment', 'noop_no_candidate', '{{"stall_type": "dcfc", "rationale": {{"wanted_type": "l2"}}}}'),
  ('{RUN}', '{DEPOT}', 'stall_assignment', 'enacted', '{{"stall_type": "l2", "rationale": {{"wanted_type": "dcfc"}}}}'),
  ('{RUN}', '{DEPOT}', 'stall_assignment', 'enacted', '{{"stall_type": "dcfc", "rationale": {{"wanted_type": "dcfc"}}}}'),
  ('{RUN}', '{OTHER}', 'stall_assignment', 'enacted', '{{"stall_type": "dcfc", "rationale": {{"wanted_type": "l2"}}}}');
"""


class Db:
    def __init__(self, name):
        self.name = name

    def run(self, sql):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True)
        return p.returncode, [l for l in p.stdout.splitlines() if l.strip()], p.stderr

    def val(self, sql):
        rc, out, err = self.run(sql)
        if rc != 0:
            raise AssertionError(f"SQL failed: {err}\n--- sql ---\n{sql}")
        return out[-1] if out else ""

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr


@pytest.fixture()
def db():
    name = f"ottoq_cfp_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        d.val(STUB)
        yield d
    finally:
        subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def test_the_profile_is_the_arithmetic_worked_by_hand(db):
    rc, err = db.file(M0604)
    assert rc == 0, err
    p = json.loads(db.val(f"SELECT public.ottoq_charger_fit_profile('{RUN}', '{DEPOT}')"))
    assert p["horizon"].startswith("2026-09-01T13:00:00")
    assert p["by_type"]["dcfc"] == {
        "sessions": 2, "session_hours": 1.5, "kwh": 68, "kw_per_session_hour": 45.0,
        "sessions_from_hi_soc": 1, "hours_from_hi_soc": 0.5, "pct_hours_from_hi_soc": 33.3,
        "sessions_from_lo_soc": 1, "avg_min_from_lo_soc": 60}
    # the L2 car at 25% is still plugged in at the horizon: two hours
    assert p["by_type"]["l2"] == {
        "sessions": 2, "session_hours": 2.5, "kwh": 24, "kw_per_session_hour": 9.6,
        "sessions_from_hi_soc": 1, "hours_from_hi_soc": 0.5, "pct_hours_from_hi_soc": 20.0,
        "sessions_from_lo_soc": 1, "avg_min_from_lo_soc": 120}
    assert p["sessions"] == 4 and p["kwh_delivered"] == 92      # the other depot and the other run never count
    assert p["fast_picks_by_cars_wanting_l2"] == 2 and p["l2_picks_by_cars_wanting_fast"] == 1
    # the thresholds are arguments
    q = json.loads(db.val(f"SELECT public.ottoq_charger_fit_profile('{RUN}', '{DEPOT}', 95, 20)"))
    assert q["by_type"]["dcfc"]["sessions_from_hi_soc"] == 0 and q["by_type"]["l2"]["sessions_from_lo_soc"] == 0
    assert db.val("SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage") \
        == "false/false"


def test_0604_refuses_in_flight_and_twice_and_rolls_back(db):
    db.val("UPDATE public.stub_in_flight SET n = 1")
    rc, err = db.file(M0604)
    assert rc != 0 and "0604 P0" in err
    db.val("UPDATE public.stub_in_flight SET n = 0")
    rc, err = db.file(M0604)
    assert rc == 0, err
    rc, err = db.file(M0604)
    assert rc != 0 and "0604 P1: already applied" in err
    db.val("DROP FUNCTION public.ottoq_charger_fit_profile(uuid, uuid, numeric, numeric)")
    db.val("DELETE FROM public.ottoq_cert_lineage")
    rc, err = db.file(M0604)
    assert rc == 0, err


def test_0604_refuses_a_database_with_no_charging_session_to_prove_on(db):
    db.val("DELETE FROM public.ocpp_sessions")
    rc, err = db.file(M0604)
    assert rc != 0 and "0604 V1: no twin run with a charging session" in err
