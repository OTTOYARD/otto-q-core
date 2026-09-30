"""db/migrations/0570, EXECUTED: the batch optimizer can hand chargers out in the order the charge cursor serves cars.

WHY THIS EXISTS. 0570 patches a function on OTTO-Q's decide path, `ottoq_l2_optimize_assignments`, and classifies
itself forces_recert FALSE on one claim: at the dial's default the batch proposes exactly what it proposed before. That
claim is executed here against the live function's own source (tests/fixtures/charge_batch_order_stub.sql carries it
byte for byte), before and after the patch in one database. The rest pins what the dial does at 1 (G297): the cars the
cursor serves first (immediate dispatch, then the least slack) get the fast chargers; slack counts the charge a car
still needs, to rule 9's target; and every candidate gate still applies.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_throughput_sweep_sql.py.
"""
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "charge_batch_order_stub.sql")
M0570 = os.path.join(ROOT, "db", "migrations", "0570_the_batch_optimizer_can_serve_cars_in_the_order_the_cursor_does.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "a0000000-0000-0000-0000-000000000001"
T = "2026-09-01 11:05:00+00"


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

    def run(self, sql):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True)
        return p.returncode, [l for l in p.stdout.splitlines() if l.strip()], p.stderr

    def val(self, sql):
        rc, out, err = self.run(sql)
        if rc != 0:
            raise AssertionError(f"SQL failed: {err}\n--- sql ---\n{sql}")
        return out[-1] if out else ""

    def json(self, sql):
        return json.loads(self.val(sql))

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr


@pytest.fixture()
def db():
    name = f"ottoq_cbo_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        d.val(f"INSERT INTO public.ottoq_sim_runs VALUES ('{RUN}', '{DEPOT}')")
        yield d
    finally:
        subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"],
                       capture_output=True)


def _apply(d):
    rc, err = d.file(M0570)
    assert rc == 0, f"0570 did not apply: {err}"


def _stall(d, code, kind, dist):
    sid = str(uuid.uuid5(uuid.NAMESPACE_DNS, code))
    d.val(f"INSERT INTO public.ottoq_ocpp_chargers VALUES ('{sid}', 'Available', '{T}')")
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, ocpp_charger_id, connector_type,
                                         connector_max_kw, distance_from_entrance)
              VALUES ('{sid}', '{DEPOT}', '{kind}', '{code}', '{sid}', 'CCS1', {350 if kind == 'dcfc' else 11}, {dist})""")
    return sid


def _car(d, name, soc, urgency="standard", due_min=None, battery=75, inlet=150):
    vid = str(uuid.uuid5(uuid.NAMESPACE_DNS, name))
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, current_soc, battery_capacity_kwh, inlet_max_kw)
              VALUES ('{vid}', '{DEPOT}', {soc}, {battery}, {inlet})""")
    due = "NULL" if due_min is None else f"'{T}'::timestamptz + interval '{due_min} minutes'"
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, status, urgency, dispatch_due_at)
              VALUES ('{vid}', '{RUN}', 'open', '{urgency}', {due})""")
    return vid


def _dial(d, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params VALUES ('run', '{RUN}', 'charge_batch_order', {value}, 'test')
              ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value""")


def _propose(d):
    """Run the batch once and return who got what, in the order the batch handed it out."""
    d.val(f"SELECT public.ottoq_l2_optimize_assignments('{RUN}', '{DEPOT}', '{T}')")
    return d.json("""SELECT COALESCE(jsonb_agg(jsonb_build_array(s.stall_code, p.proposal) ORDER BY p.proposal_id), '[]')
                       FROM public.ottoq_external_proposals p JOIN public.stalls s ON s.id = (p.proposal->>'stall_id')::uuid""")


NAMES = {str(uuid.uuid5(uuid.NAMESPACE_DNS, n)): n for n in ("U1", "U2", "U3", "S1", "S2", "S3", "A", "B", "C", "D")}


def _names(d, got):
    return [(NAMES[p["vehicle_id"]], stall) for stall, p in got]


def _morning(d):
    """G297's morning in miniature: two fast chargers, three L2, two urgent cars due in 40 minutes, two standard cars
    lower on battery than both."""
    _stall(d, "F1", "dcfc", 10)
    _stall(d, "F2", "dcfc", 20)
    for i, code in enumerate(("L1", "L2", "L3")):
        _stall(d, code, "l2", 30 + i)
    _car(d, "U1", 35, "immediate_dispatch", 40)
    _car(d, "U2", 60, "immediate_dispatch", 40)
    _car(d, "S1", 20)
    _car(d, "S2", 30)


def test_the_dial_is_catalogued_off_and_the_file_refuses_a_second_apply(db):
    _apply(db)
    row = db.json("""SELECT to_jsonb(c) - 'description' FROM public.ottoq_policy_param_catalog c
                      WHERE param_key = 'charge_batch_order'""")
    assert (row["min_value"], row["max_value"], row["default_value"], row["agent_writable"]) == (0, 1, 0, False)
    assert row["affects"] == "ottoq_l2_optimize_assignments"
    assert db.val("""SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage
                     WHERE name = '0570_the_batch_optimizer_can_serve_cars_in_the_order_the_cursor_does'""") == "false/false"
    # the pre-image is kept for the rollback, and it is the function measured
    assert db.val("""SELECT count(*) FROM public.ottoq_schema_snapshots
                     WHERE label = '0570_pre' AND position('ORDER BY v.current_soc ASC, v.id' IN definition) > 0""") == "1"
    # a second apply is refused: by P1 (the optimizer is no longer the one measured) before P2 can say so itself
    rc, err = db.file(M0570)
    assert rc != 0 and ("0570 P2" in err or "0570 P1" in err)
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0570_pre'") == "1"


