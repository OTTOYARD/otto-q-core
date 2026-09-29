"""db/migrations/0565, EXECUTED against a stub engine: the throughput scorecard counts what its definitions say.

WHY THIS EXISTS. 0565 turns a run into the numbers Lane A will quote: visits served, door-to-door time, on time, and rule
9 as two counts that must read 0. Those definitions (0565 section 3) are the claim, so each is pinned by a visit built to
exercise it. tests/fixtures/throughput_stub_engine.sql holds one finished 24-hour run on the twin depot, a live run the
backfill must skip, and a passed determinism pair whose arms must score identically. The migration's own V-blocks run
during the apply here, including its append-only and determinism checks.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_operator_start_interrupt_sql.py. It uses
$PGHOST/$PGPORT/$PGUSER/$PGPASSWORD when PGHOST is set, else the local cluster on /var/tmp:55432.
"""
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "throughput_stub_engine.sql")
M0565 = os.path.join(ROOT, "db", "migrations", "0565_a_scorecard_that_counts_cars_served.sql")
M0566 = os.path.join(ROOT, "db", "migrations", "0566_the_scorecard_reads_the_step_a_run_actually_took.sql")

RUN = "a0000000-0000-0000-0000-000000000001"
LIVE_RUN = "a0000000-0000-0000-0000-000000000002"
KPI_FAIL_RUN = "a0000000-0000-0000-0000-000000000003"


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

    def val(self, sql):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True)
        if p.returncode != 0:
            raise AssertionError(f"SQL failed: {p.stderr}\n--- sql ---\n{sql}")
        out = [l for l in p.stdout.splitlines() if l.strip()]
        return out[-1] if out else ""

    def json(self, sql):
        return json.loads(self.val(sql))

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr


@pytest.fixture(scope="module")
def db():
    name = f"ottoq_tsc_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub engine did not load: {err}"
        rc, err = d.file(M0565)
        assert rc == 0, f"0565 did not apply: {err}"
        d.apply_notices = err
        d.scorecard_0565 = d.json(f"SELECT public.ottoq_throughput_scorecard('{RUN}')")
        rc, err = d.file(M0566)
        assert rc == 0, f"0566 did not apply: {err}"
        yield d
    finally:
        subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


@pytest.fixture(scope="module")
def sc(db):
    return db.json(f"SELECT public.ottoq_throughput_scorecard('{RUN}')")


def test_a_second_apply_refuses(db):
    rc, err = db.file(M0565)
    assert rc != 0 and "0565 P2" in err, err
    rc, err = db.file(M0566)
    assert rc != 0 and "0566 P" in err, err


def test_throughput_counts_served_visits_not_cars_parked(sc):
    t = sc["throughput"]
    assert (t["visits"], t["visits_served"], t["in_depot_at_horizon"]) == (7, 6, 1)
    assert t["vehicles_served"] == 5          # vehicle F left twice and is one vehicle
    assert float(t["served_per_day"]) == 6.0  # a 24-hour horizon
    assert t["peak_hour_served"] == 2         # 12:00 and 12:30 share an hour; 14:00 and 15:00 do not


def test_a_departure_belongs_to_the_visit_it_ends(db):
    rows = db.json("SELECT json_agg(json_build_object('v', visit_id, 'dep', departed_at) ORDER BY arrived_at) "
                   f"FROM public.ottoq_visit_outcomes('{RUN}') WHERE vehicle_id = 'c0000000-0000-0000-0000-00000000000f'")
    assert [r["dep"][11:16] for r in rows] == ["09:00", "14:00"], rows


def test_rule9_counts_what_the_rule_forbids(sc):
    r9 = sc["rule9"]
    assert r9["departures"] == 6
    assert r9["left_below_target"] == 1            # E left at 90 of a 100 target
    assert r9["left_with_needed_work_open"] == 2   # C's wash ended after it left; E's repair was cancelled, not cleared
    assert r9["atoms_cleared_by_triage"] == 1      # B's tidy: inspected and not needed, so not open
    assert r9["charge_unknown_at_departure"] == 0 and r9["done_atoms_without_a_time"] == 0


def test_a_triage_clear_is_not_open_but_any_other_cancellation_is(db):
    got = db.json("SELECT json_object_agg(archetype, needed_open_at_departure) "
                  f"FROM public.ottoq_visit_outcomes('{RUN}') WHERE departed_at IS NOT NULL AND archetype <> 'std_mixed'")
    assert got == {"D_charge_and_go": 0, "A_charge_clean_go": 1, "E_tech_hold_fault": 1}, got
    b = db.val(f"SELECT needed_open_at_departure FROM public.ottoq_visit_outcomes('{RUN}') "
               "WHERE visit_id = 'b0000000-0000-0000-0000-00000000000b'")
    assert b == "0"


def test_timeliness(sc):
    t = sc["timeliness"]
    assert (t["due_served"], t["on_time"], float(t["on_time_pct"])) == (2, 1, 50.0)
    assert (float(t["late_p50_min"]), float(t["late_p95_min"])) == (60.0, 60.0)
    # door minutes of the six served visits: 30, 60, 60, 90, 120, 360
    assert (float(t["door_p50_min"]), float(t["door_p95_min"])) == (75.0, 300.0)


def test_tier_groups_partition_the_visits(sc):
    g = sc["by_tier_group"]
    assert {k: v["visits"] for k, v in g.items()} == {"pass_through": 2, "full_service": 4, "fault": 1}
    assert g["full_service"]["in_depot"] == 1 and g["pass_through"]["served"] == 2
    assert float(g["pass_through"]["on_time_pct"]) == 50.0 and g["full_service"]["on_time_pct"] is None


