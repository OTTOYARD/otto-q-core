"""db/migrations/0600 and 0601, EXECUTED: the battery stops charging itself into the half hour NES bills.

WHY THIS EXISTS. 0600 patches the battery's day plan (`ottoq_bess_day_plan`) and 0601 the EV queue forecast it reads
(`ottoq_forecast_ev_queue_kw`). Both are spliced into the live text, so both are executed here against the live bodies
carried byte for byte in tests/fixtures/bess_half_hour_stub.sql (each body's md5 is asserted below), with the smoke arm's
own samples (88e46ad3, busy_day, 11:05-12:00 UTC) and the forecast its plan logged at 11:25.

What is pinned:
  * before 0600 the live plan reproduces the smoke arm: at 11:25 it refilled the DR reserve at 118 kW (live: 118.1)
    under a "billed peak" of 2,415.1 kW, the highest single sample;
  * after 0600 the billed peak is the highest completed 30-minute average (1,960.8 kW at 12:05, the sweep scorer's own
    figure for that arm), the refill waits for the lowest-load half hours before the DR window and still fits the
    shortfall in them, it hurries as the window nears, and no grid charge lifts its half hour above the cap;
  * a charge for any other reason is unchanged when the half hour has room, and a solar-surplus charge is unchanged;
  * after 0601 a car near full is forecast at the power its battery takes, no job's forecast rate rises, the energy
    forecast is conserved, and the scheduler is untouched;
  * both refuse while anything is in flight, on a function that is not the one measured, and a second time; both roll
    back to the byte.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_throughput_sweep_sql.py.
"""
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "bess_half_hour_stub.sql")
M0600 = os.path.join(ROOT, "db", "migrations", "0600_the_battery_never_charges_itself_into_the_billed_half_hour.sql")
M0601 = os.path.join(ROOT, "db", "migrations",
                     "0601_the_battery_forecast_charges_a_waiting_car_at_the_rate_its_battery_accepts.sql")
