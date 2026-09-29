"""db/migrations/0568, EXECUTED against a stub engine: the overnight sweep runs one scored test day at a time.

WHY THIS EXISTS. 0568's runner will run unattended from 11 PM to 6 AM CT, moving the one depot every demo and every canon
uses. What it must get right is the harness, not the engine: it runs only in its window, only between runs and only
after certification; it goes seed by seed and cell by cell and never repeats an arm since the dial floor; it applies a
build-out before the operator's door and takes it back out after the teardown, filing both to no run; it records an
engine error with its arm and a failed arm without retrying it forever; and what it keeps is evidence nobody can edit.
tests/fixtures/throughput_sweep_stub.sql reduces the engine to exactly what those claims can be tested against.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_throughput_scorecard_sql.py.
"""
import json
import os
import shutil
import subprocess
import time
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "tests", "fixtures")
MIG = os.path.join(ROOT, "db", "migrations")
LOAD = [os.path.join(FIX, "throughput_stub_engine.sql"), os.path.join(FIX, "site_buildout_stub.sql"),
        os.path.join(FIX, "throughput_sweep_stub.sql"),
        os.path.join(MIG, "0565_a_scorecard_that_counts_cars_served.sql"),
        os.path.join(MIG, "0566_the_scorecard_reads_the_step_a_run_actually_took.sql"),
        os.path.join(MIG, "0567_a_charger_build_out_lives_only_inside_a_test_day.sql")]
M0568 = os.path.join(MIG, "0568_an_overnight_sweep_scores_one_test_day_at_a_time.sql")
TWIN = "11111111-1111-1111-1111-111111111111"
SWEEP = "frontier_2026_09_29"

OPEN = ("SELECT public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000', "
        "'throughput_sweep_runner_enabled', 1, 'test')")
CLOSE = ("SELECT public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000', "
         "'throughput_sweep_runner_enabled', 0, 'test')")
RUN = "SELECT public.ottoq_throughput_sweep_runner()"
ARMS = f"""SELECT COALESCE(jsonb_agg(jsonb_build_object('ord', c.ord, 'k', array_position(s.seeds, a.seed),
                                                        'replicate', a.replicate, 'complete', a.complete,
                                                        'error', a.arm_error IS NOT NULL) ORDER BY a.arm_id), '[]')
             FROM public.ottoq_throughput_sweep_arms a
             JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
             JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
            WHERE s.sweep_code = '{SWEEP}'"""


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

    def fails(self, sql):
        rc, _, err = self.run(sql)
        assert rc != 0, f"expected failure, but it succeeded:\n{sql}"
        return err

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr


def _make_db(tag, release=True):
    name = f"ottoq_{tag}_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    for path in LOAD:
        rc, err = d.file(path)
        assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
    rc, err = d.file(M0568)
    assert rc == 0, f"0568 did not apply: {err}"
    d.apply_notices = err
    if release:
        # Most tests drive night 1 directly: the smoke sweep is set aside and night 1 is made due now.
        d.val("UPDATE public.ottoq_throughput_sweeps SET status = 'concluded' WHERE sweep_code = 'smoke_2026_09_29'")
        d.val(f"UPDATE public.ottoq_throughput_sweeps SET run_after = NULL WHERE sweep_code = '{SWEEP}'")
    return d


def _drop(d):
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q"]
    subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {d.name} WITH (FORCE)"], capture_output=True)


@pytest.fixture(scope="module")
def db():
    d = _make_db("tsw")
    try:
        yield d
    finally:
        _drop(d)


@pytest.fixture()
def fresh():
    d = _make_db("tswf")
    try:
        yield d
    finally:
        _drop(d)


def test_the_first_sweep_is_defined_and_the_runner_waits_for_its_window(db):
    assert db.val(f"SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s "
                  f"USING (sweep_id) WHERE s.sweep_code = '{SWEEP}'") == "6"
    sw = db.json(f"SELECT to_jsonb(s) FROM public.ottoq_throughput_sweeps s WHERE sweep_code = '{SWEEP}'")
    assert sw["ticks"] == 144 and float(sw["sim_min_per_tick"]) == 5 and len(sw["seeds"]) == 5 and sw["replicates"] == 1
    assert sw["sim_start"].startswith("2026-09-01T11:00:00")
    jobs = db.json("SELECT jsonb_object_agg(jobname, schedule) FROM cron.job")
    assert jobs == {"ottoq-throughput-sweep-runner": "*/2 * * * *", "ottoq_sweep_window_open": "0 4 * * *",
                    "ottoq_sweep_window_close": "0 11 * * *"}
    assert db.json(RUN) == {"ran": False, "why": "throughput_sweep_runner_enabled is 0"}
    rc, err = db.file(M0568)
    assert rc != 0 and "0568 P2" in err


