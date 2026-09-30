"""db/migrations/0573, EXECUTED: every charge and service in the twin takes the time public data says it takes.

WHY THIS EXISTS. 0573 replaces the fast-charge curve every charge in the twin runs on, corrects two vehicle groups'
battery facts, and moves one service time. Its claims are numbers (docs/research/direct/
2026-09-30-lane-a-service-time-calibration.md, reproduced by the fit script beside it), so they are executed here
against the live functions' own source, carried byte for byte in tests/fixtures/charge_calibration_stub.sql:
  - the calibrated minutes, exactly as V1 pins them, and as the fit script prints them;
  - what did not change: every L2 charge, and a DC charge with no battery size, is what it was;
  - each battery is recognised by the two numbers every caller passes, and a car's own maximum still caps it;
  - the facts change for the twin's and the Benchmark's I-PACE and Zoox cars, and for no other car;
  - sensor calibration takes 60 minutes, floor 30;
  - the refusals, and the rollback the header describes.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_charge_batch_order_sql.py.
"""
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "charge_calibration_stub.sql")
M0573 = os.path.join(ROOT, "db", "migrations", "0573_every_charge_and_service_takes_the_time_public_data_says.sql")
TWIN = "11111111-1111-1111-1111-111111111111"
BENCH = "22222222-2222-2222-2222-222222222222"


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
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        yield d
    finally:
        subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _apply(d):
    rc, err = d.file(M0573)
    assert rc == 0, f"0573 did not apply: {err}"


def _minutes(d, s0, s1, vmax, kwh, charger=350):
    vmax_sql = "NULL" if vmax is None else str(vmax)
    return float(d.val(f"SELECT public.ottoq_estimate_charge_minutes({s0}, {s1}, {charger}, {vmax_sql}, {kwh}, 25, 100, 1)"))


def test_the_stub_carries_the_live_rate_function_byte_for_byte(db):
    # 0573 P2 pins this md5; a stub that drifted from live would test something else
    assert db.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_sim_compute_charge_rate'") \
        == "20f2d98f41e34238497a5d28304e7004"


def test_the_calibrated_minutes_are_the_documented_ones(db):
    before = {k: _minutes(db, 20, 100, v, e) for k, v, e in (("y", 250, 75), ("ipace", 100, 75), ("zoox", 200, 135))}
    assert before == {"y": 46.0, "ipace": 115.0, "zoox": 103.5}  # the doc's "twin today", 2.2
    _apply(db)
    got = {(k, a, b): _minutes(db, a, b, v, e)
           for k, v, e in (("y", 250, 75), ("ipace", 104, 84.7), ("zoox", 100, 133))
           for a, b in ((10, 80), (80, 100), (20, 100))}
    assert got == {("y", 10, 80): 29.2, ("y", 80, 100): 27.3, ("y", 20, 100): 54.2,
                   ("ipace", 10, 80): 45.1, ("ipace", 80, 100): 49.4, ("ipace", 20, 100): 89.5,
                   ("zoox", 10, 80): 55.9, ("zoox", 80, 100): 21.3, ("zoox", 20, 100): 69.2}


def test_l2_and_sizeless_dc_charges_are_unchanged(db):
    grid = """
      SELECT string_agg(public.ottoq_sim_compute_charge_rate(s, t, t, c, v, k, 95, 7, 'g')::text, ',' ORDER BY s, t, c, v, k)
        FROM generate_series(0, 100, 5) s, (VALUES (-5::numeric), (12), (25), (40)) tt(t),
             (VALUES (7.2::numeric, 7.4::numeric, 84.7::numeric), (11, 11, 75), (19.2, 11, 133), (22, NULL, 75),
                     (350, 104, NULL), (350, 250, 0), (150, NULL, NULL)) cc(c, v, k)"""
    before = db.val(grid)
    _apply(db)
    assert db.val(grid) == before


