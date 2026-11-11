"""db/migrations/0810, EXECUTED against the research lab's copy of the engine: the depot's electrical one-line.

WHY THIS EXISTS. 0810 adds a trigger to the row the tick writes when it reads the site meter. A capture that can change
what a run does, or that reads a rating as a limit, would break two standing rules at once (the fourteen atoms, and
rule 13: nothing below what is installed). db/checks/0481 measured a whole lab day with and without it; this file pins
the parts that need no day: the tree and its sizing rule, the thermal step at its fixed points, the capture's arithmetic
on a known load, its idempotence, the trip door's refusals, and who may call what.

It needs the lab (lab/engine/build_from_prod.sh: PostgreSQL 17 on /var/tmp:55433 with database ottoq_lab) and SKIPS
without it, so CI, which has no lab, skips it. Each run works in a throwaway copy and drops it.
"""
import glob
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M0810 = glob.glob(os.path.join(ROOT, "db", "migrations", "0810_*.sql"))[0]
TWIN = "11111111-1111-1111-1111-111111111111"
ZERO = "00000000-0000-0000-0000-000000000000"
CONN = ["-h", "/var/tmp", "-p", "55433", "-U", "postgres"]


def _psql(db, sql, check=True):
    p = subprocess.run(["psql", *CONN, "-d", db, "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                       capture_output=True, text=True)
    if check and p.returncode != 0:
        raise AssertionError(p.stderr)
    return p.stdout.strip()


def _lab_up():
    if not shutil.which("psql"):
        return False
    p = subprocess.run(["psql", *CONN, "-d", "postgres", "-Atc",
                        "select 1 from pg_database where datname = 'ottoq_lab'"], capture_output=True, text=True)
    return p.returncode == 0 and p.stdout.strip() == "1"


pytestmark = pytest.mark.skipif(not _lab_up(), reason="the research lab (ottoq_lab on /var/tmp:55433) is not running")


@pytest.fixture(scope="module")
def db():
    name = "ottoq_t0810_" + uuid.uuid4().hex[:8]
    _psql("postgres", f"create database {name} template ottoq_lab")
    try:
        p = subprocess.run(["psql", *CONN, "-d", name, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", M0810],
                           capture_output=True, text=True)
        assert p.returncode == 0, p.stderr     # P0 and V1-V6 all ran: the file refuses itself otherwise
        yield name
    finally:
        _psql("postgres", f"drop database if exists {name} with (force)", check=False)


def test_the_tree_is_the_depots_and_no_rating_is_below_what_is_connected(db):
    kinds = json.loads(_psql(db, f"select jsonb_object_agg(kind, n) from (select kind, count(*) n from "
                                 f"ottoq_power_nodes where depot_id = '{TWIN}' group by 1) x"))
    assert kinds == {"utility_service": 1, "mv_switchgear": 1, "transformer": 7, "post": 30, "bess": 1, "building": 1,
                     "solar": 1}
    # rule 13: every transformer carries 125% of everything connected under it, all at once
    worst = float(_psql(db, """
        select min(t.rated_kva / ((select sum(case l.kind when 'post' then l.rated_kw / l.efficiency
                                                    when 'solar' then 0 else l.rated_kw end)
                                     from ottoq_power_nodes l where l.parent_code = t.node_code) / t.power_factor))
          from ottoq_power_nodes t where t.kind = 'transformer'"""))
    assert worst >= 1.25
    # the design is a pure function of the installed hardware: asking again gives the same tree
    assert _psql(db, f"""
        select count(*) from (
          select node_code, parent_code, kind, rated_kva, rated_kw from ottoq_power_one_line_design('{TWIN}')
          except select node_code, parent_code, kind, rated_kva, rated_kw from ottoq_power_nodes) d""") == "0"
    assert _psql(db, f"select service_voltage::int from depots where id = '{TWIN}'") == "13800"


def test_no_engine_function_reads_the_tree_to_decide(db):
    """Rule 13 as a property of the code: only 0810's own functions mention the power tables."""
    readers = _psql(db, """
        select string_agg(p.proname, ',' order by p.proname) from pg_proc p
         where p.pronamespace::regnamespace::text in ('public', 'ottoq', 'twin') and p.prosrc ~ 'ottoq_power_node'""")
    assert set(readers.split(",")) == {
        "ottoq_power_capture", "ottoq_power_one_line", "ottoq_power_one_line_design", "ottoq_power_resilience", "ottoq_power_rightsize",
        "ottoq_power_study_on_run_end", "ottoq_twin_trip_power_node"}


def test_the_thermal_step_at_its_fixed_points(db):
    q = lambda k, dt, a, b: [float(x) for x in _psql(  # noqa: E731
        db, f"select top_oil_rise || ',' || hot_spot_rise from ottoq_power_thermal_step({k}, {dt}, {a}, {b}, 55, 25, 5, 180, 5, 0.8, 0.8)").split(",")]
    assert q(1, 100000, 10, 3) == pytest.approx([55, 25], abs=1e-3)              # rated load settles at the rated rises
    assert q(1, 180, 0, 25)[0] == pytest.approx(55 * (1 - 2.718281828 ** -1), abs=1e-3)   # one time constant: 63.2%
    assert q(2, 0.0001, 20, 5) == pytest.approx([20, 5], abs=0.01)               # almost no time, almost no change, whatever the load
    assert q(1.2, 100000, 0, 0)[1] == pytest.approx(25 * 1.2 ** 1.6, abs=1e-3)   # hot-spot rise goes with K^(2m)
    first = q(0.5, "NULL", "NULL", "NULL")                                       # a run's first reading starts settled
    assert first == pytest.approx(q(0.5, 100000, 0, 0), abs=1e-3)
    assert float(_psql(db, "select ottoq_power_aging_factor(110)")) == 1.0
    assert float(_psql(db, "select ottoq_power_aging_factor(98)")) == pytest.approx(0.2817, abs=1e-3)    # 12 C cooler: under a third
    assert float(_psql(db, "select ottoq_power_aging_factor(122)")) == pytest.approx(3.2864, abs=1e-3)   # 12 C hotter: over three times


def test_the_capture_adds_up_and_is_measured_once_per_instant(db):
    t0, t1 = "2026-09-01 12:00:00+00", "2026-09-01 12:30:00+00"
    # no run, no session: the building draws 100 kW, the battery charges at 200 kW, the sun gives 50 kW
    assert _psql(db, f"select ottoq_power_capture('{TWIN}', NULL, '{t0}', 100, -200, 50)") == "8"   # 7 transformers + service
    assert _psql(db, f"select ottoq_power_capture('{TWIN}', NULL, '{t0}', 100, -200, 50)") == "0"   # the same instant again
    assert _psql(db, f"select ottoq_power_capture('{TWIN}', NULL, '{t1}', 100, -200, 50)") == "8"
    aux = json.loads(_psql(db, f"select to_jsonb(s) from ottoq_power_node_study s where sim_run_id = '{ZERO}' and node_code = 'TX-AUX'"))
    assert aux["ticks"] == 2 and float(aux["seconds_observed"]) == 1800
    assert float(aux["peak_kw_ac"]) == pytest.approx(250)                          # 100 + 200 - 50
    assert float(aux["energy_kwh_ac"]) == pytest.approx(125)                       # 250 kW for half an hour
    assert float(aux["peak_30min_kva"]) == pytest.approx(250 / 0.97, abs=0.01)
    assert float(aux["loss_kwh"]) > 0 and float(aux["max_hot_spot_c"]) > 22
    assert sum(float(x) for x in aux["load_seconds"]) == 1800 and float(aux["load_seconds"][1]) == 1800   # 10% of 2,500 kVA
    idle = json.loads(_psql(db, f"select to_jsonb(s) from ottoq_power_node_study s where sim_run_id = '{ZERO}' and node_code = 'TX-A1'"))
    assert float(idle["peak_kva"]) == 0 and float(idle["energy_kwh_dc"]) == 0
    assert float(idle["loss_kwh"]) == pytest.approx(2500 * 0.01 / 6 * 0.5, abs=1e-3)   # an idle unit still pays its core loss
    svc = json.loads(_psql(db, f"select to_jsonb(s) from ottoq_power_node_study s where sim_run_id = '{ZERO}' and node_code = 'SERVICE'"))
    assert float(svc["loss_kwh"]) == pytest.approx(sum(float(x) for x in _psql(
        db, f"select string_agg(loss_kwh::text, ',') from ottoq_power_node_study where sim_run_id = '{ZERO}' and kind = 'transformer'").split(",")), abs=1e-6)
    # posts carry a study row and no working row
    assert _psql(db, "select count(*) from ottoq_power_node_ticks t join ottoq_power_nodes n using (node_code) where n.kind = 'post'") == "0"
    assert _psql(db, f"select count(*) from ottoq_power_node_study where sim_run_id = '{ZERO}' and kind = 'post'") == "30"
    # and the read answers from it
    line = json.loads(_psql(db, f"select ottoq_power_one_line('{TWIN}', '{ZERO}')"))
    assert len(line["nodes"]) == 42 and line["as_of_sim"].startswith("2026-09-01T12:30")


def test_the_trip_door_refuses_what_it_should_and_only_the_server_may_call_it(db):
    r = json.loads(_psql(db, f"select ottoq_twin_trip_power_node('{uuid.uuid4()}', 'TX-A1', 60, 'test')"))
    assert r == {"ok": False, "reason": "run_not_found"}
    priv = lambda role, fn: _psql(db, f"select has_function_privilege('{role}', '{fn}', 'execute')")  # noqa: E731
    trip = "public.ottoq_twin_trip_power_node(uuid, text, numeric, text)"
    assert (priv("anon", trip), priv("authenticated", trip), priv("service_role", trip)) == ("f", "f", "t")
    read = "public.ottoq_power_one_line(uuid, uuid)"
    assert (priv("anon", read), priv("authenticated", read)) == ("t", "t")
    for fn in ("public.ottoq_power_capture(uuid, uuid, timestamptz, numeric, numeric, numeric)", "public.ottoq_power_rightsize(uuid)",
               "public.ottoq_power_resilience(uuid)"):
        assert (priv("anon", fn), priv("authenticated", fn)) == ("f", "f")
    # the tables are read-only to the client keys
    assert _psql(db, "select bool_or(has_table_privilege(r, t, 'insert, update, delete')) from unnest(array['anon','authenticated']) r, "
                     "unnest(array['ottoq_power_nodes','ottoq_power_node_ticks','ottoq_power_node_study','ottoq_power_node_trips']) t") == "f"


def test_the_registry_and_the_world_fingerprint_are_untouched(db):
    assert _psql(db, "select count(*) from ottoq_check_run_scope_registry() g where g::text like '%ottoq_power_node%'") == "0"
    classes = json.loads(_psql(db, "select jsonb_object_agg(table_name, class) from ottoq_run_scope_registry where table_name like 'ottoq_power_node%'"))
    assert classes == {"ottoq_power_node_ticks": "engine", "ottoq_power_node_study": "evidence", "ottoq_power_node_trips": "evidence"}
    assert _psql(db, f"select ottoq.ottoq_world_fingerprint_sections('{TWIN}')") == _psql(
        "ottoq_lab", f"select ottoq.ottoq_world_fingerprint_sections('{TWIN}')")


def test_0813_every_transformer_stands_on_the_site_and_solar_generation_is_unchanged(db):
    """0813: seven transformer structures named as the nodes are, canopy_4's 288 panels on the carports, same solar."""
    before = _psql(db, f"select sum(nameplate_dc_kw), count(*) from ottoq_canopy_state where depot_id = '{TWIN}'")
    m0813 = glob.glob(os.path.join(ROOT, "db", "migrations", "0813_*.sql"))[0]
    p = subprocess.run(["psql", *CONN, "-d", db, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", m0813],
                       capture_output=True, text=True)
    assert p.returncode == 0, p.stderr
    assert _psql(db, f"select sum(nameplate_dc_kw), count(*) from ottoq_canopy_state where depot_id = '{TWIN}'") == before
    assert _psql(db, f"""select count(*) from ottoq_power_nodes n left join ottoq_site_structures s
                           on s.depot_id = n.depot_id and s.structure_code = n.node_code
                          and s.structure_kind = 'transformer' and s.status = 'active'
                         where n.depot_id = '{TWIN}' and n.kind = 'transformer' and s.structure_id is null""") == "0"
    assert _psql(db, f"""select sum((properties->>'panel_count')::int) from ottoq_site_structures
                         where depot_id = '{TWIN}' and properties->>'solar_array' = 'canopy_4'""") == "288"
    # no transformer stands on another structure of its yard row, and the fence check still passes
    assert _psql(db, f"""select count(*) from ottoq_site_structures a join ottoq_site_structures b
                           on a.depot_id = b.depot_id and a.structure_code < b.structure_code
                         where a.depot_id = '{TWIN}' and a.structure_kind = 'transformer' and b.structure_kind = 'transformer'
                           and a.origin_x_ft < b.origin_x_ft + b.width_ft and b.origin_x_ft < a.origin_x_ft + a.width_ft
                           and a.origin_y_ft < b.origin_y_ft + b.length_ft and b.origin_y_ft < a.origin_y_ft + a.length_ft""") == "0"
    assert json.loads(_psql(db, f"select ottoq_check_fence_containment('{TWIN}')"))["passed"] is True
