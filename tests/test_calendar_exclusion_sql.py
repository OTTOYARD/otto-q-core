"""db/migrations/0602, EXECUTED: the calendar sheds the exclusion constraint its strongest one subsumes.

WHY THIS EXISTS. 0602 drops an EXCLUDE constraint from `ottoq_stall_bookings`, the table CLAUDE.md protects by name
("makes double-booking physically impossible ... never remove either side"). Its whole case is that no_overlap_v2 can
refuse nothing no_overlap_v3 does not. That is argued in the header and executed here, on a calendar carrying the three
constraints exactly as the live one does (definitions as pg_get_constraintdef printed them on 2026-09-30):

  * after 0602, every overlap v2 refused is still refused, by v3, for every state v2 covered;
  * v1 and v3 are unchanged, and the one region v1 covers alone (a back-dated held booking) is still covered by v1;
  * 0602 refuses while anything is in flight, when the constraints are not the three measured, when a row is booked
    before the 2026-08-02 bound, and a second time; its header's rollback puts v2 back to the byte.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_throughput_sweep_sql.py.
"""
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M0602 = os.path.join(ROOT, "db", "migrations",
                     "0602_the_calendar_keeps_the_exclusion_that_binds_and_sheds_the_one_it_subsumes.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "a0000000-0000-0000-0000-000000000001"
STALL = "a0000000-0000-0000-0000-00000000000a"
CAR = "a0000000-0000-0000-0000-0000000000c1"
V2 = ("EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&) WHERE (((state = ANY "
      "(ARRAY['held'::text, 'active'::text, 'done'::text])) AND (booked_at >= '2026-08-02 03:19:00+00'::timestamp with "
      "time zone)))")


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

# The live calendar's columns, checks and exclusion constraints (2026-09-30), on a stub run, stall and car.
STUB = f"""
CREATE EXTENSION IF NOT EXISTS btree_gist;
DO $r$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
END $r$;
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, started_at timestamptz);
CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid NOT NULL);
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, home_depot_id uuid NOT NULL);
INSERT INTO public.ottoq_sim_runs VALUES ('{RUN}', now());
INSERT INTO public.stalls VALUES ('{STALL}', '{DEPOT}');
INSERT INTO public.vehicles VALUES ('{CAR}', '{DEPOT}');
CREATE TABLE public.ottoq_stall_bookings (
  booking_id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  sim_run_id uuid NOT NULL REFERENCES public.ottoq_sim_runs (sim_run_id),
  stall_id uuid NOT NULL REFERENCES public.stalls (id) ON DELETE CASCADE,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles (id) ON DELETE CASCADE,
  purpose text NOT NULL, during tstzrange NOT NULL, state text NOT NULL DEFAULT 'held',
  booked_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_stall_bookings_state_check CHECK (state = ANY (ARRAY['held','active','done','released','superseded','interrupted'])),
  CONSTRAINT ottoq_stall_bookings_window_check CHECK (NOT isempty(during) AND lower(during) IS NOT NULL AND upper(during) IS NOT NULL),
  CONSTRAINT ottoq_stall_bookings_no_overlap EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&)
    WHERE (state = ANY (ARRAY['held'::text, 'active'::text])),
  CONSTRAINT ottoq_stall_bookings_no_overlap_v2 EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&)
    WHERE ((state = ANY (ARRAY['held'::text, 'active'::text, 'done'::text])) AND booked_at >= '2026-08-02 03:19:00+00'::timestamptz),
  CONSTRAINT ottoq_stall_bookings_no_overlap_v3 EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&)
    WHERE ((state = ANY (ARRAY['held'::text, 'active'::text, 'done'::text, 'interrupted'::text]))
           AND booked_at >= '2026-08-02 03:19:00+00'::timestamptz));
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean NOT NULL DEFAULT false, note text, classified_at timestamptz);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigint GENERATED ALWAYS AS IDENTITY, label text, object_kind text,
  schema_name text, object_name text, definition text, def_md5 text);
CREATE TABLE public.stub_in_flight (n int NOT NULL);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false) RETURNS integer
  LANGUAGE sql STABLE AS $$ SELECT n FROM public.stub_in_flight $$;
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
    name = f"ottoq_cal_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        d.val(STUB)
        yield d
    finally:
        subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _refused_by(d, rows):
    """Insert the rows in one statement and name the constraint that refuses them, or None."""
    vals = ", ".join(f"('{RUN}', '{STALL}', '{CAR}', 'staging', tstzrange('{a}', '{b}', '[)'), '{s}'"
                     + (f", '{at}')" if at else ", now())") for a, b, s, at in rows)
    rc, _, err = d.run(f"BEGIN; INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, "
                       f"during, state, booked_at) VALUES {vals}; ROLLBACK;")
    if rc == 0:
        return None
    assert "conflicting key value violates exclusion constraint" in err, err
    return err.split('exclusion constraint "', 1)[1].split('"', 1)[0]


def _exclusions(d):
    return d.val("""SELECT string_agg(conname, ',' ORDER BY conname) FROM pg_constraint
                     WHERE conrelid = 'public.ottoq_stall_bookings'::regclass AND contype = 'x'""")


def test_every_overlap_v2_refused_is_still_refused_after_0602(db):
    pairs = {s: [("2026-09-01 10:00+00", "2026-09-01 11:00+00", s, None),
                 ("2026-09-01 10:30+00", "2026-09-01 11:30+00", s, None)] for s in ("held", "active", "done")}
    before = {s: _refused_by(db, rows) for s, rows in pairs.items()}
    assert all(before.values()), before
    rc, err = db.file(M0602)
    assert rc == 0, err
    assert _exclusions(db) == "ottoq_stall_bookings_no_overlap,ottoq_stall_bookings_no_overlap_v3"
    after = {s: _refused_by(db, rows) for s, rows in pairs.items()}
    assert all(after.values()), after
    assert after["done"] == "ottoq_stall_bookings_no_overlap_v3"
    # interrupted overlaps (v3's own) and back-dated held overlaps (v1's own region) are refused as before
    assert _refused_by(db, [("2026-09-01 10:00+00", "2026-09-01 11:00+00", "interrupted", None),
                            ("2026-09-01 10:30+00", "2026-09-01 11:30+00", "done", None)]) \
        == "ottoq_stall_bookings_no_overlap_v3"
    assert _refused_by(db, [("2026-09-01 10:00+00", "2026-09-01 11:00+00", "held", "2026-07-01 00:00+00"),
                            ("2026-09-01 10:30+00", "2026-09-01 11:30+00", "held", "2026-07-01 00:00+00")]) \
        == "ottoq_stall_bookings_no_overlap"
    # and what never overlapped still books
    assert _refused_by(db, [("2026-09-01 10:00+00", "2026-09-01 11:00+00", "done", None),
                            ("2026-09-01 11:00+00", "2026-09-01 12:00+00", "done", None)]) is None
    assert db.val("SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage") \
        == "false/false"


def test_0602_refuses_in_flight_on_other_constraints_on_old_rows_and_twice(db):
    db.val("UPDATE public.stub_in_flight SET n = 1")
    rc, err = db.file(M0602)
    assert rc != 0 and "0602 P0" in err
    db.val("UPDATE public.stub_in_flight SET n = 0")
    db.val(f"""INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_at)
               VALUES ('{RUN}', '{STALL}', '{CAR}', 'staging', tstzrange('2026-07-01 00:00+00', '2026-07-01 01:00+00'),
                       'released', '2026-07-01 00:00+00')""")
    rc, err = db.file(M0602)
    assert rc != 0 and "0602 P1: rows are booked before the 2026-08-02 bound" in err
    db.val("DELETE FROM public.ottoq_stall_bookings")
    db.val("ALTER TABLE public.ottoq_stall_bookings DROP CONSTRAINT ottoq_stall_bookings_no_overlap")
    rc, err = db.file(M0602)
    assert rc != 0 and "0602 P1: the calendar's exclusion constraints are not the three measured" in err
    db.val("""ALTER TABLE public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_no_overlap
                EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&)
                WHERE (state = ANY (ARRAY['held'::text, 'active'::text]))""")
    rc, err = db.file(M0602)
    assert rc == 0, err
    rc, err = db.file(M0602)
    assert rc != 0 and "0602 P1: already applied" in err


def test_the_headers_rollback_puts_v2_back_to_the_byte(db):
    rc, err = db.file(M0602)
    assert rc == 0, err
    header = open(M0602).read().split("-- ROLLBACK: ", 1)[1].split("\n\nBEGIN;", 1)[0]
    lines = [(l[2:] if l.startswith("--") else l).strip() for l in header.splitlines()]
    alter = " ".join(lines[:3])
    db.val(alter)
    db.val(lines[3].rstrip(".").replace("'.", "'") + ";")
    assert db.val("""SELECT pg_get_constraintdef(oid) FROM pg_constraint
                      WHERE conname = 'ottoq_stall_bookings_no_overlap_v2'""") == V2
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
    rc, err = db.file(M0602)
    assert rc == 0, err
