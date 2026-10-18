"""db/migrations/0746, EXECUTED: the twin times a car's work in a wash bay by the work, and can run robotic lanes.

WHY THIS EXISTS. The twin's bays worked for as long as the car's booking had left: the engine books a walk-in wash for
9 minutes at one tick, the twin seats the car at the next, and the car washes for the 4 minutes that remain; a detail
got 20 of its 25 (G460). 0746 adds the world's own minutes for a seat and a pass that times each new seat by them, at
the depot's crews' times (dial wash_lane_physics 1) or as robotic lanes (2), and a staff gate that drops the wash
supervisors from the lane's limit at 2. Every claim in 0746's header that a test can execute is executed here, on the
scratch PostgreSQL, against the live bodies of everything the new functions call and of the charge-off wash admission
they patch (tests/fixtures/robotic_wash_stub.sql, md5 asserted as read on 2026-10-17). The new functions are created
from 0746's own text, byte for byte:
  - at the dial's default the gate is the depot's wash supervisors, the world times nothing and no car is touched;
  - at 1 a wash seat is timed at the crews' 9 minutes times the deal's draw, from the minute the car entered the bay, and
    its bay need's timer moves with it; a seat the service flow made keeps the minutes STEP 2 gave it (the same card);
    a second pass changes nothing, and a new seat is timed again;
  - at 2 a wash takes the robotic 5.0 minutes within 15% and a detail 16.5 within 20%, the robotic minutes are dials,
    and the same car seated at the same sim-minute draws the same factor at 1 and at 2;
  - the service bay is never timed, and a bay need bound to an earlier timer is left unbound;
  - the charge-off wash admission, patched with 0746's anchor, admits a third car at 2 where two supervisors held it
    before, and is unchanged at the default; less its insertion it is the live body.
The service flow's and the decide's patches are proven on their live bodies by 0746's V1 at apply.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import hashlib
import os
import re
import subprocess
import sys
import tempfile
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)

ROOT = base.ROOT
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "robotic_wash_stub.sql")
M0746 = os.path.join(ROOT, "db", "migrations", "0746_robotic_wash_lanes_and_bay_work_timed_by_the_work.sql")
DEPOT = base.DEPOT
RUN = "a0000000-0000-0000-0000-000000000746"
RUN2 = "a0000000-0000-0000-0000-000000007462"
START = "2026-09-01 11:00:00+00"
T = "2026-09-01 12:00:00+00"
SEED = 686364201590009433

DISP = "public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)"
# the live bodies the fixture carries (md5 of prosrc, read from the live catalog on 2026-10-17)
LIVE = {
    "public.ottoq_crn_draw(bigint,text,text,integer,bigint)": "f41569b4516d943dcaced5745e62c57b",
    "public.ottoq_sample_calibrated(text,text,bigint,text)": "8e9ac0861143cb73a78e8290f2ed4480",
    "public.ottoq_twin_deal(uuid,text,text,timestamp with time zone,integer,bigint,text)":
        "c1ada6eddbb0474e0c1325862fab8d04",
    "twin.ottoq_sim_clock_salt(uuid,timestamp with time zone)": "0eef7e15309ba4c7546201e82d36e452",
    "twin.ottoq_sim_service_minutes(uuid,text,numeric)": "4b50e2f4d1dc4c7bfcd54dd92b65b99c",
    "twin.ottoq_sim_lane_capacity(uuid,text,integer)": "ef28379b407a30e118837a3b6cb618e4",
    "public.ottoq_depot_staffing_count(uuid,text)": "b8814784deaea5ef2121f7bb6632dcc9",
    "public.ottoq_visit_wants_detail(uuid)": "9f34be03a1e76e53a2a4be2ad03da1a5",
    "public.ottoq_flag_needs_service(jsonb)": "4a4b34dbc25397403462a492c1827546",
    DISP: "9e6ca1d95a3053ce4f50901cb723c0d5",
}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0746-{name}"))


def _migration():
    with open(M0746) as f:
        return f.read()


def _new_functions_sql():
    """0746's dials and its three new functions, exactly as the migration writes them."""
    text = _migration()
    start = text.index("-- ── (a) the dials ──")
    end = text.index("-- ── the three readers ──")
    return text[start:end]


def _anchor(seq):
    text = _migration()
    old = re.search(rf"\$o{seq}\$(.*?)\$o{seq}\$", text, re.S).group(1)
    new = re.search(rf"\$n{seq}\$(.*?)\$n{seq}\$", text, re.S).group(1)
    return old, new


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_rwt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, FIXTURE):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_rw_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _create(d):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(_new_functions_sql())
        path = f.name
    try:
        rc, err = d.file(path)
    finally:
        os.remove(path)
    assert rc == 0, f"0746's functions did not create: {err}"


