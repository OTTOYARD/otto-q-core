"""db/migrations/0703, 0704 and 0705, EXECUTED against a stub engine.

WHY THIS EXISTS. The three files are the study of 2026-10-13's answer to "one agent or a swarm": one coordinator,
consulted when something changes (0705), deterministic per-vehicle scouts instead of per-vehicle model calls (0704), and
an evidence record per agent pass so any later topology can be graded on the same inputs (0703). Each is classified
forces_recert FALSE on claims that are executed here rather than trusted:

  - 0703: the database hashes the board itself, a wrong client hash or an unknown outcome class is refused, the rows are
    append-only, and neither the public key nor a signed-in caller can read them;
  - 0704: the live ottoq_agent_board (byte for byte, tests/fixtures/agent_scouts_wake_stub.sql) is changed by exactly
    the gated block, so an UNARMED board is byte-identical before and after; each of the six scouts fires on the case it
    names and stays silent on its near miss; a second scan records nothing new;
  - 0705: shadow mode wakes on every pass and records what the gate would have done; with the gate on, nothing changed
    means no wake, and a charger fault, contention onset, a car past its contract wait or the heartbeat each wake it.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_agent_charge_order_sql.py.
"""
import json
import os
import subprocess
import uuid

import pytest

import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "agent_scouts_wake_stub.sql")
M = {n: os.path.join(ROOT, "db", "migrations", f) for n, f in (
    ("0703", "0703_every_agent_pass_keeps_what_it_saw_and_what_it_changed.sql"),
    ("0704", "0704_every_car_has_a_deterministic_scout_and_the_agent_reads_what_they_find.sql"),
    ("0705", "0705_the_agent_is_consulted_when_something_changes_not_on_every_beat.sql"),
)}
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "a0000000-0000-0000-0000-000000000704"
OP = "33333333-3333-3333-3333-333333333704"
T = "2026-10-13 15:00:00+00"
START = "2026-10-13 08:00:00+00"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0704-{name}"))


@pytest.fixture()
def db():
    name = f"ottoq_scouts_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _apply(d, *names):
    for n in names:
        rc, err = d.file(M[n])
        assert rc == 0, f"{n} did not apply: {err}"


def _world(d, armed=True):
    d.val(f"INSERT INTO fleet_operators VALUES ('{OP}', 'Op')")
    d.val(f"""INSERT INTO ottoq_fleet_operator_slas (fleet_operator_id, status, version, effective_from, max_queue_wait_minutes)
              VALUES ('{OP}', 'active', 1, '2026-01-01', 30)""")
    d.val(f"""INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_current, sim_clock_start,
                                          started_at, last_tick_at, run_by, scenario_code, random_seed, policy)
              VALUES ('{RUN}', '{DEPOT}', 'running', 80, '{T}', '{START}', '2026-10-13 12:00:00+00', now(),
                      'operator_demo', 'busy_day', 42, 'otto_q')""")
    if armed:
        d.val(f"""INSERT INTO ottoq_policy_params (scope_type, scope_id, param_key, param_value)
                  VALUES ('run', '{RUN}', 'agent_board_grounding_enabled', 1)""")
    for n in ("A", "B", "C", "D", "E", "F", "G", "H"):
        d.val(f"""INSERT INTO vehicles (id, fleet_operator_id, home_depot_id, display_name, current_soc, current_state)
                  VALUES ('{_id(n)}', '{OP}', '{DEPOT}', 'Car-{n}', 60, 'arrived_at_gate')""")
    # two chargers, both open
    for s in ("F1", "L1"):
        d.val(f"INSERT INTO ottoq_ocpp_chargers VALUES ('{_id(s)}', '{DEPOT}', 'Available', NULL)")
        d.val(f"""INSERT INTO stalls VALUES ('{_id(s)}', '{DEPOT}', '{'dcfc' if s == 'F1' else 'l2'}', '{s}', 'available',
                                             NULL, NULL, '{_id(s)}')""")


def _dispatch(d, car, at, back_at=None, recalled_at=None, trigger=None, soc=100):
    back = f"'{back_at}'" if back_at else "NULL"
    rec = f"'{recalled_at}'" if recalled_at else "NULL"
    trig = f"'{trigger}'" if trigger else "NULL"
    d.val(f"""INSERT INTO ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, returning_started_at,
                                                    actual_return_at, soc_at_dispatch_pct, return_trigger)
              VALUES ('{_id(car)}', '{RUN}', '{at}', {rec}, {back}, {soc}, {trig})""")


