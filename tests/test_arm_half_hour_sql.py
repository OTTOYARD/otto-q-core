"""db/migrations/0754, EXECUTED: a billed half hour holds thirty minutes.

WHY THIS EXISTS. The sweep scorer takes a run's demand peak as the highest mean of grid import over [t, t + 30 minutes)
for every snapshot t, and at the end of a run that window holds what is left of the day, one to three samples, so a
single late tick could be billed as the month's half hour (G469, db/checks/0451 §17: 8 of 69 arms). 0754 counts a window
only when it starts at least thirty minutes before the day ends, as the scorer integrates it. Every claim in 0754's
header about the two scorers is executed here, on the scratch PostgreSQL, against both patched exactly as 0754 patches
them, from their live bodies (tests/fixtures/arm_half_hour_stub.sql, md5 asserted):
  - before the patch a two-sample spike at the day's end is billed as the half hour, after it the last full half hour is;
  - a spike that fills the day's last thirty minutes is still billed, whole;
  - at 2.5 sim-minutes a tick the last full half hour holds twelve samples;
  - at offset 0 the profile equals the scorer, before and after;
  - the energy, cost and battery sums do not move;
  - a day shorter than half an hour has no half hour.
The patch's body is proven on live by 0754's V1 at apply, and the whole reading on live by its V2.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import tempfile
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "arm_half_hour_stub.sql")
M0754 = os.path.join(ROOT, "db", "migrations", "0754_a_billed_half_hour_holds_thirty_minutes.sql")
DEPOT = base.DEPOT
T0 = "2026-09-01 11:00:00+00"   # 6 AM CT, a summer month on the twin depot's tariff
LIVE = {"ottoq_arm_peak_profile": "917cfc1b667ce33289602438d298e218",
        "ottoq_dial_arm_metrics": "8a852c7d1394ffbc3fc56296da3d8dbb"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _run_id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0754-{name}"))


# Each day: (name, step in minutes, samples, the kW of sample i counted from 1 at t0 + step)
DAYS = {
    "late_spike": (5.0, 144, "CASE WHEN i >= 143 THEN 3000 ELSE 800 END"),      # the last two samples
    "full_late_half_hour": (5.0, 144, "CASE WHEN i >= 139 THEN 3000 ELSE 800 END"),  # the last six
    "fine_tick_spike": (2.5, 288, "CASE WHEN i >= 285 THEN 3000 ELSE 800 END"),  # the last four of 288
    "too_short": (5.0, 5, "800"),
}


def _seed_days(d):
    for name, (step, n, kw) in DAYS.items():
        run = _run_id(name)
        d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, sim_clock_start, sim_clock_current, tick_count)
                  VALUES ('{run}', '{DEPOT}', '{T0}', '{T0}'::timestamptz + interval '{step * n} minutes', {n})""")
        d.val(f"""INSERT INTO public.site_energy_snapshots (sim_run_id, depot_id, timestamp, grid_import_kw, bess_output_kw,
                                                          current_rate_per_kwh)
                  SELECT '{run}', '{DEPOT}', '{T0}'::timestamptz + make_interval(secs => i * {step} * 60),
                         {kw}, CASE WHEN i % 7 = 0 THEN -120 WHEN i % 5 = 0 THEN 90 ELSE 0 END, 0.07 + (i % 3) * 0.01
                    FROM generate_series(1, {n}) AS i""")


def _patch_sql():
    """0754's patch of both scorers and its V1, exactly as the migration writes them, in one transaction."""
    with open(M0754) as f:
        text = f.read()
    part = text[text.index("-- ── the scorers: a half hour holds thirty minutes of samples ──"):
                text.index("-- ── V2: on live, read-only, on the latest sweep arm whose run is still on record ──")]
    return "BEGIN;\n" + part + "COMMIT;\n"


def _score(d, table):
    d.val(f"""CREATE TABLE {table} AS
              SELECT r.sim_run_id, public.ottoq_arm_peak_profile(r.sim_run_id, r.depot_id) AS prof,
                     public.ottoq_dial_arm_metrics(r.sim_run_id, r.depot_id, 1400) AS met
                FROM public.ottoq_sim_runs r""")


@pytest.fixture(scope="module")
def db():
    name = f"ottoq_ahh_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"arm_half_hour_stub.sql did not load: {err}"
        for fn, md5 in LIVE.items():
            got = d.val(f"""SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                            WHERE n.nspname = 'public' AND p.proname = '{fn}'""")
            assert got == md5, f"public.{fn} is not the live body read (md5 {got})"
        _seed_days(d)
        _score(d, "before_0754")
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
            f.write(_patch_sql())
            path = f.name
        try:
            rc, err = d.file(path)
        finally:
            os.unlink(path)
        assert rc == 0, f"0754's patch did not apply: {err}"
        _score(d, "after_0754")
        yield d
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _read(d, table, name):
    return d.json(f"""SELECT jsonb_build_object('prof', prof, 'met', met) FROM {table}
                      WHERE sim_run_id = '{_run_id(name)}'""")


