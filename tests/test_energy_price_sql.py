"""db/migrations/0574, EXECUTED: the twin depot's price of power is Nashville's published time-of-use rate.

WHY THIS EXISTS. 0574 replaces the prices OTTO-Q's battery and forward plan read every tick. Its claims are what the
reader returns at given moments, so they are executed here against the live reader's own source, carried byte for byte
in tests/fixtures/energy_price_stub.sql. Before, the unsourced table's $0.235 "super peak" and the $0.10 fallback it
left in spring afternoons; after, NES Schedule TGSA Part 3 plus the September fuel adjustment. Only the twin changes.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_charge_calibration_sql.py.
"""
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "energy_price_stub.sql")
M0574 = os.path.join(ROOT, "db", "migrations", "0574_the_twin_prices_power_at_nashvilles_published_rate.sql")
TWIN = "11111111-1111-1111-1111-111111111111"
OTHER = "22222222-2222-2222-2222-222222222222"


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
    name = f"ottoq_nes_{os.getpid()}_{uuid.uuid4().hex[:6]}"
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
    rc, err = d.file(M0574)
    assert rc == 0, f"0574 did not apply: {err}"


def _price(d, depot, at):
    return d.val(f"SELECT format('%s %s', out_label, out_rate_usd_kwh) FROM twin.ottoq_sim_current_tariff('{depot}', '{at}')")


MOMENTS = ["2026-09-01 14:30:00-05", "2026-09-01 17:30:00-05", "2026-09-01 03:00:00-05", "2026-01-13 05:00:00-06",
           "2026-04-14 15:00:00-05"]


def test_the_stub_carries_the_live_reader_byte_for_byte(db):
    assert db.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_sim_current_tariff'") \
        == "8f93e635552b6be131f7e54e8eb1f54b"


def test_the_twin_is_priced_at_the_published_rate(db):
    assert [_price(db, TWIN, m) for m in MOMENTS] == \
        ["peak 0.158", "super_peak 0.235", "off_peak 0.052", "off_peak 0.052", "unknown 0.10"]  # before: no source
    _apply(db)
    assert [_price(db, TWIN, m) for m in MOMENTS] == \
        ["on_peak 0.08182", "on_peak 0.08182", "off_peak 0.06724", "on_peak 0.07719", "mid_peak 0.07187"]


def test_every_label_is_a_value_the_snapshot_can_store(db):
    _apply(db)
    db.val(f"SELECT label::public.tariff_label FROM ottoq_tariff_windows WHERE depot_id = '{TWIN}' AND active")


def test_no_other_depot_is_touched(db):
    before = [_price(db, OTHER, m) for m in MOMENTS]
    _apply(db)
    assert [_price(db, OTHER, m) for m in MOMENTS] == before
    assert db.val(f"SELECT count(*) FILTER (WHERE active) || '/' || count(*) FROM ottoq_tariff_windows WHERE depot_id = '{OTHER}'") \
        == "6/6"


def test_it_records_itself_and_the_old_windows(db):
    _apply(db)
    assert db.val("SELECT format('%s/%s', forces_recert, forces_dial_restart) FROM ottoq_cert_lineage") == "t/t"
    assert db.val("SELECT jsonb_array_length(definition::jsonb) FROM ottoq_schema_snapshots WHERE label = '0574_pre'") == "6"


def test_the_rollback_in_the_header_restores_the_old_prices(db):
    before = [_price(db, TWIN, m) for m in MOMENTS]
    _apply(db)
    db.val(f"""DELETE FROM public.ottoq_tariff_windows WHERE depot_id = '{TWIN}' AND active;
               UPDATE public.ottoq_tariff_windows SET active = true
                WHERE tariff_id IN (SELECT (e->>'tariff_id')::uuid FROM public.ottoq_schema_snapshots s,
                                           jsonb_array_elements(s.definition::jsonb) e WHERE s.label = '0574_pre')""")
    assert [_price(db, TWIN, m) for m in MOMENTS] == before


@pytest.mark.parametrize("setup, message", [
    ("CREATE OR REPLACE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false) "
     "RETURNS integer LANGUAGE sql AS $$ SELECT 1 $$", "0574 P0"),
    (f"INSERT INTO ottoq_sim_runs(depot_id, status) VALUES ('{TWIN}', 'running')", "0574 P1"),
    (f"UPDATE ottoq_tariff_windows SET rate_usd_per_kwh = 0.25 WHERE depot_id = '{TWIN}' AND label = 'super_peak'",
     "0574 P2"),
    ("CREATE OR REPLACE FUNCTION twin.ottoq_sim_current_tariff(p_depot_id uuid, p_sim_clock_now timestamptz) "
     "RETURNS TABLE(out_label text, out_rate_usd_kwh numeric) LANGUAGE sql AS $$ SELECT 'x'::text, 0.1::numeric $$",
     "0574 P2"),
])
def test_it_refuses_what_it_cannot_do_safely(db, setup, message):
    db.val(setup)
    rc, err = db.file(M0574)
    assert rc != 0 and message in err, err
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage") == "0"
    assert db.val(f"SELECT count(*) FROM ottoq_tariff_windows WHERE depot_id = '{TWIN}' AND active") == "6"


def test_it_applies_once(db):
    _apply(db)
    rc, err = db.file(M0574)
    assert rc != 0 and ("0574 P2" in err or "0574 P3" in err), err