def test_the_smoke_arm_runs_first_and_night_one_waits_for_its_window():
    d = _make_db("tsws", release=False)
    try:
        d.val(OPEN)
        res = d.json(RUN)
        assert res["ran"] is True and res["arm"]["sweep"] == "smoke_2026_09_29" and res["arm"]["cell"] == "dcfc20.otto_q"
        assert res["arm"]["complete"] is True
        a = d.json("SELECT to_jsonb(a) FROM public.ottoq_throughput_sweep_arms a")
        assert a["ticks"] == 24 and a["buildout"]["buildout_code"] == "dcfc20" and a["restore"]["spaces"] == 10
        assert d.json(RUN) == {"ran": False, "why": "no active sweep has an arm left to run"}
        st = d.json("SELECT jsonb_object_agg(sweep_code, status) FROM public.ottoq_throughput_sweeps")
        assert st == {"smoke_2026_09_29": "concluded", SWEEP: "active"}      # night 1 is not due before 11 PM CT
        assert d.val(f"SELECT run_after FROM public.ottoq_throughput_sweeps WHERE sweep_code = '{SWEEP}'").startswith(
            "2026-09-30 04:00:00")
    finally:
        _drop(d)


def test_an_arm_runs_the_cell_on_its_build_out_and_scores_it(fresh):
    d = fresh
    d.val(OPEN)
    res = d.json(RUN)
    assert res["ran"] is True and res["arm"]["cell"] == "dcfc10.otto_q" and res["arm"]["complete"] is True
    a = d.json("SELECT to_jsonb(a) FROM public.ottoq_throughput_sweep_arms a")
    assert a["complete"] and a["paid_shield"] and a["ticks"] == 144 and a["arm_error"] is None
    assert a["buildout"]["buildout_code"] == "dcfc10" and a["restore"]["restored"] is True
    assert a["scorecard"]["scorecard_version"] == "0567" and a["scorecard"]["run"]["site_buildout"] == "dcfc10"
    assert a["scorecard"]["throughput"]["visits_served"] == 1
    assert a["scorecard"]["step_min"] == 5 or float(a["scorecard"]["step_min"]) == 5.0
    run = d.json(f"SELECT to_jsonb(r) FROM public.ottoq_sim_runs r WHERE sim_run_id = '{a['sim_run_id']}'")
    assert float(run["time_scale"]) == 10 and run["tick_interval_seconds"] == 30 and run["status"] == "stopped"
    assert run["validation_status"] == "passed" and run["run_by"] == "ab_harness"
    assert run["payload"]["throughput_sweep"]["cell_code"] == "dcfc10.otto_q"
    params = d.json(f"""SELECT jsonb_object_agg(param_key, param_value) FROM public.ottoq_policy_params
                        WHERE scope_type = 'run' AND scope_id = '{a['sim_run_id']}'""")
    assert params == {"cuopt_propose_enabled": 0, "cuopt_first_refusal_max_defers": 0, "orchestrator_agent_enabled": 0,
                      "proposer_seat": 0, "deploy_peak_fraction": 0.90}
    # the score was written as evidence too
    assert d.val(f"SELECT origin FROM public.ottoq_throughput_scores WHERE sim_run_id = '{a['sim_run_id']}'") == "sweep_0568"


def test_the_night_goes_seed_by_seed_with_the_replicate_after_seed_one_and_then_concludes(fresh):
    d = fresh
    d.val(OPEN)
    for _ in range(31):
        assert d.json(RUN)["ran"] is True
    arms = d.json(ARMS)
    order = [(x["k"], x["ord"], x["replicate"]) for x in arms]
    expected = [(1, o, False) for o in range(1, 7)] + [(1, 1, True)]
    expected += [(k, o, False) for k in range(2, 6) for o in range(1, 7)]
    assert order == expected
    assert all(x["complete"] for x in arms)
    assert d.json(RUN) == {"ran": False, "why": "no active sweep has an arm left to run"}
    assert d.val(f"SELECT status FROM public.ottoq_throughput_sweeps WHERE sweep_code = '{SWEEP}'") == "concluded"

    fr = d.json("""SELECT jsonb_object_agg(cell_code, jsonb_build_array(arms, valid_arms, failed_arms, visits_served->'mean',
                                                                        deployed_car_hours)) FROM public.ottoq_throughput_frontier""")
    assert fr["dcfc10.otto_q"] == [5, 5, 0, 1.0, 105.0] and fr["dcfc20.fifo"] == [5, 5, 0, 1.0, 100.0]
    pairs = d.json("""SELECT jsonb_build_array(count(*), bool_and(world_identical), min(deployed_car_hours_delta),
                                               max(deployed_car_hours_delta)) FROM public.ottoq_throughput_sweep_pairs""")
    assert pairs == [20, True, 5, 5]      # 5 seeds x 2 build-outs x 2 baselines, each against OTTO-Q on the same world
    rep = d.json("SELECT jsonb_agg(jsonb_build_array(cell_code, identical, moved)) FROM public.ottoq_throughput_sweep_replicates")
    assert rep == [["dcfc10.otto_q", True, []]]