def test_both_scorers_are_patched_and_each_less_its_replacement_is_its_pre_image(db):
    # V1 ran inside the patch's transaction; here, independently, the stored bodies changed and carry the fix
    for fn, md5 in LIVE.items():
        got = db.val(f"""SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                         WHERE n.nspname = 'public' AND p.proname = '{fn}'""")
        assert got != md5, f"public.{fn} was not patched"
        assert db.val(f"""SELECT position('0754 (G469)' IN p.prosrc) > 0 FROM pg_proc p JOIN pg_namespace n
                            ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = '{fn}'""") == "t"


def test_a_late_spike_was_billed_as_the_half_hour_and_now_is_not(db):
    before = _read(db, "before_0754", "late_spike")
    after = _read(db, "after_0754", "late_spike")
    # before: the window at minute 715 holds two samples at 3,000 kW, and its mean is billed as the half hour
    assert before["prof"]["peak_30min_kw"]["180"] == 3000.0
    assert before["prof"]["starts_min"]["180"] == 715
    assert before["met"]["peak_30min_kw"] == 3000.0
    # after: the last full half hour starts at 695 and holds 695-720, four samples at 800 and two at 3,000
    assert after["prof"]["peak_30min_kw"]["180"] == round((4 * 800 + 2 * 3000) / 6, 1)
    assert after["prof"]["starts_min"]["180"] == 695
    assert after["met"]["peak_30min_kw"] == round((4 * 800 + 2 * 3000) / 6, 1)
    # and the demand charge follows the peak on the depot's own block tariff (summer: 21.40 to 1,000 kW, then 21.78)
    peak = (4 * 800 + 2 * 3000) / 6
    assert abs(after["met"]["demand_charge_usd_month"] - (21.40 * 1000 + 21.78 * (peak - 1000))) < 0.02
    for k in ("0", "30", "60", "90", "120", "180", "240"):
        assert after["prof"]["starts_min"][k] + 30 <= 720 + 5, f"offset {k} starts inside the day's last half hour"


def test_a_spike_that_fills_the_last_half_hour_is_still_billed_whole(db):
    after = _read(db, "after_0754", "full_late_half_hour")
    assert after["prof"]["peak_30min_kw"]["180"] == 3000.0
    assert after["prof"]["starts_min"]["180"] == 695
    assert after["met"]["peak_30min_kw"] == 3000.0


def test_at_two_and_a_half_minutes_the_last_full_half_hour_holds_twelve_samples(db):
    before = _read(db, "before_0754", "fine_tick_spike")
    after = _read(db, "after_0754", "fine_tick_spike")
    assert before["prof"]["peak_30min_kw"]["180"] == 3000.0
    # the day's samples run 2.5 to 720 minutes; the last full half hour starts at 692.5 (rounded to the minute)
    assert after["prof"]["peak_30min_kw"]["180"] == round((8 * 800 + 4 * 3000) / 12, 1)
    assert after["prof"]["starts_min"]["180"] in (692, 693)


def test_at_offset_zero_the_profile_is_the_scorer_before_and_after(db):
    for table in ("before_0754", "after_0754"):
        rows = db.val(f"""SELECT count(*) FROM {table}
                          WHERE (prof #>> '{{peak_30min_kw,0}}')::numeric IS DISTINCT FROM (met ->> 'peak_30min_kw')::numeric
                             OR (prof #>> '{{demand_charge_usd_month,0}}')::numeric
                                IS DISTINCT FROM (met ->> 'demand_charge_usd_month')::numeric""")
        assert rows == "0", f"{table}: the profile at 0 is not the scorer on {rows} days"


def test_the_energy_cost_and_battery_sums_do_not_move(db):
    keys = ("energy_samples", "grid_import_kwh", "energy_cost_usd", "bess_discharged_kwh", "bess_charged_kwh",
            "bess_degradation_usd", "terminal_soc_usd", "soc_end_kwh")
    for name in DAYS:
        before = _read(db, "before_0754", name)["met"]
        after = _read(db, "after_0754", name)["met"]
        for k in keys:
            assert before[k] == after[k], f"{name}: {k} moved, {before[k]} -> {after[k]}"
        # and everything else the scorer returns, but the peak, its demand charge and what carries them
        moved = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
        assert moved <= {"peak_30min_kw", "demand_charge_usd_month", "demand_usd_per_day", "site_cost_usd_per_day"}, moved


def test_a_day_shorter_than_half_an_hour_has_no_half_hour(db):
    before = _read(db, "before_0754", "too_short")
    after = _read(db, "after_0754", "too_short")
    assert before["met"]["peak_30min_kw"] == 800.0      # five samples, 25 minutes, billed as a half hour before
    assert after["met"]["peak_30min_kw"] is None
    assert after["met"]["demand_charge_usd_month"] is None
    assert after["prof"]["peak_30min_kw"]["0"] is None
    assert after["met"]["grid_import_kwh"] == before["met"]["grid_import_kwh"]


def test_0754_refuses_a_scorer_it_did_not_read(db):
    # a scorer that has moved since it was read fails P1, and the migration changes nothing
    name = f"ottoq_ahh_p1_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, err
        d.val("""CREATE OR REPLACE FUNCTION public.ottoq_arm_peak_profile(p_run uuid, p_depot uuid) RETURNS jsonb
                 LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$""")
        d.val("CREATE FUNCTION public.ottoq_certification_in_flight(boolean) RETURNS int LANGUAGE sql AS $$ SELECT 0 $$")
        rc, err = d.file(M0754)
        assert rc != 0 and "0754 P1" in err, err
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