def _scan(d):
    return d.json(f"SELECT public.ottoq_vehicle_scouts_scan('{RUN}')")


def _findings(d):
    rows = d.json(f"""SELECT COALESCE(jsonb_agg(jsonb_build_object('car', v.display_name, 'scout', f.scout)
                                                ORDER BY v.display_name, f.scout), '[]')
                        FROM ottoq_vehicle_scout_findings f JOIN vehicles v ON v.id = f.vehicle_id""")
    return {(r["car"], r["scout"]) for r in rows}


# ── 0703 ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0703_applies_and_its_assertions_pass(db):
    _apply(db, "0703")
    assert db.val("SELECT count(*) FROM ottoq_run_scope_registry WHERE table_name='ottoq_agent_pass_evidence' "
                  "AND class='evidence'") == "1"


def test_0703_the_database_hashes_the_board_and_refuses_a_wrong_client_hash(db):
    _apply(db, "0703")
    board = '{"tick": 7,\n "x": "é"}'
    sha = db.val(f"SELECT public.ottoq_sha256_utf8($b${board}$b$)")
    db.val(f"""INSERT INTO ottoq_agent_pass_evidence (chain_id, agent_version, consulted, board_text,
                                                      board_sha256_client, outcome_class)
               VALUES ('c1', 'v29', true, $b${board}$b$, '{sha}', 'echo')""")
    assert db.val("SELECT board_sha256 FROM ottoq_agent_pass_evidence WHERE chain_id='c1'") == sha
    rc, _, err = db.run("""INSERT INTO ottoq_agent_pass_evidence (chain_id, agent_version, consulted, board_text,
                                                                  board_sha256_client, outcome_class)
                           VALUES ('c2', 'v29', true, 'x', repeat('a', 64), 'echo')""")
    assert rc != 0 and "ottoq_agent_pass_board_hash_matches" in err
    rc, _, err = db.run("UPDATE ottoq_agent_pass_evidence SET outcome_class='changed_state' WHERE chain_id='c1'")
    assert rc != 0 and "append-only" in err


# ── 0704 ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0704_the_live_board_premise_holds_in_the_stub(db):
    assert db.val("SELECT md5(pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure))") == \
        "8613653559d1cb10eacacbe3c73293fc"


def test_0704_an_unarmed_board_is_byte_identical_and_an_armed_one_carries_the_scouts(db):
    _world(db, armed=False)
    other = "a0000000-0000-0000-0000-0000000007aa"
    db.val(f"""INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_current, sim_clock_start,
                                           started_at, run_by, scenario_code, policy)
               VALUES ('{other}', '{DEPOT}', 'running', 5, '{T}', '{START}', now(), 'operator_demo', 'busy_day', 'otto_q')""")
    db.val(f"""INSERT INTO ottoq_policy_params VALUES ('run', '{other}', 'agent_board_grounding_enabled', 1, 'test', now())""")
    before = db.val(f"SELECT public.ottoq_agent_board('{RUN}')::text")
    _apply(db, "0703", "0704")
    after = db.val(f"SELECT public.ottoq_agent_board('{RUN}')::text")
    assert before == after, "an unarmed board changed"
    armed = db.json(f"SELECT public.ottoq_agent_board('{other}')")
    assert "scouts" in armed and armed["scouts"]["total"] == 0
    db.val(f"INSERT INTO ottoq_policy_params VALUES ('run', '{other}', 'agent_scouts_enabled', 0, 'test', now())")
    assert "scouts" not in db.json(f"SELECT public.ottoq_agent_board('{other}')")