def test_fast_chargers(sc):
    f = sc["fast_chargers"]
    assert (f["at_depot"], f["used"], f["sessions"]) == (2, 2, 2)
    assert float(f["turns_per_charger_per_day"]) == 1.0
    assert float(f["busy_pct"]) == 4.2       # 2 plugged hours of 48 charger-hours
    assert (float(f["mean_session_min"]), float(f["kwh_per_session_hour"])) == (60.0, 40.0)
    assert sc["l2_sessions"] == 1


def test_the_step_travels_with_every_time(sc):
    assert sc["scorecard_version"] == "0566"
    assert float(sc["step_min"]) == 30.0 and float(sc["step_min_nominal"]) == 30.0
    assert sc["caveats"][0].startswith("Times are quantized to the run's 30.00-minute steps")
    assert None not in sc["caveats"]


def test_the_step_is_the_one_the_run_took_not_the_nominal_one(db):
    # KPI_FAIL_RUN: 7 ticks over 14 sim-minutes (2-minute steps), nominal 120 s x 1 = 2 minutes. Stretch the nominal:
    # the scorecard must still read the step off the clock. Run ...02 is live and 0566 never scored it.
    k = db.json(f"SELECT public.ottoq_throughput_scorecard('{KPI_FAIL_RUN}')")
    assert float(k["step_min"]) == 2.0
    live = db.json(f"SELECT public.ottoq_throughput_scorecard('{LIVE_RUN}')")
    assert float(live["step_min"]) == 12.0 and float(live["step_min_nominal"]) == 30.0   # 120 min over 10 ticks


def test_a_short_run_carries_no_daily_rate(db):
    k = db.json(f"SELECT public.ottoq_throughput_scorecard('{KPI_FAIL_RUN}')")
    assert k["throughput"]["served_per_day"] is None
    assert k["fast_chargers"]["turns_per_charger_per_day"] is None
    assert any("under 6, so per-day rates are not extrapolated" in c for c in k["caveats"]), k["caveats"]


def test_0565_scored_the_nominal_step_and_its_rows_stay(db):
    assert db.scorecard_0565["scorecard_version"] == "0565"
    n = db.val("SELECT count(*) FROM public.ottoq_throughput_scores WHERE origin = 'backfill_0565'")
    assert n == "4"


def test_the_latest_view_reads_the_newest_scorecard(db):
    got = db.val("SELECT string_agg(DISTINCT scorecard->>'scorecard_version', ',') FROM public.ottoq_throughput_scores_latest")
    assert got == "0566"
    assert db.val("SELECT count(*) FROM public.ottoq_throughput_scores_latest") == "4"
    assert db.val("SELECT has_table_privilege('anon', 'public.ottoq_throughput_scores_latest', 'SELECT')") == "f"


def test_a_failing_kpi_is_reported_not_fatal(db):
    k = db.json(f"SELECT public.ottoq_throughput_scorecard('{KPI_FAIL_RUN}')")
    assert k["throughput"]["visits_served"] == 1 and k["kpi"] is None
    assert k["kpi_errors"] == {"kpi_five": "field name must not be null"}, k["kpi_errors"]
    assert k["charge_wait"] is not None and k["service_completion"] is not None


def test_a_healthy_run_reports_no_kpi_errors(sc):
    assert sc["kpi_errors"] == {} and sc["kpi"]["peak_site_kw"] == 400.0


def test_the_scorecard_is_deterministic(db, sc):
    again = db.json(f"SELECT public.ottoq_throughput_scorecard('{RUN}')")
    assert again == sc


def test_the_backfill_scored_finished_runs_and_skipped_the_live_one(db):
    runs = db.val("SELECT string_agg(sim_run_id::text, ',' ORDER BY sim_run_id) FROM public.ottoq_throughput_scores "
                  "WHERE origin = 'backfill_0565'").split(",")
    assert LIVE_RUN not in runs and RUN in runs and KPI_FAIL_RUN in runs and len(runs) == 4, runs
    assert db.val("SELECT bool_and(scorecard_md5 = md5(scorecard::text)) FROM public.ottoq_throughput_scores") == "t"


def test_the_determinism_pair_was_checked_and_the_rule9_finding_reported(db):
    assert "scores identically" in db.apply_notices, db.apply_notices
    assert "RULE 9 FINDING" in db.apply_notices, db.apply_notices


def test_the_evidence_table_is_append_only(db):
    p = subprocess.run(["psql", *_conn_args(), "-d", db.name, "-q", "-At", "-c",
                        "DELETE FROM public.ottoq_throughput_scores"], capture_output=True, text=True)
    assert p.returncode != 0 and "append-only" in p.stderr, p.stderr


def test_grants_read_for_authenticated_write_for_service_role(db):
    fn = "'public.ottoq_throughput_scorecard(uuid)'"
    wr = "'public.ottoq_throughput_score_write(uuid,text)'"
    assert db.val(f"SELECT has_function_privilege('authenticated', {fn}, 'EXECUTE')") == "t"
    assert db.val(f"SELECT has_function_privilege('anon', {fn}, 'EXECUTE')") == "f"
    assert db.val(f"SELECT has_function_privilege('authenticated', {wr}, 'EXECUTE')") == "f"
    assert db.val(f"SELECT has_function_privilege('service_role', {wr}, 'EXECUTE')") == "t"
    assert db.val("SELECT has_table_privilege('anon', 'public.ottoq_throughput_scores', 'SELECT')") == "f"


def test_registered_as_evidence_and_classified_as_no_sweep(db):
    assert db.val("SELECT class FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_throughput_scores'") == "evidence"
    row = db.json("SELECT row_to_json(l) FROM public.ottoq_cert_lineage l "
                  "WHERE name = '0565_a_scorecard_that_counts_cars_served'")
    assert row["forces_recert"] is False and row["forces_dial_restart"] is False