def test_the_build_out_is_applied_before_the_door_and_restored_after_the_teardown_all_filed_to_no_run(fresh):
    d = fresh
    d.val(OPEN)
    for _ in range(4):          # cells 1-4: the fourth is dcfc20.otto_q
        d.json(RUN)
    calls = d.json("SELECT jsonb_agg(jsonb_build_object('fn', fn) || args ORDER BY n) FROM public.stub_calls")
    doors = [c for c in calls if c["fn"] == "door"]
    assert [c["census"] for c in doors] == ["10dcfc/11l2"] * 3 + ["20dcfc/1l2"]
    stops = [c for c in calls if c["fn"] == "stop"]
    assert [c["census"] for c in stops] == ["10dcfc/11l2"] * 3 + ["20dcfc/1l2"]   # restored only after the teardown
    resets = [c for c in calls if c["fn"] == "reset"]
    assert all(c["guc"] == "none" for c in resets)
    # and after the arm the depot is as built
    assert d.val(f"SELECT public.stub_census('{TWIN}')") == "10dcfc/11l2"
    assert d.val("SELECT count(*) FROM public.ottoq_site_buildout_active") == "0"
    a4 = d.json("SELECT to_jsonb(a) FROM public.ottoq_throughput_sweep_arms a ORDER BY arm_id DESC LIMIT 1")
    assert a4["buildout"]["buildout_code"] == "dcfc20" and a4["restore"]["spaces"] == 10
    assert a4["scorecard"]["fast_chargers"]["at_depot"] == 20


def test_an_engine_error_ends_its_arm_is_recorded_with_it_and_the_depot_is_restored(fresh):
    d = fresh
    seed1 = d.val(f"SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = '{SWEEP}'")
    d.val(f"INSERT INTO public.stub_faults (seed, at_tick) VALUES ({seed1}, 5)")
    d.val(OPEN)
    res = d.json(RUN)
    assert res["ran"] is True and res["arm"]["complete"] is False
    a = d.json("SELECT to_jsonb(a) FROM public.ottoq_throughput_sweep_arms a")
    assert a["complete"] is False and a["arm_error"]["tick"] == 5 and "stub engine error" in a["arm_error"]["error"]
    assert a["restore"]["restored"] is True
    assert d.val(f"SELECT validation_status FROM public.ottoq_sim_runs WHERE sim_run_id = '{a['sim_run_id']}'") == "inconclusive"
    # the night moves on to the next cell
    assert d.json(RUN)["arm"]["cell"] == "dcfc10.fifo"


def test_a_failed_arm_is_recorded_not_retried_and_leaves_no_build_out(fresh):
    d = fresh
    seed1 = d.val(f"SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = '{SWEEP}'")
    d.val(f"INSERT INTO public.stub_faults (seed, at_door) VALUES ({seed1}, true)")
    d.val(OPEN)
    res = d.json(RUN)
    assert res["ran"] is True and res["failed"] is True and "fleet seed failed" in res["error"]
    a = d.json("SELECT to_jsonb(a) FROM public.ottoq_throughput_sweep_arms a")
    assert a["complete"] is False and a["sim_run_id"] is None and a["arm_error"]["stage"] == "arm"
    assert d.val("SELECT count(*) FROM public.ottoq_site_buildout_active") == "0"
    assert d.val(f"SELECT public.stub_census('{TWIN}')") == "10dcfc/11l2"
    # not retried: the next firing takes the next cell (whose door fails too on this seed, and is also moved past)
    assert d.json(RUN)["cell_id"] != res["cell_id"]