def test_0704_each_scout_fires_on_its_case_and_not_on_its_near_miss(db):
    _world(db)
    _apply(db, "0703", "0704")
    # A: B came home for an interval and left with nothing done -> finding; C had its PM done in between -> none
    for car in ("B", "C"):
        _dispatch(db, car, "2026-10-13 09:00:00+00", back_at="2026-10-13 10:00:00+00",
                  recalled_at="2026-10-13 09:40:00+00", trigger="service_interval_due")
        _dispatch(db, car, "2026-10-13 11:00:00+00", back_at="2026-10-13 12:30:00+00",
                  recalled_at="2026-10-13 12:00:00+00", trigger="sensor_soil")
    db.val(f"""INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, status, atoms)
               VALUES ('{_id('C')}', '{RUN}', '{DEPOT}', '2026-10-13 10:00:00+00', 'completed',
                       '[{{"svc":"mechanical_pm","status":"done","done_at":"2026-10-13 10:30:00+00"}}]')""")
    # B (rebound): D recalled for sensor_soil, then out and back for sensor_soil within 20 minutes -> finding;
    # E's second recall took 50 minutes -> none
    _dispatch(db, "D", "2026-10-13 09:00:00+00", back_at="2026-10-13 09:50:00+00",
              recalled_at="2026-10-13 09:30:00+00", trigger="sensor_soil")
    _dispatch(db, "D", "2026-10-13 10:00:00+00", back_at="2026-10-13 10:40:00+00",
              recalled_at="2026-10-13 10:20:00+00", trigger="sensor_soil")
    _dispatch(db, "E", "2026-10-13 09:00:00+00", back_at="2026-10-13 09:50:00+00",
              recalled_at="2026-10-13 09:30:00+00", trigger="sensor_soil")
    _dispatch(db, "E", "2026-10-13 10:00:00+00", back_at="2026-10-13 11:10:00+00",
              recalled_at="2026-10-13 10:50:00+00", trigger="sensor_soil")
    # C (below target): F left at 90% after the run started -> finding; G left at 80% AT the run's start -> none
    _dispatch(db, "F", "2026-10-13 13:00:00+00", soc=90)
    _dispatch(db, "G", START, soc=80)
    # D (contract wait): H waited 45 min against a 30-minute contract -> finding; A waited 20 -> none
    db.val(f"INSERT INTO stub_kernel_line VALUES ('{RUN}', '{_id('H')}', 1, 45, 30), ('{RUN}', '{_id('A')}', 2, 20, 50)")
    # E (stranded): A's visit is 5 h old with a must_do wash open and nothing done in 2 h -> finding;
    #   F's visit is 5 h old but its readiness check finished 30 minutes ago -> none
    db.val(f"""INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, status, atoms)
               VALUES ('{_id('A')}', '{RUN}', '{DEPOT}', '2026-10-13 10:00:00+00', 'open',
                       '[{{"svc":"exterior_wash","status":"pending","must_do":true}}]'),
                      ('{_id('F')}', '{RUN}', '{DEPOT}', '2026-10-13 10:00:00+00', 'open',
                       '[{{"svc":"exterior_wash","status":"pending","must_do":true}},
                         {{"svc":"interior_reset","status":"done","must_do":true,"done_at":"2026-10-13 14:30:00+00"}}]')""")
    # F (legacy task): a June in_progress task for E -> finding; a fresh one for D -> none
    db.val(f"""INSERT INTO schedule_tasks (vehicle_id, depot_id, status, service_code, created_at)
               VALUES ('{_id('E')}', '{DEPOT}', 'in_progress', 'detail', '2026-06-04 12:00:00+00'),
                      ('{_id('D')}', '{DEPOT}', 'in_progress', 'detail', now())""")

    r = _scan(db)
    assert r["ok"] is True, r
    got = _findings(db)
    want = {("Car-B", "interval_due_departure"), ("Car-D", "same_trigger_rebound"),
            ("Car-F", "departed_below_target"), ("Car-H", "contract_wait_breach"),
            ("Car-A", "stranded_open_must_do"), ("Car-E", "legacy_task_residue")}
    assert got == want, f"unexpected findings: {sorted(got ^ want)}"

    # idempotent: a second scan records nothing new
    r2 = _scan(db)
    assert all(v == 0 for v in r2["new"].values()), r2
    assert int(db.val("SELECT count(*) FROM ottoq_vehicle_scout_findings")) == len(want)

    # the digest the agent reads names the cars
    dig = db.json(f"SELECT public.ottoq_vehicle_scouts_digest('{RUN}', 10)")
    assert dig["total"] == len(want) and {x["car"] for x in dig["newest"]} == {c for c, _ in want}