M0573 = os.path.join(ROOT, "db", "migrations", "0573_every_charge_and_service_takes_the_time_public_data_says.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "88e46ad3-8ed5-4609-892a-38298e19dfca"
PLAN_MD5 = "8f136624ad07b64a3ef3022b3bab0753"
QUEUE_MD5 = "ff2cfc482ce702e664b24ed514435569"


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


# The smoke arm's site at 11:05-12:00 UTC (6:05-7:00 AM CDT), from its own rows: the battery as the twin has it (3,000 kWh,
# 1,500 kW, 10-95%, round trip 0.96) at the 23.94% it held at 11:25; NES's summer demand rate; and the samples
# site_energy_snapshots holds for 88e46ad3, grid draw and the sample maximum the site-energy step kept.
SEED = f"""
INSERT INTO public.depots VALUES ('{DEPOT}', 36.1397, -86.7728);
ALTER TABLE public.ottoq_sim_runs ADD COLUMN sim_clock_start timestamptz, ADD COLUMN started_at timestamptz;
INSERT INTO public.ottoq_sim_runs VALUES ('{RUN}', '{DEPOT}', '2026-09-01 11:00+00', '2026-09-29 20:02+00');
INSERT INTO public.ottoq_bess_units (depot_id, capacity_kwh, current_soc_pct, soc_min_floor_pct, soc_max_ceiling_pct,
                                     max_discharge_kw, max_charge_kw, roundtrip_efficiency_pct)
VALUES ('{DEPOT}', 3000, 23.94, 10, 95, 1500, 1500, 0.96);
INSERT INTO public.ottoq_depot_tariffs (depot_id, season, season_months, demand_first_block_usd_kw)
VALUES ('{DEPOT}', 'summer', '{{6,7,8,9}}', 21.40);
INSERT INTO public.ottoq_tariff_windows VALUES ('{DEPOT}', true, 'all', 0.08);
INSERT INTO public.site_energy_snapshots (depot_id, sim_run_id, "timestamp", grid_import_kw, building_load_kw,
                                          lighting_load_kw, solar_generation_kw, total_ev_charging_kw, billing_period_peak_kw)
SELECT '{DEPOT}', '{RUN}', t, g, b, 0, 0, ev, pk
  FROM unnest('{{2026-09-01 11:05+00,2026-09-01 11:10+00,2026-09-01 11:15+00,2026-09-01 11:20+00,2026-09-01 11:25+00,
                 2026-09-01 11:30+00,2026-09-01 11:35+00,2026-09-01 11:40+00,2026-09-01 11:45+00,2026-09-01 11:50+00,
                 2026-09-01 11:55+00,2026-09-01 12:00+00}}'::timestamptz[],
              '{{990.9,2415.1,2404.9,1937.4,1722.3,1742.4,1542.8,1495.9,1588.0,1541.8,1493.8,1577.0}}'::numeric[],
              '{{39.5,46.1,44.6,49.9,47.4,39.9,46.1,52.1,45,45,45,95}}'::numeric[],
              '{{0,2369.0,2360.3,1887.5,1556.8,1417.8,1138.8,953.5,1002,910,814,980}}'::numeric[],
              '{{990.9,2415.1,2415.1,2415.1,2415.1,2415.1,2415.1,2415.1,2415.1,2415.1,2415.1,2415.1}}'::numeric[])
       AS u(t, g, b, ev, pk);
-- the forecast the plan logged at 11:25 (ottoq_energy_plan.forecast_load_kw of 88e46ad3), carried as known EV load
INSERT INTO public.stub_known_kw
SELECT o, x FROM unnest('{{1937,2131,1683,1646,1598,1565,1586,1559,1530,1510,1486,1475,1484,1482,1471,1479,1489}}'::numeric[])
                 WITH ORDINALITY AS u(x, o);
"""


def _plan(d, clock, net):
    return d.json(f"SELECT public.ottoq_bess_day_plan('{RUN}', '{DEPOT}', '{clock}', {net})")


def _make_db(tag):
    name = f"ottoq_{tag}_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    rc, err = d.file(STUB)
    assert rc == 0, f"stub did not load: {err}"
    d.val(SEED)
    return d


def _drop(d):
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q"]
    subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {d.name} WITH (FORCE)"], capture_output=True)


@pytest.fixture()
def db():
    d = _make_db("bhh")
    try:
        yield d
    finally:
        _drop(d)


def _md5(d, sig):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = '{sig}'::regprocedure")


PLAN_SIG = "public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)"
QUEUE_SIG = "public.ottoq_forecast_ev_queue_kw(uuid,uuid,timestamp with time zone,integer,numeric)"


def test_the_stub_carries_the_live_bodies(db):
    assert _md5(db, PLAN_SIG) == PLAN_MD5
    assert _md5(db, QUEUE_SIG) == QUEUE_MD5
    assert _md5(db, "public.ottoq_bess_plan_eval(numeric,numeric[],numeric[],numeric[],numeric,numeric,numeric,numeric,"
                    "numeric,numeric,numeric)") == "28c8e1aa2e86922861695f95d22a424e"
    assert _md5(db, "public.ottoq_ev_queue_schedule(numeric[],numeric[],numeric[],numeric[],numeric[],numeric,integer)") \
        == "bb2a1dce2e7d984bb8707dea1873d137"
    assert _md5(db, "public.ottoq_sim_compute_charge_rate(numeric,numeric,numeric,numeric,numeric,numeric,numeric,bigint,"
                    "text)") == "20f2d98f41e34238497a5d28304e7004"


def test_before_0600_the_plan_refills_into_the_surge_half_hour_under_the_sample_peak(db):
    p = _plan(db, "2026-09-01 11:25+00", 1937)
    # the smoke arm's own tick: 118.1 kW commanded at 11:25 under restore_dr_reserve, level 2,415.1 kW
    assert p["charge_reason"] == "restore_dr_reserve" and abs(p["charge_now_kw"] - 118.1) < 1
    assert p["ratchet_kw"] == 2415.1 and p["level_kw"] == 2415.1


def test_after_0600_the_billed_peak_is_the_completed_half_hour(db):
    rc, err = db.file(M0600)
    assert rc == 0, err
    p = _plan(db, "2026-09-01 11:25+00", 1937)
    assert p["ratchet_kw"] == 0 and p["ratchet_sample_kw"] == 2415.1        # no half hour has closed yet
    p = _plan(db, "2026-09-01 12:05+00", 700)
    # the 11:10-11:40 half hour: the smoke arm's scored peak_30min_kw, to the tenth
    assert p["ratchet_kw"] == 1960.8 and p["ratchet_sample_kw"] == 2415.1


def test_a_test_day_that_bills_from_an_hour_in_can_plan_that_way(db):
    rc, err = db.file(M0600)
    assert rc == 0, err
    assert db.val("SELECT default_value FROM public.ottoq_policy_param_catalog WHERE param_key = 'bess_plan_bill_from_min'") \
        == "0"
    db.val(f"INSERT INTO public.ottoq_policy_params VALUES ('run', '{RUN}', 'bess_plan_bill_from_min', 30)")
    # windows from 11:30: 11:30-12:00 (1,567.5 kW) and 11:35-12:05 (1,539.9) have closed by 12:05; the opening has not
    assert _plan(db, "2026-09-01 12:05+00", 700)["ratchet_kw"] == 1567.5
    db.val(f"UPDATE public.ottoq_policy_params SET param_value = 60 WHERE scope_id = '{RUN}'")
    assert _plan(db, "2026-09-01 12:05+00", 700)["ratchet_kw"] == 0


def test_after_0600_the_refill_waits_for_the_valley_and_still_fits(db):
    rc, err = db.file(M0600)
    assert rc == 0, err
    p = _plan(db, "2026-09-01 11:25+00", 1937)
    assert p["mode"] == "reserve_protected" and p["charge_now_kw"] == 0
    fill = p["refill_level_kw"]
    net = p["forecast"]["net_kw"]
    # 6:25 AM CDT: the steps before the 2 PM DR window are the first 16 (6:25 ... 1:55)
    need = (p["reserve_now_kwh"] - p["e_avail_kwh"]) / 0.96
    placed = sum(min(1500, max(0, fill - x)) * 0.5 for x in net[:16])
    assert fill < net[0] and placed >= need - 5, (fill, need, placed)


def test_after_0600_the_refill_hurries_as_the_window_nears(db):
    rc, err = db.file(M0600)
    assert rc == 0, err
    # 1:30 PM CDT, one step before the DR window: the whole shortfall has to go in now
    db.val(f"""INSERT INTO public.site_energy_snapshots (depot_id, sim_run_id, "timestamp", grid_import_kw, building_load_kw,
                 lighting_load_kw, solar_generation_kw, total_ev_charging_kw, billing_period_peak_kw)
               SELECT '{DEPOT}', '{RUN}', t, 900, 50, 0, 0, 850, 2415.1
                 FROM generate_series('2026-09-01 18:00+00'::timestamptz, '2026-09-01 18:25+00', interval '5 minutes') t""")
    p = _plan(db, "2026-09-01 18:30+00", 900)
    assert p["charge_reason"] == "restore_dr_reserve" and p["charge_now_kw"] > 400
    assert p["refill_level_kw"] >= 900 + p["charge_now_kw"] - 1


def test_after_0600_no_grid_charge_lifts_its_half_hour_over_the_cap(db):
    rc, err = db.file(M0600)
    assert rc == 0, err
    for clock, net in (("2026-09-01 11:45+00", 1000), ("2026-09-01 12:05+00", 700), ("2026-09-01 12:05+00", 300)):
        p = _plan(db, clock, net)
        if p["charge_now_kw"] <= 0:
            continue
        rows = db.json(f"""SELECT jsonb_build_array(count(*), COALESCE(sum(grid_import_kw), 0))
                             FROM public.site_energy_snapshots WHERE sim_run_id = '{RUN}'
                              AND "timestamp" > '{clock}'::timestamptz - interval '30 minutes' AND "timestamp" < '{clock}'""")
        avg = (float(rows[1]) + net + p["charge_now_kw"]) / (rows[0] + 1)
        assert avg <= p["half_hour_cap_kw"] + 0.1, (clock, net, p["charge_now_kw"], avg, p["half_hour_cap_kw"])


def _quiet_site(d, soc):
    """A quiet night: the battery above its reserve, 100 kW of load, no forecast load."""
    d.val(f"""UPDATE public.ottoq_bess_units SET current_soc_pct = {soc};
              UPDATE public.ottoq_sim_runs SET sim_clock_start = '2026-09-01 05:00+00';
              DELETE FROM public.stub_known_kw;
              DELETE FROM public.site_energy_snapshots;
              INSERT INTO public.site_energy_snapshots (depot_id, sim_run_id, "timestamp", grid_import_kw, building_load_kw,
                     lighting_load_kw, solar_generation_kw, total_ev_charging_kw, billing_period_peak_kw)
              SELECT '{DEPOT}', '{RUN}', t, 100, 100, 0, 0, 0, 100
                FROM generate_series('2026-09-01 05:00+00'::timestamptz, '2026-09-01 05:55+00', interval '5 minutes') t""")


def test_a_charge_for_another_reason_is_unchanged_when_its_half_hour_has_room(db):
    _quiet_site(db, 60)
    # an afternoon peak ahead (steps 24-30), so the level sits above tonight's load and the cheap window has headroom
    db.val("INSERT INTO public.stub_known_kw SELECT k, 900 FROM generate_series(24, 30) k")
    before = _plan(db, "2026-09-01 06:00+00", 100)
    rc, err = db.file(M0600)
    assert rc == 0, err
    after = _plan(db, "2026-09-01 06:00+00", 100)
    assert before["charge_reason"] == after["charge_reason"] == "cheapest_window"
    assert before["charge_now_kw"] == after["charge_now_kw"] > 0


def test_a_solar_surplus_charge_is_unchanged(db):
    _quiet_site(db, 60)
    db.val("""UPDATE public.site_energy_snapshots SET solar_generation_kw = 400, building_load_kw = 60, grid_import_kw = 0
               WHERE "timestamp" = '2026-09-01 05:55+00'""")
    before = _plan(db, "2026-09-01 06:00+00", 0)
    rc, err = db.file(M0600)
    assert rc == 0, err
    after = _plan(db, "2026-09-01 06:00+00", 0)
    assert before["charge_reason"] == after["charge_reason"] == "solar_surplus"
    assert before["charge_now_kw"] == after["charge_now_kw"] == 340


def test_0600_refuses_in_flight_on_another_plan_and_twice_and_rolls_back(db):
    db.val("UPDATE public.stub_in_flight SET n = 1")
    rc, err = db.file(M0600)
    assert rc != 0 and "0600 P0" in err
    db.val("UPDATE public.stub_in_flight SET n = 0")
    rc, err = db.file(M0600)
    assert rc == 0, err
    rc, err = db.file(M0600)
    assert rc != 0 and "0600 P1: already applied" in err
    db.val("""DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0600_pre'
                AND object_name = 'ottoq_bess_day_plan' ORDER BY snapshot_id DESC LIMIT 1); END $$;
              DELETE FROM public.ottoq_cert_lineage
               WHERE name = '0600_the_battery_never_charges_itself_into_the_billed_half_hour'""")
    assert _md5(db, PLAN_SIG) == PLAN_MD5
    db.val(f"CREATE OR REPLACE FUNCTION {PLAN_SIG.replace('(uuid,uuid,timestamp with time zone,numeric)', '')}"
           "(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz, p_net_load_now_kw numeric DEFAULT NULL)"
           " RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$")
    rc, err = db.file(M0600)
    assert rc != 0 and "0600 P1: ottoq_bess_day_plan is not the function measured" in err


# ── 0601: the queue forecast ─────────────────────────────────────────────────────────────────────────────────────────

# The twin depot's chargers (10 fast at 350 kW, 30 L2 at 19.2 kW, all free) and a waiting fleet in its mix: I-PACE
# (90 kWh, 100 kW), Zoox (135 kWh, 200 kW), Model Y (75 kWh, 250 kW).
FLEET = f"""
INSERT INTO public.ottoq_ocpp_chargers (charger_id, max_kw)
SELECT ('c0000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, CASE WHEN g <= 10 THEN 350 ELSE 19.2 END
  FROM generate_series(1, 40) g;
INSERT INTO public.stalls
SELECT ('a0000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, '{DEPOT}',
       ('c0000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, CASE WHEN g <= 10 THEN 350 ELSE 19.2 END
  FROM generate_series(1, 40) g;
"""


def _car(i, soc, cls):
    kwh, kw = {"ipace": (90, 100), "zoox": (135, 200), "mody": (75, 250)}[cls]
    return (f"INSERT INTO public.vehicles VALUES ('b0000000-0000-0000-0000-{i:012d}', '{DEPOT}', "
            f"'staged_awaiting_service', {soc}, 100, {kwh}, {kw})")


def _queue(d, steps=16):
    return d.json(f"""SELECT jsonb_build_object('load', to_jsonb(load_kw), 'pending', pending_n)
                        FROM public.ottoq_forecast_ev_queue_kw('{RUN}', '{DEPOT}', '2026-09-01 11:25+00', {steps}, 30)""")


def test_after_0601_a_car_near_full_is_forecast_at_what_its_battery_takes(db):
    db.val(FLEET)
    for i in range(1, 41):                                   # every charger taken, as on a busy morning
        db.val(_car(i, 80 + (i % 16), ("ipace", "zoox", "mody")[i % 3]))
    before = _queue(db)
    rc, err = db.file(M0601)
    assert rc == 0, err
    after = _queue(db)
    assert before["pending"] == after["pending"] == 40
    # the same energy, delivered at the rate the batteries take: the first half hour is forecast well under 0444's
    assert after["load"][0] < 0.8 * before["load"][0], (before["load"][:3], after["load"][:3])
    assert abs(sum(before["load"]) - sum(after["load"])) < 1
    # each car near full on a fast charger: a quarter of 0444's 0.60 x LEAST(inlet, 250) or less
    for i in range(1, 41):
        cls = ("ipace", "zoox", "mody")[i % 3]
        inlet = {"ipace": 100, "zoox": 200, "mody": 250}[cls]
        enc = float(db.val(f"SELECT public.ottoq_queue_job_inlet_kw('b0000000-0000-0000-0000-{i:012d}', {80 + (i % 16)})"))
        rate = enc if enc <= 30 else enc * 0.60
        assert rate <= 0.60 * min(inlet, 250) / 4, (i, cls, rate)


def test_after_0601_a_forecast_rate_never_rises(db):
    db.val(FLEET)
    # a Model Y at 15% charging to 100: its battery averages under 0444's 150 kW, so it is forecast lower, not higher
    db.val(_car(1, 15, "mody"))
    # a car whose owner set 40%, at 10%: its battery takes more than 0.60 x inlet all the way, so 0444's rate stands
    db.val(_car(2, 10, "ipace"))
    db.val("UPDATE public.vehicles SET target_soc = 40 WHERE id = 'b0000000-0000-0000-0000-000000000002'")
    before = _queue(db)
    rc, err = db.file(M0601)
    assert rc == 0, err
    enc1 = float(db.val("SELECT public.ottoq_queue_job_inlet_kw('b0000000-0000-0000-0000-000000000001', 15)"))
    enc2 = float(db.val("SELECT public.ottoq_queue_job_inlet_kw('b0000000-0000-0000-0000-000000000002', 10)"))
    assert enc1 * 0.60 < 150 and min(100, enc2) == 100
    after = _queue(db)
    assert after["load"][0] < before["load"][0] and abs(sum(before["load"]) - sum(after["load"])) < 1
    # at target, or unknown: no rate, and LEAST keeps the inlet
    assert db.val("SELECT public.ottoq_queue_job_inlet_kw('b0000000-0000-0000-0000-000000000001', 100) IS NULL") == "t"
    assert db.val("SELECT public.ottoq_queue_job_inlet_kw(gen_random_uuid(), 50) IS NULL") == "t"
    assert _md5(db, "public.ottoq_ev_queue_schedule(numeric[],numeric[],numeric[],numeric[],numeric[],numeric,integer)") \
        == "bb2a1dce2e7d984bb8707dea1873d137"


def _rate_function_from_0573():
    """0573's calibrated charge-rate function, exactly as 0573 creates it (Lane A applies 0573 before 0601)."""
    src = open(M0573).read()
    a = src.index("CREATE OR REPLACE FUNCTION public.ottoq_sim_compute_charge_rate(")
    b = src.index("$function$;", src.index("AS $function$", a) + 13) + len("$function$;")
    return src[a:b]


def test_0601_holds_on_0573s_calibrated_curves_too(db):
    # the twin's cars with 0573's vehicle facts, near full, on 0573's measured curves
    db.val(_rate_function_from_0573())
    db.val(FLEET)
    facts = {"ipace": (84.7, 104), "mody": (75, 250), "zoox": (133, 200)}
    for i in range(1, 31):
        cls = ("ipace", "zoox", "mody")[i % 3]
        kwh, kw = facts[cls]
        db.val(f"INSERT INTO public.vehicles VALUES ('b0000000-0000-0000-0000-{i:012d}', '{DEPOT}', "
               f"'staged_awaiting_service', {86 + (i % 12)}, 100, {kwh}, {kw})")
    before = _queue(db)
    rc, err = db.file(M0601)                                    # its V2 asserts the invariants on this curve
    assert rc == 0, err
    after = _queue(db)
    assert after["load"][0] < before["load"][0] and abs(sum(before["load"]) - sum(after["load"])) < 1
    # a calibrated I-PACE at 90% takes about 16 kW of the 62.4 0444 forecast; a median-curve car far more than 15
    ipace = float(db.val("SELECT public.ottoq_queue_job_inlet_kw('b0000000-0000-0000-0000-000000000003', 90)"))
    zoox = float(db.val("SELECT public.ottoq_queue_job_inlet_kw('b0000000-0000-0000-0000-000000000001', 90)"))
    assert 10 < ipace <= 30 < zoox * 0.60 < 0.60 * 200


def test_0601_a_battery_that_takes_more_than_0444s_rate_keeps_0444s(db):
    # The twin's Zoox run at a 100 kW inlet (2026-10-02). On 0573's curve one takes a little more from 90% to 100% than
    # 0444's 0.60 x 100 = 60 kW, so the forecast's LEAST keeps 0444's 60. 0601's first live apply refused on exactly these
    # cars: its V2 judged the helper's own rate instead of the rate the forecast charges. An I-PACE keeps V2's "at least
    # one lower" honest.
    db.val(_rate_function_from_0573())
    db.val(FLEET)
    for i in range(1, 9):
        db.val(f"INSERT INTO public.vehicles VALUES ('b0000000-0000-0000-0000-{i:012d}', '{DEPOT}', "
               f"'staged_awaiting_service', 90, 100, 133, 100)")
    db.val(f"INSERT INTO public.vehicles VALUES ('b0000000-0000-0000-0000-000000000009', '{DEPOT}', "
           f"'staged_awaiting_service', 90, 100, 84.7, 104)")
    before = _queue(db)
    rc, err = db.file(M0601)
    assert rc == 0, err
    zoox = [float(db.val(f"SELECT public.ottoq_queue_job_inlet_kw('b0000000-0000-0000-0000-{i:012d}', 90)"))
            for i in range(1, 9)]
    assert any(z * 0.60 > 60 for z in zoox)                 # some batteries take more than 0444's 60 kW
    assert all(min(100, z) * 0.60 <= 60 for z in zoox)      # and the forecast's LEAST never charges more than 0444's
    after = _queue(db)
    assert after["load"][0] < before["load"][0] and abs(sum(before["load"]) - sum(after["load"])) < 1


def test_0601_refuses_in_flight_twice_and_rolls_back(db):
    db.val("UPDATE public.stub_in_flight SET n = 1")
    rc, err = db.file(M0601)
    assert rc != 0 and "0601 P0" in err
    db.val("UPDATE public.stub_in_flight SET n = 0")
    rc, err = db.file(M0601)
    assert rc == 0, err
    rc, err = db.file(M0601)
    assert rc != 0 and "0601 P1: already applied" in err
    db.val("""DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0601_pre'
                AND object_name = 'ottoq_forecast_ev_queue_kw' ORDER BY snapshot_id DESC LIMIT 1); END $$;
              DROP FUNCTION public.ottoq_queue_job_inlet_kw(uuid, numeric);
              DELETE FROM public.ottoq_cert_lineage
               WHERE name = '0601_the_battery_forecast_charges_a_waiting_car_at_the_rate_its_battery_accepts'""")
    assert _md5(db, QUEUE_SIG) == QUEUE_MD5
    rc, err = db.file(M0601)
    assert rc == 0, err