def test_at_the_default_the_batch_proposes_exactly_what_it_did_before(db):
    _morning(db)
    before = _propose(db)
    assert _names(db, before) == [("S1", "F1"), ("S2", "F2"), ("U1", "L1"), ("U2", "L2")]   # G297, as measured
    _apply(db)
    assert _propose(db) == before            # every field of every proposal, in the same order
    _dial(db, 0)                             # and a run-scoped 0 is the default too
    assert _propose(db) == before


def test_at_one_the_cars_the_cursor_serves_first_get_the_fast_chargers(db):
    _morning(db)
    _apply(db)
    _dial(db, 1)
    got = _names(db, _propose(db))
    # urgent first, the least slack first among them (U1 needs 48.8 kWh: 15.6 min of slack; U2 needs 30: 25.0), then
    # battery for the rest, who take the L2 overflow
    assert got == [("U1", "F1"), ("U2", "F2"), ("S1", "L1"), ("S2", "L2")]


def test_the_least_slack_goes_first_and_it_counts_the_charge_still_needed(db):
    _stall(db, "F1", "dcfc", 10)
    _stall(db, "L1", "l2", 30)
    _stall(db, "L2", "l2", 31)
    _car(db, "C", 20, "immediate_dispatch", 50)    # 50 min to due, 30 min of fast charge: 20.0 of slack
    _car(db, "D", 90, "immediate_dispatch", 40)    # 40 min to due, 3.75 min of fast charge: 36.3 of slack
    _apply(db)
    _dial(db, 1)
    # D is due sooner, but C needs far more of the charger: least slack, not earliest due, gets the fast charger
    assert _names(db, _propose(db)) == [("C", "F1"), ("D", "L1")]


def test_urgency_outranks_slack_as_it_does_in_the_cursor(db):
    _stall(db, "F1", "dcfc", 10)
    _stall(db, "L1", "l2", 30)
    _stall(db, "L2", "l2", 31)
    _car(db, "U3", 50, "immediate_dispatch", 120)  # plenty of slack, but the cursor serves it first
    _car(db, "S3", 50, "standard", 30)             # a standard visit with a tight due time
    _apply(db)
    _dial(db, 1)
    assert _names(db, _propose(db)) == [("U3", "F1"), ("S3", "L1")]


def test_the_slack_reads_the_owners_target_and_is_null_without_a_due_time(db):
    _apply(db)
    a = _car(db, "A", 50, "immediate_dispatch", 60)
    b = _car(db, "B", 50)
    slack = lambda v: db.val(f"SELECT public.ottoq_charge_slack_min('{v}', '{RUN}', '{T}')")
    assert float(slack(a)) == 41.3             # 60 - 37.5 kWh / 120 kW
    assert slack(b) == ""                      # no due time: NULL, sorted after every car with one
    # an owner who caps the car at 80% (rule 9: the owner's answer, read at ottoq_effective_target_soc_at) needs less
    db.val(f"INSERT INTO public.stub_owner_target VALUES ('{a}', 80)")
    assert float(slack(a)) == 48.8             # 60 - 22.5 kWh / 120 kW
    # another run's visit is not this car's visit
    assert db.val(f"SELECT public.ottoq_charge_slack_min('{a}', gen_random_uuid(), '{T}') IS NULL") == "t"


def test_at_one_every_candidate_gate_still_applies(db):
    _morning(db)
    _apply(db)
    _dial(db, 1)
    u1 = str(uuid.uuid5(uuid.NAMESPACE_DNS, "U1"))
    f1 = str(uuid.uuid5(uuid.NAMESPACE_DNS, "F1"))
    f2 = str(uuid.uuid5(uuid.NAMESPACE_DNS, "F2"))
    db.val(f"INSERT INTO public.stub_refused VALUES ('{u1}', '{f1}')")                      # the calendar says no
    db.val(f"UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted' WHERE charger_id = '{f2}'")   # a fault
    assert _names(db, _propose(db)) == [("U1", "L1"), ("U2", "F1"), ("S1", "L2"), ("S2", "L3")]


def test_the_file_refuses_while_a_pair_is_in_flight_or_the_optimizer_has_moved(db):
    db.val("UPDATE public.stub_in_flight SET n = 1")
    rc, err = db.file(M0570)
    assert rc != 0 and "0570 P0" in err
    db.val("UPDATE public.stub_in_flight SET n = 0")
    assert db.val("""SELECT position('ORDER BY v.current_soc ASC' IN pg_get_functiondef(
                       'public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure)) > 0""") == "t"
    db.val("""DO $x$ BEGIN EXECUTE replace(pg_get_functiondef('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure),
                                          'RETURN v_n;', 'RETURN v_n;   -- moved'); END $x$""")
    rc, err = db.file(M0570)
    assert rc != 0 and "0570 P1" in err and "not the function measured" in err
    assert db.val("SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_batch_order'") == "0"