def test_0704_findings_are_append_only_and_private(db):
    _world(db)
    _apply(db, "0703", "0704")
    db.val(f"INSERT INTO stub_kernel_line VALUES ('{RUN}', '{_id('H')}', 1, 45, 30)")
    _scan(db)
    rc, _, err = db.run("DELETE FROM ottoq_vehicle_scout_findings")
    assert rc != 0 and "append-only" in err
    assert db.val("SELECT has_table_privilege('anon','public.ottoq_vehicle_scout_findings','SELECT')") == "f"
    assert db.val("SELECT command FROM cron.job WHERE jobname='ottoq-vehicle-scouts'") == \
        "SELECT public.ottoq_vehicle_scouts_scan_live()"


# ── 0705 ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def _consult(d, chain, fp, clock=T, objective="readiness_first", outcome="no_effect"):
    d.val(f"""INSERT INTO ottoq_agent_pass_evidence (chain_id, agent_version, sim_run_id, consulted, sim_clock, wake,
                                                     answer, outcome_class)
              VALUES ('{chain}', 'v29', '{RUN}', true, '{clock}', jsonb_build_object('fingerprint', '{json.dumps(fp)}'::jsonb),
                      '{{"solver":{{"objective":"{objective}"}}}}', '{outcome}')""")


def _wake(d):
    return d.json(f"SELECT public.ottoq_agent_wake('{RUN}')")


def test_0705_shadow_mode_always_wakes_and_records_what_the_gate_would_do(db):
    _world(db)
    _apply(db, "0703", "0704", "0705")
    w = _wake(db)
    assert w["wake"] is True and w["gate"] == "shadow" and w["reasons"] == ["first_consult"]
    _consult(db, "k1", w["fingerprint"])
    w = _wake(db)
    assert w["wake"] is True and w["would_wake"] is False and w["reasons"] == []


def test_0705_with_the_gate_on_only_a_change_wakes_the_agent(db):
    _world(db)
    _apply(db, "0703", "0704", "0705")
    db.val(f"INSERT INTO ottoq_policy_params VALUES ('run', '{RUN}', 'agent_wake_enabled', 1, 'test', now())")
    fp = _wake(db)["fingerprint"]
    _consult(db, "k1", fp, objective="throughput_first")
    w = _wake(db)
    assert w["wake"] is False and w["standing_objective"] == "throughput_first", w

    # a charger faults
    db.val(f"UPDATE ottoq_ocpp_chargers SET station_state='Faulted' WHERE charger_id='{_id('F1')}'")
    w = _wake(db)
    assert w["wake"] is True and "charger_fault" in w["reasons"], w
    _consult(db, "k2", w["fingerprint"])
    assert _wake(db)["wake"] is False

    # the line outgrows the open chargers (one open L2, two cars waiting) and one is past its contract wait
    db.val(f"INSERT INTO stub_kernel_line VALUES ('{RUN}', '{_id('H')}', 1, 45, 30), ('{RUN}', '{_id('A')}', 2, 10, 50)")
    w = _wake(db)
    assert w["wake"] is True and {"contention_onset", "contract_wait"} <= set(w["reasons"]), w
    _consult(db, "k3", w["fingerprint"])

    # a fallback does not count as the agent having looked
    db.val(f"""INSERT INTO ottoq_agent_pass_evidence (chain_id, agent_version, sim_run_id, consulted, sim_clock, outcome_class)
               VALUES ('k4', 'v29', '{RUN}', true, '{T}', 'fallback')""")
    assert _wake(db)["wake"] is False

    # the heartbeat: 31 sim-minutes on
    db.val(f"UPDATE ottoq_sim_runs SET sim_clock_current = sim_clock_current + interval '31 minutes'")
    w = _wake(db)
    assert w["wake"] is True and "heartbeat" in w["reasons"], w


def test_0705_a_broken_wake_test_wakes_rather_than_skips(db):
    _world(db)
    _apply(db, "0703", "0704", "0705")
    db.val(f"INSERT INTO ottoq_policy_params VALUES ('run', '{RUN}', 'agent_wake_enabled', 1, 'test', now())")
    db.val("ALTER TABLE public.ottoq_dr_calls RENAME TO ottoq_dr_calls_gone")
    w = _wake(db)
    assert w["wake"] is True and w["reasons"] == ["wake_error"], w