def test_a_battery_is_recognised_by_its_maximum_and_size_and_the_car_still_caps_it(db):
    _apply(db)
    rate = lambda soc, vmax, kwh, charger=350: float(db.val(
        f"SELECT public.ottoq_sim_compute_charge_rate({soc}, 25, 25, {charger}, {vmax}, {kwh}, 100, 0, 'x')"))
    noise = lambda soc: float(db.val(f"SELECT 0.97 + twin.ottoq_sim_seeded_random(0, 'x:{soc}') * 0.06"))
    # Model Y at 50%: 75 kWh x 1.404 kW/kWh, its measured curve
    assert rate(50, 250, 75) == round(75 * 1.404 * noise(50), 3)
    # the same battery with another maximum is not a Model Y: the typical curve (1.543 at 50%)
    assert rate(50, 249, 75) == round(75 * 1.543 * noise(50), 3)
    # I-PACE below 50%: the car's own 104 kW binds, not its acceptance
    assert rate(30, 104, 84.7) == round(104 * noise(30), 3)
    # a 100 kW charger caps a Model Y at low charge
    assert rate(10, 250, 75, charger=100) == round(100 * noise(10), 3)
    # no car maximum (a Cybercab): the charger and the typical curve, 75 x 1.543 at 50%
    assert rate(50, "NULL", 75) == round(75 * 1.543 * noise(50), 3)
    # above 100% or below 0% reads the ends of the table
    assert rate(120, 250, 75) == round(75 * 0.219 * noise(120), 3)
    assert rate(-3, 104, 84.7) == round(104 * noise(-3), 3)


def test_only_the_twin_and_benchmark_ipace_and_zoox_cars_change(db):
    q = """SELECT string_agg(format('%s/%s/%s/%s/%s/%s', left(home_depot_id::text, 4), category, make, model,
                                    battery_capacity_kwh, COALESCE(inlet_max_kw::text, '-')), ';')
             FROM (SELECT DISTINCT home_depot_id, category, make, model, battery_capacity_kwh, inlet_max_kw FROM vehicles) v"""
    before = set(db.val(q).split(";"))
    _apply(db)
    after = set(db.val(q).split(";"))
    changed_to = after - before
    assert changed_to == {"1111/autonomous/Waymo/I-Pace/84.70/104.0", "1111/autonomous/Jaguar/I-PACE AV/84.70/104.0",
                          "2222/autonomous/Waymo/I-Pace/84.70/104.0", "2222/autonomous/Jaguar/I-PACE AV/84.70/104.0",
                          "1111/autonomous/Zoox/Robotaxi/133.00/100.0", "1111/autonomous/Zoox/VH6/133.00/100.0",
                          "2222/autonomous/Zoox/Robotaxi/133.00/100.0"}
    # untouched: the retail Zoox at the twin, the third depot's I-Paces, every Tesla and Zeekr
    assert {"1111/retail/Zoox/Robotaxi/135.00/200.0", "3333/autonomous/Waymo/I-Pace/75.00/100.0",
            "1111/autonomous/Tesla/Model Y/75.00/250.0", "2222/autonomous/Zeekr/RT AV/100.00/-"} <= after
    assert db.val("SELECT string_agg(format('%s=%s/%s', vehicle_class_code, battery_capacity_kwh, max_charge_rate_kw), ',' "
                  "ORDER BY vehicle_class_code) FROM ottoq_vehicle_classes") \
        == "tesla_model_y_robotaxi_2024=75/250,waymo_jaguar_ipace_2024=84.7/104,zoox_robotaxi_2024=133/100"


def test_sensor_calibration_takes_sixty_minutes_with_a_thirty_minute_floor(db):
    calib = lambda obs: db.val(f"SELECT ottoq.ottoq_derive_visit_needs(NULL, NULL, NULL, NULL, NULL, '{obs}')->>'calib_min'")
    assert (calib("{}"), calib('{"svcspd": 0.3}')) == ("30", "18")
    _apply(db)
    assert (calib("{}"), calib('{"svcspd": 0.3}'), calib('{"svcspd": 1.5}')) == ("60", "30", "90")
    assert db.val("SELECT est_min_default FROM service_cadence_policy WHERE svc = 'sensor_calibration'") == "60"
    assert db.val("SELECT est_min_default FROM service_cadence_policy WHERE svc = 'exterior_wash'") == "10"


def test_it_records_itself_and_its_pre_images(db):
    _apply(db)
    assert db.val("SELECT format('%s/%s', forces_recert, forces_dial_restart) FROM ottoq_cert_lineage") == "t/t"
    assert db.val("SELECT string_agg(object_kind || ':' || object_name, ',' ORDER BY object_kind, object_name) FROM ottoq_schema_snapshots "
                  "WHERE label = '0573_pre'") \
        == "function:ottoq_derive_visit_needs,function:ottoq_sim_compute_charge_rate," \
           "table_row:ottoq_vehicle_classes,table_row:vehicles"
    assert db.val("SELECT jsonb_array_length(definition::jsonb) FROM ottoq_schema_snapshots "
                  "WHERE label = '0573_pre' AND object_name = 'vehicles'") == "147"


