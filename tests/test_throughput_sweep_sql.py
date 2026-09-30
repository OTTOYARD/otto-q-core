"""db/migrations/0568, EXECUTED against a stub engine: the overnight sweep runs one scored test day at a time.

WHY THIS EXISTS. 0568's runner will run unattended from 11 PM to 6 AM CT, moving the one depot every demo and every canon
uses. What it must get right is the harness, not the engine: it runs only in its window, only between runs and only
after certification; it goes seed by seed and cell by cell and never repeats an arm since the dial floor; it applies a
build-out before the operator's door and takes it back out after the teardown, filing both to no run; it records an
engine error with its arm and a failed arm without retrying it forever; and what it keeps is evidence nobody can edit.
tests/fixtures/throughput_sweep_stub.sql reduces the engine to exactly what those claims can be tested against.

0569, 0571 and 0572 are tested here too, because they only read or extend what 0568 keeps. 0569: the margin ledger prices each OTTO-Q-against-baseline
pair on demand met (never on cars out beyond demand), keeps a loss a loss, sets aside a pair whose arms were not asked for
the same demand, and moves with a customer's price while the measurement stays put. So is 0571: a treatment cell is
measured against its own control cell, the ledger prices that contrast and keeps every row it held, night 2 is defined on
night 1's seeds, and the same cell definition run on two nights is checked for identity. And 0572: a fleet build-out
borrows the same lender cars every time, parks them, lets the fleet reset seed them, and puts every car and stall pointer
back from its pre-image; it cannot commit applied; and a fleet night's arm borrows before the reset and returns after the
teardown. tests/fixtures/fleet_buildout_stub.sql gives the stub both depots' cars.

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
        os.path.join(FIX, "throughput_sweep_stub.sql"), os.path.join(FIX, "fleet_buildout_stub.sql"),
        os.path.join(MIG, "0565_a_scorecard_that_counts_cars_served.sql"),
        os.path.join(MIG, "0566_the_scorecard_reads_the_step_a_run_actually_took.sql"),
        os.path.join(MIG, "0567_a_charger_build_out_lives_only_inside_a_test_day.sql")]
M0568 = os.path.join(MIG, "0568_an_overnight_sweep_scores_one_test_day_at_a_time.sql")
M0569 = os.path.join(MIG, "0569_a_margin_ledger_prices_what_the_twin_measured.sql")
M0571 = os.path.join(MIG, "0571_a_sweep_measures_a_dial_against_its_own_control.sql")
M0572 = os.path.join(MIG, "0572_a_fleet_build_out_borrows_cars_for_one_test_day.sql")
NIGHT2 = "charge_order_2026_09_30"
F150, F200 = "fleet150_2026_10_01", "fleet200_2026_10_01"
LENDER = "22222222-2222-2222-2222-222222222222"
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


def _make_db(tag, release=True, ledger=True, night2=True, fleet=True):
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
    if ledger:
        rc, err = d.file(M0569)
        assert rc == 0, f"0569 did not apply: {err}"
    if ledger and night2:
        rc, err = d.file(M0571)
        assert rc == 0, f"0571 did not apply: {err}"
    if ledger and night2 and fleet:
        rc, err = d.file(M0572)
        assert rc == 0, f"0572 did not apply: {err}"
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
        assert st == {"smoke_2026_09_29": "concluded", SWEEP: "active", NIGHT2: "active",    # nights 1-3 not yet due
                      F150: "active", F200: "active"}
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


# ── 0569: the margin ledger ──────────────────────────────────────────────────────────────────────────────────────────

LEDGER = """SELECT jsonb_agg(jsonb_build_object(
                'b', buildout_code, 'base', baseline, 'seed', seed, 'world', world_identical, 'same_demand', demand_identical,
                'window_h', window_h, 'demand', demand_car_hours, 'deployed', deployed_car_hours_delta,
                'met', demand_met_car_hours_delta,
                'up', jsonb_build_array(uptime_usd_low, uptime_usd_point, uptime_usd_high),
                'cost', site_cost_usd_delta, 'cars', cars_at_work_delta,
                'cap', jsonb_build_array(fleet_capex_equiv_usd_low, fleet_capex_equiv_usd_point, fleet_capex_equiv_usd_high))
                ORDER BY buildout_code, baseline, seed)
             FROM public.ottoq_margin_ledger"""


def _synthetic_pair(d, seed, q_unmet, b_unmet, q_demand=120, b_demand=120):
    """Two arms written the way the arm writes them, on dcfc10 OTTO-Q against dcfc10 FIFO, for a seed the sweep does not
    run: the only way to put a loss, or a pair asked for different demand, in front of the ledger."""
    for cell, unmet, demand in (("dcfc10.otto_q", q_unmet, q_demand), ("dcfc10.fifo", b_unmet, b_demand)):
        d.val(f"""INSERT INTO public.ottoq_throughput_sweep_arms
                    (sweep_id, cell_id, seed, sim_run_id, engine_hash, dial_floor, complete, ticks, paid_shield, boot_md5,
                     h_cal, scorecard, arm_metrics)
                  SELECT s.sweep_id, c.cell_id, {seed}, gen_random_uuid(), 'stub', public.ottoq_dial_pair_floor(), true,
                         144, true, 'boot-{seed}', 'cal-{seed}',
                         '{{"run": {{"horizon_h": 12}}, "throughput": {{"visits_served": 1}},
                           "timeliness": {{"on_time_pct": 90, "door_p50_min": 30}}}}'::jsonb,
                         jsonb_build_object('demand_car_hours', {demand}, 'deployed_car_hours', 100,
                                            'unmet_demand_car_hours', {unmet}, 'site_cost_usd_per_day', 420.25)
                    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                   WHERE s.sweep_code = '{SWEEP}' AND c.cell_code = '{cell}'""")


@pytest.fixture(scope="module")
def priced():
    """Seed 1 on all six cells, its replicate, and seed 2 on all six: eight real pairs. Then two written by hand: seed
    991, where the baseline beats OTTO-Q on the same demand, and seed 992, whose arms were asked for different demand."""
    d = _make_db("tswm")
    try:
        d.val(OPEN)
        for _ in range(13):
            assert d.json(RUN)["ran"] is True
        d.val(CLOSE)
        _synthetic_pair(d, 991, q_unmet=30, b_unmet=24)
        _synthetic_pair(d, 992, q_unmet=20, b_unmet=24, b_demand=130)
        yield d
    finally:
        _drop(d)


def test_the_margin_ledger_prices_demand_met_not_cars_out(priced):
    rows = priced.json(LEDGER)
    real = [r for r in rows if r["seed"] not in (991, 992)]
    assert len(real) == 8          # 2 seeds x 2 build-outs x 2 baselines; the replicate is never a pair
    for r in real:
        assert r["world"] is True and r["same_demand"] is True
        assert float(r["window_h"]) == 12 and float(r["demand"]) == 120
        assert float(r["deployed"]) == 5          # shown beside it, never priced
        assert float(r["cost"]) == 11.25          # OTTO-Q's site cost more: passed through, not re-priced
        if r["base"] == "fifo":
            # 24 unmet against 20: 4 car-hours of demand met, at $16/$20/$24; 4/12 of a car at $75k/$150k/$200k
            assert float(r["met"]) == 4 and r["up"] == [64, 80, 96]
            assert float(r["cars"]) == 0.33 and r["cap"] == [25000, 50000, 66667]
        else:
            assert r["base"] == "greedy"
            assert float(r["met"]) == 6 and r["up"] == [96, 120, 144]
            assert float(r["cars"]) == 0.5 and r["cap"] == [37500, 75000, 100000]


def test_a_loss_stays_a_loss_and_a_pair_asked_for_different_demand_is_shown_but_set_aside(priced):
    rows = {r["seed"]: r for r in priced.json(LEDGER) if r["seed"] in (991, 992)}
    loss = rows[991]
    assert loss["same_demand"] is True and float(loss["met"]) == -6
    assert loss["up"] == [-144, -120, -96] and loss["cap"] == [-100000, -75000, -37500]
    skew = rows[992]
    assert skew["same_demand"] is False and skew["world"] is True and float(skew["met"]) == 4
    summ = priced.json("""SELECT jsonb_object_agg(buildout_code || '.' || baseline, jsonb_build_object(
                                 'seeds', seeds, 'aside', seeds_set_aside, 'met', demand_met_car_hours_delta,
                                 'up', uptime_usd, 'cars', cars_at_work_delta, 'window_h', window_h))
                            FROM public.ottoq_margin_summary""")
    assert set(summ) == {"dcfc10.fifo", "dcfc10.greedy", "dcfc20.fifo", "dcfc20.greedy"}
    f10 = summ["dcfc10.fifo"]
    # seeds 1, 2 and 991 (a loss counts); 992 is set aside, not averaged in
    assert f10["seeds"] == 3 and f10["aside"] == 1
    assert f10["met"] == {"mean": 0.7, "min": -6, "max": 4}
    assert f10["up"] == {"mean_point": 13, "min_low": -144, "max_high": 96}
    g20 = summ["dcfc20.greedy"]
    assert g20["seeds"] == 2 and g20["aside"] == 0 and g20["up"] == {"mean_point": 120, "min_low": 96, "max_high": 144}
    assert float(g20["window_h"]) == 12


def test_a_customer_price_moves_the_dollars_and_not_the_measurement(priced):
    moved = priced.val("""BEGIN;
        UPDATE public.ottoq_margin_prices SET low = 30, point = 35, high = 40
         WHERE price_code = 'revenue_per_deployed_car_hour';
        SELECT jsonb_build_array(demand_met_car_hours_delta, uptime_usd_low, uptime_usd_point, uptime_usd_high)
          FROM public.ottoq_margin_ledger WHERE baseline = 'fifo' AND buildout_code = 'dcfc20' ORDER BY seed LIMIT 1;
        ROLLBACK;""")
    met, lo, pt, hi = json.loads(moved)
    assert float(met) == 4 and [lo, pt, hi] == [120, 140, 160]
    assert priced.val("SELECT point FROM public.ottoq_margin_prices WHERE price_code = 'revenue_per_deployed_car_hour'") == "20"


def test_the_band_keeps_its_order_and_never_reads_a_missing_number_as_zero(db):
    assert db.json("SELECT to_jsonb(public.ottoq_margin_band(-6, 16, 20, 24))") == [-144, -120, -96]
    assert db.json("SELECT to_jsonb(public.ottoq_margin_band(2.5, 16, 20, 24))") == [40, 50, 60]
    assert db.val("SELECT public.ottoq_margin_band(NULL, 16, 20, 24) IS NULL") == "t"
    assert db.val("SELECT public.ottoq_margin_band(6, NULL, 20, 24) IS NULL") == "t"
    # a price whose range is out of order is refused at the door
    assert "check" in db.fails("""INSERT INTO public.ottoq_margin_prices (price_code, unit, low, point, high, lever, basis,
                                    sources, confidence) VALUES ('x', 'usd', 5, 4, 6, 'x', 'x',
                                    '[{"url": "https://example.org", "retrieved": "2026-09-29"}]', 'low')""").lower()


def test_the_prices_carry_their_sources_and_the_ledger_is_read_only(db):
    prices = db.json("""SELECT jsonb_object_agg(price_code, jsonb_build_array(low, point, high, confidence,
                                (SELECT bool_and(s->>'url' ~ '^https://' AND s->>'retrieved' = '2026-09-29')
                                   FROM jsonb_array_elements(sources) s)))
                          FROM public.ottoq_margin_prices""")
    assert prices == {"revenue_per_deployed_car_hour": [16, 20, 24, "medium", True],
                      "vehicle_capex": [75000, 150000, 200000, "low", True],
                      "dcfc_350kw_installed": [193984, 205984, 215984, "medium", True]}
    for v in ("ottoq_margin_prices", "ottoq_margin_ledger", "ottoq_margin_summary"):
        assert db.val(f"SELECT has_table_privilege('authenticated', 'public.{v}', 'SELECT')") == "t"
        assert db.val(f"SELECT has_table_privilege('anon', 'public.{v}', 'SELECT')") == "f"
        assert db.val(f"SELECT has_table_privilege('authenticated', 'public.{v}', 'INSERT')") == "f"
    assert db.val("""SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage
                     WHERE name = '0569_a_margin_ledger_prices_what_the_twin_measured'""") == "false/false"
    rc, err = db.file(M0569)
    assert rc != 0 and "0569 P2" in err


def test_the_ledger_refuses_to_build_on_arm_metrics_without_unmet_demand():
    d = _make_db("tswp", ledger=False)
    try:
        d.val("""CREATE OR REPLACE FUNCTION public.ottoq_dial_arm_metrics(p_run uuid, p_depot uuid, p_soc0 numeric)
                 RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT jsonb_build_object('deployed_car_hours', 100,
                   'site_cost_usd_per_day', 420.25) $$""")
        rc, err = d.file(M0569)
        assert rc != 0 and "0569 P1" in err and "unmet_demand_car_hours" in err
        assert d.val("SELECT to_regclass('public.ottoq_margin_prices') IS NULL") == "t"
    finally:
        _drop(d)


# ── 0571: a dial against its own control, priced; night 2; the same cell on two nights ──────────────────────────────────

def _release_night2(d, pause_night1=True):
    if pause_night1:
        d.val(f"UPDATE public.ottoq_throughput_sweeps SET status = 'paused' WHERE sweep_code = '{SWEEP}'")
    d.val(f"UPDATE public.ottoq_throughput_sweeps SET run_after = NULL WHERE sweep_code = '{NIGHT2}'")


def test_night_two_is_four_cells_and_two_contrasts_on_night_ones_seeds(db):
    cells = db.json(f"""SELECT jsonb_agg(jsonb_build_array(c.ord, c.cell_code, c.seat, c.buildout_code, c.fixed_params,
                                                           c.control_cell_code) ORDER BY c.ord)
                          FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                         WHERE s.sweep_code = '{NIGHT2}'""")
    assert cells == [
        [1, "dcfc10.otto_q", "otto_q", "dcfc10", {"deploy_peak_fraction": 0.90}, None],
        [2, "dcfc10.otto_q.batch_order", "otto_q", "dcfc10", {"deploy_peak_fraction": 0.90, "charge_batch_order": 1},
         "dcfc10.otto_q"],
        [3, "dcfc20.otto_q", "otto_q", "dcfc20", {"deploy_peak_fraction": 0.90}, None],
        [4, "dcfc20.otto_q.batch_order", "otto_q", "dcfc20", {"deploy_peak_fraction": 0.90, "charge_batch_order": 1},
         "dcfc20.otto_q"]]
    n1 = db.json(f"SELECT to_jsonb(s) FROM public.ottoq_throughput_sweeps s WHERE sweep_code = '{SWEEP}'")
    n2 = db.json(f"SELECT to_jsonb(s) FROM public.ottoq_throughput_sweeps s WHERE sweep_code = '{NIGHT2}'")
    assert n2["seeds"] == n1["seeds"] and n2["ticks"] == 144 and n2["replicates"] == 0 and n2["status"] == "active"
    assert n2["run_after"].startswith("2026-10-01T04:00:00") and n2["priority"] == n1["priority"]
    assert db.val("""SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage
                     WHERE name = '0571_a_sweep_measures_a_dial_against_its_own_control'""") == "false/false"
    # a second apply is refused: by P1 (the ledger is no longer 0569's) before P2 can say so itself
    rc, err = db.file(M0571)
    assert rc != 0 and ("0571 P2" in err or "0571 P1" in err)


def test_a_control_is_a_sibling_that_differs_only_by_its_dials(fresh):
    d = fresh
    sid = d.val(f"SELECT sweep_id FROM public.ottoq_throughput_sweeps WHERE sweep_code = '{NIGHT2}'")

    def add(code, ord_, seat, bo, params, control):
        return d.fails(f"""INSERT INTO public.ottoq_throughput_sweep_cells
                             (sweep_id, cell_code, ord, seat, buildout_code, fixed_params, control_cell_code)
                           VALUES ('{sid}', '{code}', {ord_}, '{seat}', '{bo}', '{params}', '{control}')""")
    assert "not seat" in add("x1", 11, "fifo", "dcfc10", '{"charge_batch_order": 1}', "dcfc10.otto_q")
    assert "not seat" in add("x2", 12, "otto_q", "dcfc20", '{"charge_batch_order": 1}', "dcfc10.otto_q")
    assert "is itself a treatment" in add("x3", 13, "otto_q", "dcfc10", '{"charge_batch_order": 0}',
                                          "dcfc10.otto_q.batch_order")
    assert "nothing to contrast" in add("x4", 14, "otto_q", "dcfc10", '{"deploy_peak_fraction": 0.90}', "dcfc10.otto_q")
    assert "not a cell of the same sweep" in add("x5", 15, "otto_q", "dcfc10", '{"charge_batch_order": 1}', "no_such_cell")
    # a control cannot later become a treatment itself, even against a sibling that would otherwise qualify
    d.val(f"""INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
              VALUES ('{sid}', 'dcfc10.otto_q.alt', 21, 'otto_q', 'dcfc10', '{{"deploy_peak_fraction": 0.80}}')""")
    assert "another cell's control" in d.fails(f"""UPDATE public.ottoq_throughput_sweep_cells
                                                     SET control_cell_code = 'dcfc10.otto_q.alt'
                                                   WHERE sweep_id = '{sid}' AND cell_code = 'dcfc10.otto_q'""")


def test_night_two_contrasts_are_measured_and_priced(fresh):
    d = fresh
    _release_night2(d)
    d.val(OPEN)
    for _ in range(8):                      # seeds 1 and 2, four cells each
        assert d.json(RUN)["ran"] is True
    con = d.json("""SELECT jsonb_agg(jsonb_build_array(treatment_cell, control_cell, world_identical, served_delta,
                                                       deployed_car_hours_delta, site_cost_usd_delta)
                                     ORDER BY treatment_cell, seed) FROM public.ottoq_throughput_sweep_contrasts""")
    assert [c[:3] for c in con] == [["dcfc10.otto_q.batch_order", "dcfc10.otto_q", True]] * 2 + \
                                   [["dcfc20.otto_q.batch_order", "dcfc20.otto_q", True]] * 2
    assert all(float(c[3]) == 0 and float(c[4]) == 0 and float(c[5]) == 0 for c in con)
    led = d.json("""SELECT jsonb_agg(jsonb_build_object('b', buildout_code, 'base', baseline, 'met', demand_met_car_hours_delta,
                                                        'up', jsonb_build_array(uptime_usd_low, uptime_usd_point, uptime_usd_high),
                                                        'cars', cars_at_work_delta,
                                                        'cap', jsonb_build_array(fleet_capex_equiv_usd_low,
                                                                                 fleet_capex_equiv_usd_point,
                                                                                 fleet_capex_equiv_usd_high))
                                     ORDER BY buildout_code, seed)
                      FROM public.ottoq_margin_ledger WHERE comparison = 'dial'""")
    assert len(led) == 4
    for r in led:
        # the dial left 3 fewer car-hours of demand unmet: $48 / $60 / $72; a quarter of a car at work over 12 hours
        assert r["base"] == f"{r['b']}.otto_q" and float(r["met"]) == 3 and r["up"] == [48, 60, 72]
        assert float(r["cars"]) == 0.25 and r["cap"] == [18750, 37500, 50000]
    summ = d.json(f"""SELECT jsonb_object_agg(baseline, jsonb_build_array(seeds, seeds_set_aside, uptime_usd->'mean_point'))
                        FROM public.ottoq_margin_summary WHERE sweep_code = '{NIGHT2}'""")
    assert summ == {"dcfc10.otto_q": [2, 0, 60], "dcfc20.otto_q": [2, 0, 60]}


def test_the_ledger_kept_every_row_it_held_before():
    d = _make_db("tswk", night2=False)
    try:
        d.val(OPEN)
        for _ in range(7):                  # seed 1 on all six cells, and its replicate
            d.json(RUN)
        rows = """SELECT jsonb_agg(to_jsonb(l) - 'comparison' ORDER BY buildout_code, baseline, seed)
                    FROM public.ottoq_margin_ledger l"""
        before = d.json(rows)
        assert len(before) == 4
        rc, err = d.file(M0571)
        assert rc == 0, f"0571 did not apply: {err}"
        assert d.json(rows) == before       # every column of every row, unchanged
        assert d.val("SELECT string_agg(DISTINCT comparison, ',') FROM public.ottoq_margin_ledger") == "seat"
    finally:
        _drop(d)


def test_the_same_cell_on_two_nights_is_checked_for_identity(fresh):
    d = fresh
    d.val(OPEN)
    for _ in range(6):                      # night 1, seed 1: all six cells
        d.json(RUN)
    _release_night2(d)
    for _ in range(4):                      # night 2, seed 1: its four cells
        d.json(RUN)
    tw = d.json("""SELECT jsonb_agg(jsonb_build_array(earlier_sweep, earlier_cell, later_sweep, later_cell, identical, moved)
                                    ORDER BY earlier_cell) FROM public.ottoq_throughput_cross_sweep_twins""")
    # only the controls repeat a night-1 definition; the treatments carry a dial night 1 never set
    assert tw == [[SWEEP, "dcfc10.otto_q", NIGHT2, "dcfc10.otto_q", True, []],
                  [SWEEP, "dcfc20.otto_q", NIGHT2, "dcfc20.otto_q", True, []]]


# ── 0572: a fleet build-out borrows cars for one test day ────────────────────────────────────────────────────────────────

LENDER_ROWS = """SELECT COALESCE(jsonb_object_agg(id, to_jsonb(v) - 'updated_at'), '{}')
                   FROM public.vehicles v WHERE vin LIKE 'LENDER-%'"""
LENDER_STALLS = f"""SELECT COALESCE(jsonb_object_agg(id, to_jsonb(s)), '{{}}') FROM public.stalls s WHERE depot_id = '{LENDER}'"""


def test_the_fleet_build_outs_are_the_twins_mix_and_night_three_is_defined(db):
    fb = db.json("""SELECT jsonb_object_agg(fleet_code, jsonb_build_array(borrow_by_class, fleet_size))
                      FROM public.ottoq_fleet_buildouts""")
    assert fb == {"fleet150": [{"tesla_model_y_robotaxi_2024": 11, "waymo_jaguar_ipace_2024": 13, "zoox_robotaxi_2024": 10}, 150],
                  "fleet200": [{"tesla_model_y_robotaxi_2024": 26, "waymo_jaguar_ipace_2024": 34, "zoox_robotaxi_2024": 24}, 200]}
    n1 = db.json(f"SELECT to_jsonb(seeds) FROM public.ottoq_throughput_sweeps WHERE sweep_code = '{SWEEP}'")
    for code, fleet in ((F150, "fleet150"), (F200, "fleet200")):
        sw = db.json(f"SELECT to_jsonb(s) FROM public.ottoq_throughput_sweeps s WHERE sweep_code = '{code}'")
        assert sw["fleet_code"] == fleet and sw["seeds"] == n1[:3] and sw["replicates"] == 0
        assert sw["run_after"].startswith("2026-10-02T04:00:00") and sw["ticks"] == 144
        cells = db.json(f"""SELECT jsonb_agg(jsonb_build_array(c.cell_code, c.seat, c.buildout_code) ORDER BY c.ord)
                              FROM public.ottoq_throughput_sweep_cells c WHERE c.sweep_id = '{sw["sweep_id"]}'""")
        assert cells == [["dcfc20.otto_q", "otto_q", "dcfc20"], ["dcfc20.fifo", "fifo", "dcfc20"],
                         ["dcfc10.otto_q", "otto_q", "dcfc10"]]
    assert db.val("""SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage
                     WHERE name = '0572_a_fleet_build_out_borrows_cars_for_one_test_day'""") == "false/false"
    rc, err = db.file(M0572)
    assert rc != 0 and ("0572 P1" in err or "0572 P2" in err)


def test_a_fleet_build_out_borrows_the_same_cars_and_puts_every_one_back(fresh):
    d = fresh
    cars, stalls = d.json(LENDER_ROWS), d.json(LENDER_STALLS)
    out = d.json(f"""BEGIN;
        CREATE TEMP TABLE r AS SELECT public.ottoq_fleet_buildout_apply('{TWIN}', 'fleet200') AS apply;
        CREATE TEMP TABLE m AS SELECT
            public.ottoq_fleet_buildout_census('{TWIN}') AS census,
            (SELECT count(*) FROM public.vehicles WHERE vin LIKE 'LENDER-%' AND home_depot_id = '{TWIN}'
                                                    AND current_state = 'offline' AND current_stall_id IS NULL) AS parked,
            (SELECT count(*) FROM public.stalls WHERE depot_id = '{LENDER}'
                AND (current_vehicle_id IN (SELECT id FROM public.vehicles WHERE home_depot_id = '{TWIN}')
                  OR reserved_by IN (SELECT id FROM public.vehicles WHERE home_depot_id = '{TWIN}'))) AS still_pointing;
        SELECT public.ottoq_tick_invariance_reset_fleet('{TWIN}', 42, '2026-09-01 11:00+00');
        SELECT public.ottoq_sim_stop_and_reset(gen_random_uuid(), 'test');
        CREATE TEMP TABLE x AS SELECT public.ottoq_fleet_buildout_restore('{TWIN}') AS restore;
        SELECT jsonb_build_object('apply', (SELECT apply FROM r), 'census', (SELECT census FROM m),
                                  'parked', (SELECT parked FROM m), 'pointing', (SELECT still_pointing FROM m),
                                  'restore', (SELECT restore FROM x),
                                  'reset_fleet', (SELECT args->'fleet' FROM public.stub_calls WHERE fn = 'reset'
                                                   ORDER BY n DESC LIMIT 1));
        COMMIT;""")
    a = out["apply"]
    assert a["borrowed"] == 84 and a["fleet_size"] == 200 and a["lender_stalls_cleared"] == 3
    assert out["census"] == {"depot_id": TWIN, "fleet": 200, "applied": "fleet200"}
    assert out["parked"] == 84 and out["pointing"] == 0     # the two frozen in a bay and the reservation let go
    assert out["reset_fleet"] == 200                          # the reset seeded the lent cars with the twin's own
    assert out["restore"]["restored"] is True and out["restore"]["vehicles"] == 84 and out["restore"]["fleet_size"] == 116
    # every lent car and every lender stall is back as it was, although the teardown left one tethered to a twin charger
    assert d.json(LENDER_ROWS) == cars and d.json(LENDER_STALLS) == stalls
    assert d.json(f"SELECT public.ottoq_fleet_buildout_census('{TWIN}')")["fleet"] == 116
    # and the next borrow takes the same cars: per class, in id order
    again = d.json(f"""BEGIN;
        CREATE TEMP TABLE r2 AS SELECT public.ottoq_fleet_buildout_apply('{TWIN}', 'fleet200') AS apply;
        SELECT public.ottoq_fleet_buildout_restore('{TWIN}');
        SELECT apply->'borrowed_ids' FROM r2;
        COMMIT;""")
    assert again == a["borrowed_ids"] and len(again) == 84


def test_a_fleet_build_out_cannot_commit(fresh):
    d = fresh
    cars = d.json(LENDER_ROWS)
    err = d.fails(f"BEGIN; SELECT public.ottoq_fleet_buildout_apply('{TWIN}', 'fleet150'); COMMIT;")
    assert "still applied to depot" in err
    assert d.json(LENDER_ROWS) == cars
    assert d.val("SELECT count(*) FROM public.ottoq_fleet_buildout_active") == "0"


def test_apply_refuses_what_it_cannot_do_cleanly(fresh):
    d = fresh
    assert "is not defined" in d.fails(f"SELECT public.ottoq_fleet_buildout_apply('{TWIN}', 'fleet999')")
    assert "is for depot" in d.fails(f"SELECT public.ottoq_fleet_buildout_apply('{LENDER}', 'fleet150')")
    assert "already applied" in d.fails(f"""BEGIN; SELECT public.ottoq_fleet_buildout_apply('{TWIN}', 'fleet150');
                                              SELECT public.ottoq_fleet_buildout_apply('{TWIN}', 'fleet150'); ROLLBACK;""")
    # a run live at the lender: cars move only between runs
    d.val(f"""UPDATE public.ottoq_sim_runs SET status = 'running', depot_id = '{LENDER}'
              WHERE sim_run_id = 'a0000000-0000-0000-0000-000000000002'""")
    assert "a run is live" in d.fails(f"SELECT public.ottoq_fleet_buildout_apply('{TWIN}', 'fleet150')")
    d.val(f"""UPDATE public.ottoq_sim_runs SET status = 'completed', depot_id = '{TWIN}'
              WHERE sim_run_id = 'a0000000-0000-0000-0000-000000000002'""")
    # a car it would borrow with an open visit
    d.val(f"""INSERT INTO public.ottoq_visit_needs (visit_id, vehicle_id, status)
              SELECT gen_random_uuid(), id, 'open' FROM public.vehicles
               WHERE home_depot_id = '{LENDER}' AND vehicle_class_code = 'zoox_robotaxi_2024' ORDER BY id LIMIT 1""")
    assert "have live rows" in d.fails(f"SELECT public.ottoq_fleet_buildout_apply('{TWIN}', 'fleet150')")


def test_a_fleet_night_borrows_before_the_reset_and_returns_after_the_teardown(fresh):
    d = fresh
    cars = d.json(LENDER_ROWS)
    d.val(f"UPDATE public.ottoq_throughput_sweeps SET status = 'paused' WHERE sweep_code IN ('{SWEEP}', '{NIGHT2}', '{F150}')")
    d.val(f"UPDATE public.ottoq_throughput_sweeps SET run_after = NULL WHERE sweep_code = '{F200}'")
    d.val(OPEN)
    res = d.json(RUN)
    assert res["ran"] is True and res["arm"]["sweep"] == F200 and res["arm"]["complete"] is True
    a = d.json("SELECT to_jsonb(a) FROM public.ottoq_throughput_sweep_arms a")
    assert a["fleet_buildout"]["borrowed"] == 84 and a["fleet_buildout"]["fleet_size"] == 200
    assert a["fleet_restore"]["restored"] is True and a["fleet_restore"]["fleet_size"] == 116
    assert a["restore"]["restored"] is True       # the chargers went back first, then the cars
    run = d.json(f"SELECT payload FROM public.ottoq_sim_runs WHERE sim_run_id = '{a['sim_run_id']}'")
    assert run["fleet_buildout"]["fleet_code"] == "fleet200"
    resets = d.json("SELECT jsonb_agg(args ORDER BY n) FROM public.stub_calls WHERE fn = 'reset'")
    assert resets[-1]["fleet"] == 200 and resets[-1]["guc"] == "none"    # borrowed BEFORE the reset, filed to no run
    assert d.json(LENDER_ROWS) == cars
    assert d.json(f"SELECT public.ottoq_fleet_buildout_census('{TWIN}')") == {"depot_id": TWIN, "fleet": 116, "applied": None}


def test_the_same_cell_at_two_fleet_sizes_is_not_a_twin(fresh):
    d = fresh
    d.val(OPEN)
    for _ in range(4):                      # night 1, seed 1: cells 1-4 (the fourth is dcfc20.otto_q)
        d.json(RUN)
    d.val(f"UPDATE public.ottoq_throughput_sweeps SET status = 'paused' WHERE sweep_code IN ('{SWEEP}', '{NIGHT2}', '{F200}')")
    d.val(f"UPDATE public.ottoq_throughput_sweeps SET run_after = NULL WHERE sweep_code = '{F150}'")
    assert d.json(RUN)["arm"]["cell"] == "dcfc20.otto_q"     # night 3 at 150 cars, seed 1: the same cell definition
    assert d.val("SELECT count(*) FROM public.ottoq_throughput_cross_sweep_twins") == "0"