def _run(d, run=RUN, status="running"):
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, random_seed, started_at, sim_clock_start,
                                                 sim_clock_current)
              VALUES ('{run}', '{DEPOT}', '{status}', {SEED}, '{START}', '{START}', '{T}')""")


def _dial(d, key, value, run=RUN):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{run}', '{key}', {value}, 'test', now())
              ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value""")


def _car(d, name, state, seat_min_ago=3, ends_min_ahead=1, bound=True):
    """A car in a bay, seated seat_min_ago before T, its timer the booking's end; its bay need bound to that timer."""
    vid = _id(name)
    cfg = (f"""jsonb_build_object('svc_step', 'washing',
                 'service_ends_at', ('{T}'::timestamptz + interval '{ends_min_ahead} minutes')::text,
                 'bay_need', jsonb_build_object('svc', 'exterior_wash', 'ends_at',
                   ('{T}'::timestamptz + interval '{ends_min_ahead if bound else ends_min_ahead + 7} minutes')::text))""")
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, last_state_change, config)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', '{name}', '{state}',
                      '{T}'::timestamptz - interval '{seat_min_ago} minutes', {cfg})""")
    return vid


def _cfg(d, vid):
    return d.json(f"SELECT config FROM public.vehicles WHERE id = '{vid}'")


def _deal_sql(run, key, vid, seat):
    """The deal's card for a car and its seat, by STEP 2's own expression (an SQL expression, kept exact)."""
    return (f"public.ottoq_twin_deal('{run}', '{key}', '{vid}'::text || ':' || "
            f"twin.ottoq_sim_clock_salt('{run}', '{seat}'::timestamptz), '{seat}'::timestamptz, "
            f"('{seat}'::timestamptz::date - DATE '2020-01-01'), 0)")


def _deal(d, run, key, vid, seat):
    return float(d.val(f"SELECT {_deal_sql(run, key, vid, seat)}"))


def _is(d, vid, expr):
    """The car's recorded minutes equal an exact SQL expression."""
    return d.val(f"""SELECT (config->>'bay_work_min')::numeric = ({expr})
                       FROM public.vehicles WHERE id = '{vid}'""") == "t"


def _seat_of(d, vid):
    return d.val(f"SELECT last_state_change FROM public.vehicles WHERE id = '{vid}'")


def test_the_fixture_carries_the_live_bodies(db):
    for fn, md5 in LIVE.items():
        assert db.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')") == md5, fn


def test_at_the_default_the_gate_is_the_supervisors_and_nothing_is_timed(db):
    _create(db)
    _run(db)
    vid = _car(db, "w1", "in_wash_bay")
    before = _cfg(db, vid)
    assert db.val(f"SELECT public.ottoq_wash_lane_staff_gate('{RUN}', '{DEPOT}')") == "2"
    db.val(f"INSERT INTO public.ottoq_depot_staffing (depot_id, role, headcount) VALUES ('{DEPOT}', 'wash_supervisor', 3)")
    assert db.val(f"SELECT public.ottoq_wash_lane_staff_gate('{RUN}', '{DEPOT}')") == "3"
    assert db.val(f"SELECT twin.ottoq_sim_bay_work_minutes('{RUN}', '{vid}', 'in_wash_bay', '{T}') IS NULL") == "t"
    assert db.val(f"SELECT twin.ottoq_sim_time_bay_work('{RUN}', '{DEPOT}', '{T}')") == "0"
    assert _cfg(db, vid) == before
    assert db.val("SELECT count(*) FROM public.ottoq_variability_cards") == "0"