def test_the_rollback_in_the_header_restores_everything(db):
    fingerprint = """SELECT md5(string_agg(x, '|' ORDER BY x)) FROM (
        SELECT md5(prosrc) x FROM pg_proc WHERE proname IN ('ottoq_sim_compute_charge_rate', 'ottoq_derive_visit_needs')
        UNION ALL SELECT format('%s/%s/%s', id, battery_capacity_kwh, inlet_max_kw) FROM vehicles
        UNION ALL SELECT format('%s/%s/%s', vehicle_class_code, battery_capacity_kwh, max_charge_rate_kw) FROM ottoq_vehicle_classes
        UNION ALL SELECT format('%s/%s', svc, est_min_default) FROM service_cadence_policy) s"""
    before = db.val(fingerprint)
    _apply(db)
    assert db.val(fingerprint) != before
    db.val("""DO $rb$
      DECLARE r record;
      BEGIN
        FOR r IN SELECT definition FROM ottoq_schema_snapshots WHERE label = '0573_pre' AND object_kind = 'function' LOOP
          EXECUTE r.definition;
        END LOOP;
        UPDATE vehicles v SET battery_capacity_kwh = (e->>'battery_capacity_kwh')::numeric,
                              inlet_max_kw = (e->>'inlet_max_kw')::numeric
          FROM ottoq_schema_snapshots s, jsonb_array_elements(s.definition::jsonb) e
         WHERE s.label = '0573_pre' AND s.object_name = 'vehicles' AND v.id = (e->>'id')::uuid;
        UPDATE ottoq_vehicle_classes c SET battery_capacity_kwh = (e->>'battery_capacity_kwh')::numeric,
                                           max_charge_rate_kw = (e->>'max_charge_rate_kw')::numeric
          FROM ottoq_schema_snapshots s, jsonb_array_elements(s.definition::jsonb) e
         WHERE s.label = '0573_pre' AND s.object_name = 'ottoq_vehicle_classes'
           AND c.vehicle_class_code = e->>'vehicle_class_code';
        UPDATE service_cadence_policy SET est_min_default = 30 WHERE svc = 'sensor_calibration';
      END $rb$""")
    assert db.val(fingerprint) == before


@pytest.mark.parametrize("setup, message", [
    ("SELECT set_config('stub.in_flight', '1', false)", None),  # session GUC is per psql call: handled below
    (f"INSERT INTO ottoq_sim_runs(depot_id, status) VALUES ('{TWIN}', 'running')", "0573 P1"),
    (f"INSERT INTO ottoq_sim_runs(depot_id, status) VALUES ('{BENCH}', 'paused')", "0573 P1"),
    ("INSERT INTO ottoq_site_buildout_active VALUES ('dcfc20')", "0573 P1"),
    ("CREATE TABLE ottoq_fleet_buildout_active (fleet_code text); INSERT INTO ottoq_fleet_buildout_active VALUES ('fleet150')",
     "0573 P1"),
    ("CREATE OR REPLACE FUNCTION ottoq.ottoq_derive_visit_needs(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, "
     "p_clock timestamptz, p_depot_id uuid, p_obs jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$",
     "0573 P2"),
    (f"DELETE FROM vehicles WHERE id = (SELECT id FROM vehicles WHERE make = 'Zoox' AND home_depot_id = '{BENCH}' LIMIT 1)",
     "0573 P2"),
    ("UPDATE service_cadence_policy SET est_min_default = 45 WHERE svc = 'sensor_calibration'", "0573 P2"),
])
def test_it_refuses_what_it_cannot_do_safely(db, setup, message):
    if message is None:
        # the in-flight probe: a stub that reports one pair running
        db.val("CREATE OR REPLACE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false) "
               "RETURNS integer LANGUAGE sql AS $$ SELECT 1 $$")
        message = "0573 P0"
    else:
        db.val(setup)
    rc, err = db.file(M0573)
    assert rc != 0 and message in err, err
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage") == "0"
    assert db.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_sim_compute_charge_rate'") \
        == "20f2d98f41e34238497a5d28304e7004"


def test_it_applies_once(db):
    _apply(db)
    rc, err = db.file(M0573)
    # the rate function is no longer the one measured (P2) before the lineage check (P3) is reached
    assert rc != 0 and ("0573 P2" in err or "0573 P3" in err), err