def test_the_runner_stands_down_for_a_live_run_certification_and_a_held_world(fresh):
    d = fresh
    d.val(OPEN)
    d.val("UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = 'a0000000-0000-0000-0000-000000000002'")
    assert d.json(RUN)["why"] == "a run is live"
    d.val("UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = 'a0000000-0000-0000-0000-000000000002'")
    d.val("INSERT INTO public.ottoq_determinism_canon VALUES (true, false)")
    assert d.json(RUN)["why"].startswith("certification has priority: 1 canon column")
    d.val("DELETE FROM public.ottoq_determinism_canon")
    holder = subprocess.Popen(["psql", *_conn_args(), "-d", d.name, "-q", "-c",
                               "BEGIN; SELECT pg_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint); "
                               "SELECT pg_sleep(4); COMMIT;"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.0)
        assert d.json(RUN)["why"].startswith("the world lock is held")
    finally:
        holder.wait(timeout=20)
    assert d.val("SELECT count(*) FROM public.ottoq_throughput_sweep_arms") == "0"


def test_a_floor_change_makes_every_arm_stale_and_the_sweep_starts_over(fresh):
    d = fresh
    d.val(OPEN)
    d.json(RUN)
    d.json(RUN)
    d.val("UPDATE public.stub_floor SET floor = clock_timestamp()")
    assert d.json(RUN)["arm"]["cell"] == "dcfc10.otto_q"
    fr = d.json("SELECT jsonb_object_agg(cell_code, arms) FROM public.ottoq_throughput_frontier")
    assert fr == {"dcfc10.otto_q": 1}        # the two stale arms no longer count


def test_the_arm_refuses_what_the_sweep_does_not_define_or_has_already_run(fresh):
    d = fresh
    cell1 = d.val(f"""SELECT c.cell_id FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s
                      USING (sweep_id) WHERE s.sweep_code = '{SWEEP}' AND c.ord = 1""")
    seed1 = d.val(f"SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = '{SWEEP}'")
    assert "is not one of sweep" in d.fails(f"SELECT public.ottoq_throughput_sweep_arm('{cell1}', 42)")
    assert "needs a complete primary" in d.fails(f"SELECT public.ottoq_throughput_sweep_arm('{cell1}', {seed1}, true)")
    d.val(f"SELECT public.ottoq_throughput_sweep_arm('{cell1}', {seed1})")
    assert "already ran since the dial floor" in d.fails(f"SELECT public.ottoq_throughput_sweep_arm('{cell1}', {seed1})")
    # a cell holding an uncatalogued dial fails in the arm, and the runner records it rather than looping on it
    d.val(f"""UPDATE public.ottoq_throughput_sweep_cells SET fixed_params = '{{"no_such_dial": 1}}'
              WHERE cell_id = (SELECT c.cell_id FROM public.ottoq_throughput_sweep_cells c
                                 JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                                WHERE s.sweep_code = '{SWEEP}' AND c.ord = 2)""")
    d.val(OPEN)
    res = d.json(RUN)
    assert res["failed"] is True and "uncatalogued or outside its range" in res["error"]


def test_the_arms_are_evidence(db):
    db.val(OPEN)
    db.json(RUN)
    db.val(CLOSE)
    assert "append-only" in db.fails("UPDATE public.ottoq_throughput_sweep_arms SET complete = false")
    assert "append-only" in db.fails("DELETE FROM public.ottoq_throughput_sweep_arms")
    assert db.val("""SELECT class FROM public.ottoq_run_scope_registry
                     WHERE table_name = 'ottoq_throughput_sweep_arms' AND column_name = 'sim_run_id'""") == "evidence"


def test_grants_and_lineage(db):
    def can(role, fn):
        return db.val(f"SELECT has_function_privilege('{role}', '{fn}', 'EXECUTE')") == "t"
    assert not can("anon", "public.ottoq_throughput_sweep_runner()")
    assert not can("authenticated", "public.ottoq_throughput_sweep_runner()")
    assert can("service_role", "public.ottoq_throughput_sweep_runner()")
    assert not can("authenticated", "public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)")
    for v in ("ottoq_throughput_frontier", "ottoq_throughput_sweep_pairs", "ottoq_throughput_sweep_replicates",
              "ottoq_throughput_sweep_arms"):
        assert db.val(f"SELECT has_table_privilege('authenticated', 'public.{v}', 'SELECT')") == "t"
        assert db.val(f"SELECT has_table_privilege('anon', 'public.{v}', 'SELECT')") == "f"
    assert db.val("""SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage
                     WHERE name = '0568_an_overnight_sweep_scores_one_test_day_at_a_time'""") == "false/false"
