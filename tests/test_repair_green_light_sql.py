"""db/migrations/0753, EXECUTED: a repair waits for its technician's green-light at every door.

WHY THIS EXISTS. OTTO-Q plans every fault repair as needing a technician's green-light before the car goes back to
work, and the decide's redeploy door waits for one; but nothing asked for one after a bay repair, and every other door
(the deploy planner's, the twin's dispatcher, the dispatch trigger) tests public.ottoq_departure_clear, which never
asked. So every repaired car left through the planner's door with no green-light (G467, db/checks/0457). 0753 asks when
the repair is done, makes the one departure test wait for the answer, and re-opens a repair whose green-light is
declined. Every claim in 0753's header about them is executed here, on the scratch PostgreSQL, against the triggers and
the departure test exactly as 0753 writes and patches them, through the live departure test and atom marker and the
twin technician's scan as 0751 leaves it (tests/fixtures/repair_green_light_stub.sql and
tests/fixtures/opportunistic_scan_stub.sql, md5 asserted):
  - at the dial's default a repair asks nothing and the departure test is today's;
  - with the dial on, a repair done at a twin-fed depot asks with the twin's own technician delay and expiry, the car is
    not clear to leave until the question is approved, and the twin's technician approves it on its own draw;
  - a declined green-light re-opens the repair; done again, it is asked again;
  - at a depot a real feed drives the question is a person's: asked at the repair's end, never expiring, passed over by
    the scan until a person answers, and their verdict clears the car;
  - one question at a time for a car, and none for work that needs no green-light;
  - the dial is the run's: another run's repair asks nothing;
  - no API role can call the trigger functions.
The departure test's patch is proven on its live body by 0753's V1 at apply (and here, in the template's setup), and the
whole path on live by its V3. It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import tempfile
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)

ROOT = base.ROOT
SCAN = os.path.join(ROOT, "tests", "fixtures", "opportunistic_scan_stub.sql")
STUB = os.path.join(ROOT, "tests", "fixtures", "repair_green_light_stub.sql")
M0751 = os.path.join(ROOT, "db", "migrations", "0751_in_production_only_a_person_answers_a_technician_question.sql")
M0753 = os.path.join(ROOT, "db", "migrations", "0753_a_repair_waits_for_its_green_light_at_every_door.sql")
DEPOT = base.DEPOT
RUN = "a0000000-0000-0000-0000-000000000753"
OTHER = "a0000000-0000-0000-0000-00000000753b"
T = "2026-09-01 15:00:00+00"
LIVE = {"ottoq_departure_clear": "ac79f1b4109f9eae3e821fdc20e6dca0",
        "ottoq_mark_visit_atoms_done": "be7dc4f2393b0b451543e12450f2df88",
        "ottoq_opportunistic_scan": "fce0e0609ef96ad49de836f95620b1f1",
        "ottoq_sim_seeded_random": "237b754ac865e17e0876a5df7af979b2"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0753-{name}"))


def _slice(path, start, end):
    with open(path) as f:
        text = f.read()
    return "BEGIN;\n" + text[text.index(start):text.index(end)] + "COMMIT;\n"


def _apply(d, sql, what):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(sql)
        path = f.name
    try:
        rc, err = d.file(path)
    finally:
        os.remove(path)
    assert rc == 0, f"{what} did not apply: {err}"


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_rgt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, SCAN, STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        for fn, md5 in LIVE.items():
            got = d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE proname = '{fn}'")
            assert got == md5, f"{fn} is not the live body read (md5 {got})"
        _apply(d, _slice(M0751, "-- ── the scan: only a depot the twin feeds has a simulated technician ──",
                         "-- ── V2: on live, rolled back by its own raise ──"), "0751's patch of the scan")
        _apply(d, _slice(M0753, "-- ── (a) the dial ──", "-- ── V2 and V3: on live, rolled back by its own raise ──"),
               "0753's dial, triggers and departure test")
        for run in (RUN, OTHER):
            d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, random_seed, started_at,
                                                        sim_clock_start, sim_clock_current)
                      VALUES ('{run}', '{DEPOT}', '{'running' if run == RUN else 'completed'}', 42,
                              '{T}'::timestamptz - interval '4 hours', '{T}'::timestamptz - interval '4 hours', '{T}')""")
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_rg_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _dial(d, value=1, run=RUN):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{run}', 'repair_needs_its_green_light', {value}, 'test', now())
              ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value""")


def _plan(d, p):
    d.val("DELETE FROM public.scan_stub_plan")
    d.val(f"""INSERT INTO public.scan_stub_plan (plan) VALUES ('{{"greenlight_approve_p": {p}}}'::jsonb)""")


def _car(d, name):
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, last_state_change,
                                           current_soc, target_soc, config)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', '{name}', 'staged_for_departure',
                      '{T}'::timestamptz - interval '1 hour', 100, 100, '{{}}'::jsonb)""")
    return vid


