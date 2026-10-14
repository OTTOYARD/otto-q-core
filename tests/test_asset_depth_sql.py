"""db/migrations/0717, EXECUTED: the agent's board calls a car's 80% a priority band, not a ready floor (G434, rule 9).

WHY THIS EXISTS. ottoq_agent_asset_depth told the agent "soc 49% below ready floor 80%", a number that is neither the
car's target (100% unless its owner set less) nor the departure gate, and the agent repeated it as a charge target in
114 distinct directives. Executed here on the live definition (md5 70f53e41...):
  - the attention reason now says the car is in the priority band and charges to its owner's target;
  - who is on the attention list, in what order and with what score, does not change.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "asset_depth_stub.sql")
M0717 = os.path.join(ROOT, "db", "migrations", "0717_the_board_calls_eighty_percent_a_priority_band_not_a_floor.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "0717aaaa-0000-0000-0000-000000000001"
CLOCK = "2026-10-13 16:00:00+00"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_ad_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        for i, (name_, soc, ready, deploy_min, dcfc_safe) in enumerate([
                ("Waymo-AV-030", 49, 80, -170, False), ("Zoox-AV-075", 49, 80, -35, True),
                ("Tesla-AV-062", 85, 80, 20, True), ("Waymo-AV-037", 78, 80, 138, True)]):
            vid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0717-{name_}"))
            d.val(f"""INSERT INTO public.vehicles (id, display_name, current_state, current_soc, home_depot_id)
                      VALUES ('{vid}', '{name_}', 'arrived_at_gate', {soc}, '{DEPOT}')""")
            d.val(f"""INSERT INTO public.vehicle_need_profile (vehicle_id, min_ready_soc_pct, dcfc_safe, worst_fault_severity,
                                                                next_deploy_at, priority_class)
                      VALUES ('{vid}', {ready}, {str(dcfc_safe).lower()}, 99,
                              '{CLOCK}'::timestamptz + interval '{deploy_min} minutes', 'standard')""")
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _attention(d):
    return d.json(f"""SELECT public.ottoq_agent_asset_depth('{RUN}', '{DEPOT}', '{CLOCK}') -> 'assets' -> 'attention'""")


def test_0717_the_reason_names_the_band_and_the_target_and_nothing_else_moves(db):
    before = _attention(db)
    assert any("below ready floor 80%" in w for a in before for w in a["why"]), before
    rc, err = db.file(M0717)
    assert rc == 0 and "0717 V1-V2 PASSED" in err, err
    after = _attention(db)
    assert [(a["asset"], a["soc"], a["mins_to_deploy"]) for a in after] == \
           [(a["asset"], a["soc"], a["mins_to_deploy"]) for a in before], "the list or its order moved"
    whys = [w for a in after for w in a["why"]]
    assert not any("ready floor" in w for w in whys), whys
    assert "soc 49%, in the priority band under 80% (charges to its owner's target, not to 80%)" in whys, whys
    # the soc block keeps its field and its count
    soc = db.json(f"SELECT public.ottoq_agent_asset_depth('{RUN}', '{DEPOT}', '{CLOCK}') -> 'assets' -> 'soc'")
    assert soc["below_min_ready"] == 3, soc


def test_0717_refuses_a_definition_it_was_not_written_against(db):
    rc, err = db.file(M0717)
    assert rc == 0, err
    rc, err = db.file(M0717)
    assert rc != 0 and "0717 P1" in err, err