def test_at_one_a_wash_is_timed_by_the_crews_from_its_seat(db):
    _create(db)
    _run(db)
    _dial(db, "wash_lane_physics", 1)
    vid = _car(db, "w1", "in_wash_bay", seat_min_ago=3, ends_min_ahead=1)
    old = _cfg(db, vid)
    assert db.val(f"SELECT twin.ottoq_sim_time_bay_work('{RUN}', '{DEPOT}', '{T}')") == "1"
    cfg = _cfg(db, vid)
    seat = _seat_of(db, vid)
    f = _deal(db, RUN, "wash_time", vid, seat)
    assert 0.7 <= f <= 1.3
    card = _deal_sql(RUN, "wash_time", vid, seat)
    assert _is(db, vid, f"round(9 * {card}, 3)")
    want_end = db.val(f"SELECT ('{seat}'::timestamptz + make_interval(secs => round(9 * {card}, 3) * 60))::text")
    assert cfg["service_ends_at"] == want_end
    assert cfg["bay_need"]["ends_at"] == cfg["service_ends_at"]       # still bound, so STEP 1 credits the seat
    assert cfg["bay_need"]["svc"] == "exterior_wash"
    assert db.val(f"SELECT '{cfg['bay_work_seat']}'::timestamptz = '{seat}'::timestamptz") == "t"
    assert cfg["bay_plan_ends_at"] == old["service_ends_at"]          # the engine's plan, kept beside it
    # once per seat: a second pass changes nothing
    assert db.val(f"SELECT twin.ottoq_sim_time_bay_work('{RUN}', '{DEPOT}', '{T}')") == "0"
    assert _cfg(db, vid) == cfg
    # a new seat is timed again, from its own minute
    db.val(f"UPDATE public.vehicles SET last_state_change = '{T}'::timestamptz + interval '20 minutes' WHERE id = '{vid}'")
    assert db.val(f"SELECT twin.ottoq_sim_time_bay_work('{RUN}', '{DEPOT}', '{T}'::timestamptz + interval '25 minutes')") == "1"
    assert _cfg(db, vid)["bay_work_seat"] != cfg["bay_work_seat"]


def test_at_one_a_seat_the_service_flow_made_keeps_its_minutes(db):
    _create(db)
    _run(db)
    _dial(db, "wash_lane_physics", 1)
    vid = _car(db, "d1", "in_detail_bay", seat_min_ago=5, ends_min_ahead=20)
    seat = _seat_of(db, vid)
    # STEP 2 deals the card when it seats the car, with its own expression; 0746 must draw the same card
    card = _deal_sql(RUN, "detail_time", vid, seat)
    step2 = f"round(twin.ottoq_sim_service_minutes('{RUN}', 'detail_time', 25) * {card}, 3)"
    db.val(f"SELECT {card}")                                     # STEP 2's seat deals the card
    cards = db.val("SELECT count(*) FROM public.ottoq_variability_cards")
    assert db.val(f"SELECT twin.ottoq_sim_time_bay_work('{RUN}', '{DEPOT}', '{T}')") == "1"
    assert db.val("SELECT count(*) FROM public.ottoq_variability_cards") == cards   # no new card was dealt
    assert _is(db, vid, step2)


def test_at_two_the_lanes_are_robotic_and_the_draw_is_the_same(db):
    _create(db)
    _run(db)
    _run(db, RUN2)
    _dial(db, "wash_lane_physics", 2)
    _dial(db, "wash_lane_physics", 1, run=RUN2)
    washes, details = [], []
    for i in range(24):
        w = _car(db, f"rw{i}", "in_wash_bay", seat_min_ago=i % 5)
        washes.append(w)
    for i in range(24):
        details.append(_car(db, f"rd{i}", "in_detail_bay", seat_min_ago=i % 5))
    assert db.val(f"SELECT twin.ottoq_sim_time_bay_work('{RUN}', '{DEPOT}', '{T}')") == "48"
    for vid in washes:
        seat = _seat_of(db, vid)
        card = _deal_sql(RUN, "wash_time", vid, seat)
        assert _is(db, vid, f"round(GREATEST(1, 5.0 * (1 + ({card} - 1) * 0.5)), 3)")
        m = float(_cfg(db, vid)["bay_work_min"])
        assert 4.25 <= m <= 5.75
        # the same car at the same sim-minute of a same-seed run draws the same factor at 1
        assert db.val(f"SELECT {card} = {_deal_sql(RUN2, 'wash_time', vid, seat)}") == "t"
    for vid in details:
        seat = _seat_of(db, vid)
        card = _deal_sql(RUN, "detail_time", vid, seat)
        assert _is(db, vid, f"round(GREATEST(1, 16.5 * (1 + ({card} - 1) * 2.0 / 3.0)), 3)")
        m = float(_cfg(db, vid)["bay_work_min"])
        assert 13.2 <= m <= 19.8
    spread = db.json("""SELECT json_build_array(min((config->>'bay_work_min')::numeric), max((config->>'bay_work_min')::numeric))
                          FROM public.vehicles WHERE current_state = 'in_wash_bay'""")
    assert float(spread[1]) - float(spread[0]) > 0.3          # the cars differ: the world varies, unlike before


def test_the_robotic_minutes_are_dials(db):
    _create(db)
    _run(db)
    _dial(db, "wash_lane_physics", 2)
    _dial(db, "robotic_wash_min", 6.0)
    _dial(db, "robotic_detail_min", 12.0)
    w = _car(db, "w1", "in_wash_bay")
    dd = _car(db, "d1", "in_detail_bay")
    db.val(f"SELECT twin.ottoq_sim_time_bay_work('{RUN}', '{DEPOT}', '{T}')")
    cw = _deal_sql(RUN, "wash_time", w, _seat_of(db, w))
    cd = _deal_sql(RUN, "detail_time", dd, _seat_of(db, dd))
    assert _is(db, w, f"round(GREATEST(1, 6.0 * (1 + ({cw} - 1) * 0.5)), 3)")
    assert _is(db, dd, f"round(GREATEST(1, 12.0 * (1 + ({cd} - 1) * 2.0 / 3.0)), 3)")