def _repair(svc="fault_repair", greenlight=True):
    a = {"svc": svc, "status": "pending", "must_do": True, "concurrency": "bay", "requires_bay": "service_bay",
         "est_min": 60}
    if greenlight:
        a["requires_tech_greenlight"] = True
    return a


def _visit(d, car, atoms, run=RUN):
    return d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms,
                                                           status, source)
                     VALUES ('{car}', '{run}', '{DEPOT}', '{T}'::timestamptz - interval '1 hour', 'v-{car}-{run[-4:]}',
                             '{json.dumps(atoms)}'::jsonb, 'in_progress', 'test')
                     RETURNING visit_id""")


def _mark(d, car, svcs, minutes=0):
    arr = "ARRAY[" + ",".join(f"'{s}'" for s in svcs) + "]::text[]"
    return d.val(f"SELECT public.ottoq_mark_visit_atoms_done('{car}', {arr}, '{T}'::timestamptz + interval '{minutes} minutes')")


def _clear(d, car, minutes=0, run=RUN):
    return d.val(f"SELECT public.ottoq_departure_clear('{car}', '{run}', '{T}'::timestamptz + interval '{minutes} minutes', false)")


def _questions(d, car):
    out = d.val(f"""SELECT COALESCE(jsonb_agg(jsonb_build_object(
                             'id', approval_id, 'status', status, 'decide_after', decide_after, 'expires_at', expires_at,
                             'visit_id', visit_id, 'asked_by', payload ->> 'asked_by', 'priority', priority,
                             'decided_by', decided_by) ORDER BY created_at, requested_at, approval_id), '[]'::jsonb)
                    FROM public.ottoq_ops_approvals WHERE vehicle_id = '{car}'""")
    return json.loads(out)


def _scan(d, minutes):
    d.val(f"SELECT twin.ottoq_opportunistic_scan('{RUN}', '{T}'::timestamptz + interval '{minutes} minutes')")


def _atom_status(d, visit):
    return d.val(f"""SELECT string_agg(a->>'status', ',' ORDER BY a->>'svc') FROM public.ottoq_visit_needs vn,
                     jsonb_array_elements(vn.atoms) a WHERE vn.visit_id = '{visit}'""")


def test_the_departure_test_is_patched_from_its_live_body(db):
    # V1 ran in the template's patch transaction and raised nothing: the test less its insertion is ac79f1b4
    assert db.val("""SELECT position('repair_needs_its_green_light' in prosrc) > 0 FROM pg_proc
                      WHERE proname = 'ottoq_departure_clear'""") == "t"


def test_at_the_default_a_repair_asks_nothing_and_the_car_may_leave(db):
    car = _car(db, "AV-1")
    _visit(db, car, [_repair()])
    assert _clear(db, car) == "f"  # the repair is open
    _mark(db, car, ["fault_repair"])
    assert _questions(db, car) == []
    assert _clear(db, car) == "t"


def test_a_twin_fed_repair_asks_with_the_twins_times_and_waits_for_the_answer(db):
    _dial(db)
    car = _car(db, "AV-2")
    visit = _visit(db, car, [_repair()])
    _mark(db, car, ["fault_repair"], 0)
    qs = _questions(db, car)
    assert len(qs) == 1 and qs[0]["status"] == "pending" and qs[0]["visit_id"] == visit
    assert qs[0]["asked_by"] == "0753" and qs[0]["priority"] == "high"
    want = db.val(f"""SELECT to_jsonb('{T}'::timestamptz + (15 + floor(twin.ottoq_sim_seeded_random(42, '{car}:glDelay') * 45))::int
                                      * interval '1 minute')""").strip('"')
    assert db.val(f"SELECT '{qs[0]['decide_after']}'::timestamptz = '{want}'::timestamptz") == "t"
    assert db.val(f"SELECT '{qs[0]['expires_at']}'::timestamptz = '{T}'::timestamptz + interval '120 minutes'") == "t"
    assert _clear(db, car) == "f"
    _plan(db, 1.0)
    _scan(db, 61)
    assert _questions(db, car)[0]["status"] == "approved"
    assert _questions(db, car)[0]["decided_by"] == "twin_tech_sim"
    assert _clear(db, car, 61) == "t"


def test_a_declined_green_light_reopens_the_repair_and_it_is_asked_again(db):
    _dial(db)
    car = _car(db, "AV-3")
    visit = _visit(db, car, [_repair()])
    _mark(db, car, ["fault_repair"], 0)
    _plan(db, 0.0)
    _scan(db, 61)
    assert _questions(db, car)[0]["status"] == "declined"
    assert _atom_status(db, visit) == "pending"
    assert db.val(f"""SELECT a -> 'reopened' -> 0 ->> 'reason' FROM public.ottoq_visit_needs vn,
                      jsonb_array_elements(vn.atoms) a WHERE vn.visit_id = '{visit}'""") == "green_light_declined"
    assert _clear(db, car, 61) == "f"
    _mark(db, car, ["fault_repair"], 150)
    qs = _questions(db, car)
    assert [q["status"] for q in qs] == ["declined", "pending"]
    _plan(db, 1.0)
    _scan(db, 211)
    assert _questions(db, car)[1]["status"] == "approved" and _clear(db, car, 211) == "t"


def test_a_real_feeds_question_is_a_persons(db):
    _dial(db)
    db.val(f"UPDATE public.depots SET feed_mode = 'external' WHERE id = '{DEPOT}'")
    car = _car(db, "AV-4")
    _visit(db, car, [_repair()])
    _mark(db, car, ["fault_repair"], 10)
    q = _questions(db, car)[0]
    assert db.val(f"SELECT '{q['decide_after']}'::timestamptz = '{T}'::timestamptz + interval '10 minutes'") == "t"
    assert q["expires_at"] == "infinity"
    _plan(db, 1.0)
    _scan(db, 600)
    assert _questions(db, car)[0]["status"] == "pending" and _clear(db, car, 600) == "f"
    db.val(f"""UPDATE public.ottoq_ops_approvals
                  SET payload = payload || '{{"operator_verdict": {{"verdict": "approved", "by": "pulse"}}}}'::jsonb
                WHERE approval_id = '{q['id']}'""")
    _scan(db, 601)
    q = _questions(db, car)[0]
    assert q["status"] == "approved" and q["decided_by"] == "operator:pulse"
    assert _clear(db, car, 601) == "t"


def test_one_question_at_a_time_and_none_for_work_that_needs_no_green_light(db):
    _dial(db)
    car = _car(db, "AV-5")
    visit = _visit(db, car, [_repair(), _repair("cosmetic_repair"), _repair("mechanical_pm", greenlight=False)])
    _mark(db, car, ["fault_repair", "cosmetic_repair", "mechanical_pm"], 0)
    assert len(_questions(db, car)) == 1
    other = _car(db, "AV-6")
    _visit(db, other, [_repair("mechanical_pm", greenlight=False)])
    _mark(db, other, ["mechanical_pm"], 0)
    assert _questions(db, other) == [] and _clear(db, other) == "t"
    assert _atom_status(db, visit) == "done,done,done"


def test_the_dial_is_the_runs(db):
    _dial(db, 1, RUN)
    car = _car(db, "AV-7")
    _visit(db, car, [_repair()], run=OTHER)
    # the atom marker reads the running run's visits only: with no run live at the depot it marks the other run's
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{OTHER}'")
    _mark(db, car, ["fault_repair"], 0)
    assert _questions(db, car) == [] and _clear(db, car, 0, run=OTHER) == "t"


def test_no_api_role_calls_the_trigger_functions(db):
    for fn in ("public.ottoq_ask_repair_green_light()", "public.ottoq_reopen_declined_repair()"):
        for role in ("anon", "authenticated"):
            assert db.val(f"SELECT has_function_privilege('{role}', '{fn}', 'EXECUTE')") == "f", (fn, role)