def test_the_service_bay_is_never_timed_and_an_unbound_need_stays_unbound(db):
    _create(db)
    _run(db)
    _dial(db, "wash_lane_physics", 2)
    svc = _car(db, "s1", "in_service_bay")
    before = _cfg(db, svc)
    stale = _car(db, "w1", "in_wash_bay", bound=False)
    stale_need = _cfg(db, stale)["bay_need"]
    assert db.val(f"SELECT twin.ottoq_sim_bay_work_minutes('{RUN}', '{svc}', 'in_service_bay', '{T}') IS NULL") == "t"
    assert db.val(f"SELECT twin.ottoq_sim_time_bay_work('{RUN}', '{DEPOT}', '{T}')") == "1"
    assert _cfg(db, svc) == before
    cfg = _cfg(db, stale)
    assert cfg["bay_need"] == stale_need                         # bound to an earlier timer: left as it was
    assert cfg["service_ends_at"] != cfg["bay_need"]["ends_at"]


def test_at_two_the_gate_is_none_and_least_ignores_it(db):
    _create(db)
    _run(db)
    _dial(db, "wash_lane_physics", 2)
    assert db.val(f"SELECT public.ottoq_wash_lane_staff_gate('{RUN}', '{DEPOT}') IS NULL") == "t"
    assert db.val(f"SELECT LEAST(3, public.ottoq_wash_lane_staff_gate('{RUN}', '{DEPOT}'))") == "3"
    _dial(db, "wash_lane_physics", 1)
    assert db.val(f"SELECT LEAST(3, public.ottoq_wash_lane_staff_gate('{RUN}', '{DEPOT}'))") == "2"


def _patch_disposition(d):
    old, new = _anchor(4)
    d.val(f"""DO $p$
              DECLARE v_def text := pg_get_functiondef('{DISP}'::regprocedure); n int;
              BEGIN
                n := (length(v_def) - length(replace(v_def, $a${old}$a$, ''))) / length($a${old}$a$);
                IF n <> 1 THEN RAISE EXCEPTION 'anchor 4 matches % times', n; END IF;
                EXECUTE replace(v_def, $a${old}$a$, $b${new}$b$);
              END $p$""")
    return old, new


def _two_in_the_lane_and_one_waiting(d):
    for i, code in enumerate(["WSH-1", "WSH-2", "WSH-3"]):
        d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, display_name, status, distance_from_entrance)
                  VALUES ('{_id(code)}', '{DEPOT}', '{code}', 'wash_bay', '{code}', 'available', {i})""")
    _car(d, "in1", "in_wash_bay")
    _car(d, "in2", "in_detail_bay")
    vid = _id("next")
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, last_state_change, config)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', 'next', 'charge_complete_holding', '{T}', '{{}}')""")
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, status, atoms)
              VALUES ('{vid}', '{RUN}', '{DEPOT}', 'open',
                      '[{{"svc": "exterior_wash", "must_do": true, "status": "pending", "est_min": 8}}]')""")
    return vid


def _dispose(d, vid):
    return d.json(f"""SELECT public.ottoq_l2_propose_charge_disposition('{vid}', '{DEPOT}',
                              jsonb_build_object('sim_run_id', '{RUN}'))""")


def test_the_charge_off_wash_admission_admits_a_third_car_on_robotic_lanes(db):
    _create(db)
    _run(db)
    vid = _two_in_the_lane_and_one_waiting(db)
    _dial(db, "wash_lane_physics", 2)
    # the live body: two supervisors hold the third car even on robotic lanes
    live = _dispose(db, vid)
    assert live["abstain"] is True and live["reason"] == "wash_lane_full_hold"
    old, new = _patch_disposition(db)
    # less its insertion it is the live body
    src = db.json(f"SELECT to_json(prosrc) FROM pg_proc WHERE oid = '{DISP}'::regprocedure")
    assert hashlib.md5(src.replace(new, old).encode()).hexdigest() == LIVE[DISP]
    got = _dispose(db, vid)
    assert got["verb"] == "admit_wash" and got["rationale"]["wash_cap"] == 3
    # at the default the patched body holds the car, exactly as the live one does
    _dial(db, "wash_lane_physics", 0)
    held = _dispose(db, vid)
    assert held == live
